"""Host tests for the dashboard "Device info" texts and the factory-block readout
(components/cgdn1_info/info.h).

A tiny C++ driver is compiled against the header with the system C++ compiler (skipped when none
is installed) and fed '|'-separated commands over stdin.
"""
import math
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
INFO_DIR = ROOT / "components" / "cgdn1_info"

DRIVER = r"""
#include "info.h"
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
using namespace cgdn1_info;
static std::vector<std::string> split(const std::string &s) {
  std::vector<std::string> out; std::string cur;
  for (char c : s) { if (c == '|') { out.push_back(cur); cur.clear(); } else cur += c; }
  out.push_back(cur);
  return out;
}
static unsigned long u(const std::string &s, int base = 10) { return strtoul(s.c_str(), nullptr, base); }
int main() {
  std::string line;
  while (std::getline(std::cin, line)) {
    auto a = split(line);
    if (a[0] == "C") printf("%s\n", chip_text(u(a[1]), u(a[2]), u(a[3]), u(a[4])).c_str());
    else if (a[0] == "F") printf("%s\n", flash_text(u(a[1], 16)).c_str());
    else if (a[0] == "S") printf("%s\n", slots_text(a[1].c_str(), a[2].c_str(), a[3] == "1", a[4].c_str(),
                                                    a[5].c_str()).c_str());
    else if (a[0] == "W") printf("%s\n", firmware_text(a[1].c_str(), a[2].c_str(), a[3].c_str()).c_str());
    else if (a[0] == "P") printf("%g\n", signal_pct(strtof(a[1].c_str(), nullptr)));
    else if (a[0] == "Z") {
      std::vector<uint8_t> b;
      for (size_t i = 0; i + 1 < a[1].size(); i += 2) b.push_back((uint8_t) strtoul(a[1].substr(i, 2).c_str(), nullptr, 16));
      for (const auto &l : factory_summary(b.data(), b.size(), a[3].c_str(), u(a[2]))) printf("%s\n", l.c_str());
      printf("--\n");
    }
  }
}
"""


@pytest.fixture(scope="module")
def drv(tmp_path_factory):
    cxx = shutil.which("c++") or shutil.which("g++") or shutil.which("clang++")
    if not cxx:
        pytest.skip("no C++ compiler on PATH")
    d = tmp_path_factory.mktemp("info")
    src = d / "drv.cpp"
    src.write_text(DRIVER)
    exe = d / "drv"
    subprocess.run([cxx, "-std=c++17", "-O1", "-Wall", "-Werror", "-I", str(INFO_DIR), str(src), "-o", str(exe)],
                   check=True)
    return exe


def run(exe, lines):
    out = subprocess.run([str(exe)], input="".join(l + "\n" for l in lines), capture_output=True, text=True,
                         check=True).stdout
    return out.splitlines()


def test_chip_text(drv):
    assert run(drv, ["C|0|300|2|160", "C|1|101|2|240", "C|3|300|1|80", "C|7|301|2|160"]) == [
        "ESP32-D0WDQ6, rev v3.0, 2 cores, 160 MHz",
        "ESP32-D0WDQ5, rev v1.1, 2 cores, 240 MHz",
        "ESP32 (package 3), rev v3.0, 1 core, 80 MHz",
        "ESP32-D0WDR2-V3, rev v3.1, 2 cores, 160 MHz",
    ]


def test_flash_text(drv):
    assert run(drv, ["F|C84016", "F|EF4018", "F|124016", "F|C84040", "F|0", "F|FFFFFF"]) == [
        "4 MB, GigaDevice (C84016)",
        "16 MB, Winbond (EF4018)",
        "4 MB, vendor 0x12 (124016)",
        "unknown size, GigaDevice (C84040)",
        "unknown (no flash ID)",
        "unknown (no flash ID)",
    ]


def test_slots_text(drv):
    assert run(drv, ["S|ota_1|ota_0|1|Dany-ESP|4.8.5", "S|ota_1|ota_0|0|x|y", "S|ota_0|ota_1|1|Da\x01ny|"]) == [
        "running ota_1 · other ota_0: Dany-ESP 4.8.5",
        "running ota_1 · other ota_0: no valid app",
        "running ota_0 · other ota_1: Da?ny",
    ]


def test_firmware_text(drv):
    assert run(drv, ["W|2026.9.1|c7b6ceb|2026-11-02 05:48:29 +0000", "W|2026.9.1||2026-11-02 05:48:29 +0000"]) == [
        "ESPHome 2026.9.1 · c7b6ceb · built 2026-11-02 05:48:29 +0000",
        "ESPHome 2026.9.1 · built 2026-11-02 05:48:29 +0000",
    ]


def test_signal_pct(drv):
    got = run(drv, ["P|-50", "P|-100", "P|-70", "P|-30", "P|-120", "P|nan"])
    assert got[:5] == ["100", "0", "60", "100", "0"]
    assert math.isnan(float(got[5]))


