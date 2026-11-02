"""Host tests for the extra WiFi network set over the API (components/cgdn1_wifi/extra_wifi.h) and its
cgdn1.yaml wiring.

A tiny C++ driver is compiled against the header with the system C++ compiler (skipped when none
is installed) and fed '|'-separated commands over stdin; "\\xNN" in a field is one byte.
"""
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
WIFI_DIR = ROOT / "components" / "cgdn1_wifi"
YAML = (ROOT / "cgdn1.yaml").read_text()

DRIVER = r"""
#include "extra_wifi.h"
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
using namespace cgdn1_wifi;
static std::string unesc(const std::string &s) {
  std::string out;
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '\\' && i + 3 < s.size() && s[i + 1] == 'x') { out += (char) strtoul(s.substr(i + 2, 2).c_str(), nullptr, 16); i += 3; }
    else out += s[i];
  }
  return out;
}
static std::vector<std::string> split(const std::string &s) {
  std::vector<std::string> out; std::string cur;
  for (char c : s) { if (c == '|') { out.push_back(cur); cur.clear(); } else cur += c; }
  out.push_back(cur);
  return out;
}
int main() {
  std::string line;
  while (std::getline(std::cin, line)) {
    auto a = split(line);
    if (a[0] == "K") {
      std::string ssid = unesc(a[1]), pw = unesc(a[2]);
      printf("%s\n", check_text(check(ssid.data(), ssid.size(), pw.data(), pw.size())));
    } else if (a[0] == "D") {
      std::string ssid = unesc(a[2]), pw = unesc(a[3]);
      PageResult r = page_decide(a[1] == "1", ssid.data(), ssid.size(), pw.data(), pw.size());
      printf("%s\n", page_text(r, ssid.c_str(), check(ssid.data(), ssid.size(), pw.data(), pw.size())).c_str());
    } else if (a[0] == "M") {
      std::string ssid = unesc(a[1]), pw = unesc(a[2]);
      ExtraWifi w{};
      bool ok = make(w, ssid.data(), ssid.size(), pw.data(), pw.size());
      printf("%d %d [%s] [%s] %s\n", ok, has(w), w.ssid, w.password, label(w).c_str());
      w = ExtraWifi{};
      printf("cleared %d %s\n", has(w), label(w).c_str());
    }
  }
}
"""


@pytest.fixture(scope="module")
def drv(tmp_path_factory):
    cxx = shutil.which("c++") or shutil.which("g++") or shutil.which("clang++")
    if not cxx:
        pytest.skip("no C++ compiler on PATH")
    d = tmp_path_factory.mktemp("wifi")
    src = d / "drv.cpp"
    src.write_text(DRIVER)
    exe = d / "drv"
    subprocess.run([cxx, "-std=c++17", "-O1", "-Wall", "-Werror", "-I", str(WIFI_DIR), str(src), "-o", str(exe)],
                   check=True)
    return exe


def run(exe, lines):
    out = subprocess.run([str(exe)], input="".join(l + "\n" for l in lines), capture_output=True, text=True,
                         check=True).stdout
    return out.splitlines()


def test_check_ssid(drv):
    assert run(drv, ["K|Home|password1", "K||password1", "K|" + "s" * 32 + "|password1", "K|" + "s" * 33 + "|password1",
                     "K|Ho\\x01me|password1", "K|caf\\xc3\\xa9 wifi|password1"]) == [
        "ok", "network name must be 1-32 bytes", "ok", "network name must be 1-32 bytes",
        "network name has control characters", "ok"]


def test_check_password(drv):
    assert run(drv, ["K|Home|", "K|Home|1234567", "K|Home|12345678", "K|Home|" + "p" * 63, "K|Home|" + "p" * 64,
                     "K|Home|" + "0123456789abcdef" * 4, "K|Home|pass\\x01word", "K|Home|p\\xc3\\xa4sswort"]) == [
        "ok",  # open network
        "password must be empty (open network), 8-63 characters or 64 hex digits",
        "ok", "ok",
        "password must be empty (open network), 8-63 characters or 64 hex digits",
        "ok",  # raw 64-hex PSK
        "password must be printable ASCII",
        "password must be printable ASCII",
    ]