def block(size=256, fill=0xFF):
    return bytearray([fill] * size)


def put(b, off, data):
    b[off:off + len(data)] = data


MAC = "CCB5D131D278"


def summary(drv, b, max_lines=48, mac=MAC):
    out = run(drv, [f"Z|{bytes(b).hex()}|{max_lines}|{mac}"])
    assert out[-1] == "--"
    return out[:-1]


def test_factory_summary_shows_only_versions_and_short_ids(drv):
    b = block()
    put(b, 0x00, b"Z\x00")
    put(b, 0x10, b"CGDN1\x00")                          # model-like text: classes only
    put(b, 0x20, b"0001\x00")                           # version-like: shown
    put(b, 0x28, b"1.0.2\x00")                          # version-like: shown
    put(b, 0x30, b"0123456789abcdef0123456789abcdef")   # key: classes only
    put(b, 0x5D, b"\x01")                               # panel id byte: shown
    put(b, 0x60, b"123-45-678\x00")                     # HomeKit-style setup code: never shown
    put(b, 0x70, b"12345678\x00")                       # 8 digits: never shown
    put(b, 0x80, bytes(range(1, 13)))                   # 12 binary bytes: length only
    put(b, 0x90, b"\x02\x9a")                           # 2 binary bytes: shown
    put(b, 0x98, b"\x4e\x61\xbc\x00")                   # 3 binary bytes (could be a packed code): length only
    out = summary(drv, b)
    assert out == [
        "factory block: 'Z' marker present",
        "+0x000: 5a",
        "+0x010: <5 chars: upper, digits>",
        '+0x020: "0001"',
        '+0x028: "1.0.2"',
        "+0x030: <32 chars: lower, digits>",
        "+0x05d: 01",
        "+0x060: <10 chars: digits, '-'>",
        "+0x070: <8 chars: digits>",
        "+0x080: <12 bytes binary>",
        "+0x090: 02 9a",
        "+0x098: <3 bytes binary>",
    ]
    text = "\n".join(out)
    for secret in ("123-45-678", "12345678", "0123456789abcdef", "CGDN1"):
        assert secret not in text


def test_factory_summary_marks_own_mac(drv):
    b = block()
    put(b, 0x00, b"Z\x00")
    put(b, 0x08, b"ccb5d131d278\x00")       # own MAC (any case)
    put(b, 0x18, b"AABBCCDDEEFF\x00")       # another MAC-shaped value: classes only
    put(b, 0x28, b"Q p-1_x.\x00")           # punctuation and spaces are listed by class
    assert summary(drv, b) == [
        "factory block: 'Z' marker present",
        "+0x000: 5a",
        "+0x008: <device MAC>",
        "+0x018: <12 chars: upper>",
        "+0x028: <8 chars: upper, lower, digits, ' ', '-', '.', '_'>",
    ]


def test_factory_summary_blank_and_unmarked(drv):
    assert summary(drv, block()) == ["factory block: no 'Z' marker (first byte 0xff)", "(all blank)"]
    assert summary(drv, block(fill=0x00)) == ["factory block: no 'Z' marker (first byte 0x00)", "(all blank)"]


def test_factory_summary_caps_lines(drv):
    b = block()
    for i in range(10):
        put(b, 0x10 * i + 4, b"%d00\x00" % i)
    assert summary(drv, b, max_lines=3) == [
        "factory block: no 'Z' marker (first byte 0xff)",
        '+0x004: "000"',
        '+0x014: "100"',
        '+0x024: "200"',
        "... 7 more entries",
    ]


# ---- cgdn1.yaml wiring ----------------------------------------------------------------------------

YAML = (ROOT / "cgdn1.yaml").read_text()
INFO_ROWS = ["Device name", "IP address", "MAC address", "WiFi network", "WiFi signal", "WiFi signal %", "Uptime",
             "Firmware", "Firmware slots", "Chip", "Flash chip", "Display panel", "Free memory",
             "Lowest free memory", "Last reset", "Log factory info"]


def _entity_block(name):
    start = YAML.index(f'name: "{name}"\n')
    end = YAML.find("\n  - ", start)
    return YAML[start:end if end != -1 else len(YAML)]


def test_device_info_group_holds_every_row():
    assert "    - id: grp_device_info\n      name: \"Device info\"" in YAML
    for name in INFO_ROWS:
        assert "sorting_group_id: grp_device_info" in _entity_block(name), name


def test_firmware_rev_is_a_substitution():
    assert 'fw_rev: "dev"' in YAML
    assert '"${fw_rev}"' in YAML


def test_factory_block_is_only_logged():
    button = _entity_block("Log factory info")
    assert "cgdn1_info::log_factory_block();" in button
    # never published as an entity state
    assert YAML.count("factory_summary") == 0