def test_make_has_label_clear(drv):
    assert run(drv, ["M|Home|password1"]) == ["1 1 [Home] [password1] Home", "cleared 0 none"]
    assert run(drv, ["M|Home|short"]) == ["0 0 [] [] none", "cleared 0 none"]
    s32 = "s" * 32
    assert run(drv, [f"M|{s32}|"]) == [f"1 1 [{s32}] [] {s32} (open)", "cleared 0 none"]


# ---- cgdn1.yaml wiring ----------------------------------------------------------------------------

def _action(name):
    start = YAML.index(f"    - action: {name}\n")
    end = YAML.find("\n    - action: ", start + 1)
    end2 = YAML.find("\n\n", start)
    return YAML[start:min(e for e in (end, end2, len(YAML)) if e != -1)]


def test_page_decisions(drv):
    assert run(drv, ["D|1|Home|password1", "D|0|Home|password1", "D|1||password1", "D|1|Home|short",
                     "D|1|Home|"]) == [
        "Saved 'Home': joining it when in reach (the hotspot closes once it's connected)",
        "Only on the fallback hotspot (http://192.168.4.1); on a network use tools/cgdn1_set_wifi.py",
        "Enter a WiFi name first",
        "Not saved: password must be empty (open network), 8-63 characters or 64 hex digits",
        "Saved 'Home': joining it when in reach (the hotspot closes once it's connected)",
    ]


def test_builtin_network_is_the_office_only():
    wifi = YAML[YAML.index("\nwifi:\n"):YAML.index("\nmdns:")]
    assert "!secret wifi_ssid\n" in wifi and "!secret wifi_password\n" in wifi
    assert "hotspot_wifi" not in YAML  # the Add WiFi page covers new places; no extra secrets needed
    assert "  ap:\n" in wifi  # fallback hotspot stays


def _entity(name):
    start = YAML.index(f'name: "{name}"\n')
    end = YAML.find("\n  - ", start)
    return YAML[start:end if end != -1 else len(YAML)]


def test_add_wifi_page():
    assert "    - id: grp_add_wifi\n      name: \"Add WiFi\"" in YAML
    name = _entity("WiFi name")
    assert "mode: text" in name and "cgdn1_wifi::set_pending_ssid(x)" in name
    pw = _entity("WiFi password")
    assert "mode: password" in pw
    assert "optimistic: false" in pw  # never published as a state, so never broadcast to clients
    assert "restore_value" not in pw
    assert "cgdn1_wifi::set_pending_password(x)" in pw
    connect = _entity("Connect to WiFi")
    assert "cgdn1_wifi::connect_from_page()" in connect
    status = _entity("Add WiFi status")
    assert "cgdn1_wifi::page_status()" in status
    for n in ("WiFi name", "WiFi password", "Connect to WiFi", "Add WiFi status"):
        assert "sorting_group_id: grp_add_wifi" in _entity(n), n


def test_set_and_forget_actions():
    s = _action("set_wifi")
    assert "ssid: string" in s and "password: string" in s
    assert "cgdn1_wifi::store(" in s
    f = _action("forget_wifi")
    assert "cgdn1_wifi::forget()" in f


def test_password_never_logged():
    for block in (_action("set_wifi"), _action("forget_wifi"), _entity("WiFi password"), _entity("Connect to WiFi")):
        for line in block.splitlines():
            if "ESP_LOG" in line:
                assert "password" not in line, line
    esphome_glue = (WIFI_DIR / "extra_wifi_esphome.h").read_text()
    for line in esphome_glue.splitlines():
        if "ESP_LOG" in line:
            assert not re.search(r"password", line), line


def test_extra_network_added_before_wifi_starts():
    boot = YAML[YAML.index("  on_boot:\n"):YAML.index("  on_shutdown:")]
    assert re.search(r"priority: 2[6-9]\d", boot)  # before WiFi (250), after globals/preferences
    assert "cgdn1_wifi::apply_saved();" in boot


def test_extra_wifi_row_in_device_info():
    start = YAML.index('name: "Extra WiFi"\n')
    block = YAML[start:YAML.find("\n  - ", start)]
    assert "sorting_group_id: grp_device_info" in block
    assert "cgdn1_wifi::saved_label()" in block


def test_component_loaded():
    # Without the top-level line the headers are not in the build ("cgdn1_wifi has not been declared").
    assert "\ncgdn1_wifi:\n" in YAML
    assert re.search(r"components: \[[^\]]*\bcgdn1_wifi\b", YAML)
