"""Host tests for components/cgdn1_display/usage_page.h (Claude / Codex usage pages): validation,
age across the millis() wrap, fresh/stale/no-data look, corner text, percentages, bars, ink box."""
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
DISPLAY_DIR = ROOT / "components" / "cgdn1_display"

DRIVER = r"""
#include "usage_page.h"
#include <cstdio>
#include <iostream>
#include <sstream>
#include <string>
using namespace esphome::cgdn1_display;

static std::string unhex(const std::string &h) {
  std::string s;
  for (size_t i = 0; i + 1 < h.size(); i += 2) s += (char) std::stoi(h.substr(i, 2), nullptr, 16);
  return s;
}
static void dump(const UsageState &s) {
  std::printf("%d %.2f %.2f %s %u %u\n", s.has, s.five_hour, s.seven_day, s.account, s.age_s, s.rx_ms);
}

int main() {
  UsageState st{};
  std::string line;
  while (std::getline(std::cin, line)) {
    std::istringstream in(line);
    std::string cmd; in >> cmd;
    if (cmd == "set") {  // set account_hex five seven age_s now_ms -> ret, then state
      std::string acc, f5, f7; long age; unsigned long now;
      in >> acc >> f5 >> f7 >> age >> now;
      std::string a = acc == "-" ? "" : unhex(acc);
      int ok = usage_set(st, a.data(), a.size(), std::stof(f5), std::stof(f7), (int32_t) age, (uint32_t) now);
      std::printf("%d ", ok);
      dump(st);
    } else if (cmd == "age") {  // age rx_ms age_s now_ms
      unsigned long rx, age, now; in >> rx >> age >> now;
      UsageState s{}; s.has = true; s.rx_ms = (uint32_t) rx; s.age_s = (uint32_t) age;
      std::printf("%u\n", usage_age_s(s, (uint32_t) now));
    } else if (cmd == "look") {  // look has age_s
      int has; unsigned long age; in >> has >> age;
      UsageState s{}; s.has = has; s.age_s = (uint32_t) age;
      std::printf("%d\n", (int) usage_look(s, 0));
    } else if (cmd == "corner") {  // corner has age_s account with_account
      int has, with; unsigned long age; std::string acc; in >> has >> age >> acc >> with;
      UsageState s{}; s.has = has; s.age_s = (uint32_t) age;
      if (acc != "-") std::snprintf(s.account, sizeof(s.account), "%s", acc.c_str());
      char out[64]; usage_corner_text(s, 0, with, out, sizeof(out));
      std::printf("%s\n", out);
    } else if (cmd == "pct") {
      std::string v; in >> v; std::printf("%d\n", usage_pct(std::stof(v)));
    } else if (cmd == "bar") {
      std::string v; int w; in >> v >> w; std::printf("%d\n", usage_bar_fill(std::stof(v), w));
    } else if (cmd == "ink") {
      Rect r = usage_ink(); std::printf("%d %d %d %d\n", r.x0, r.y0, r.x1, r.y1);
    }
  }
}
"""


@pytest.fixture(scope="module")
def drv(tmp_path_factory):
    cxx = shutil.which("c++") or shutil.which("g++") or shutil.which("clang++")
    if not cxx:
        pytest.skip("no C++ compiler on PATH")
    d = tmp_path_factory.mktemp("upage")
    src = d / "drv.cpp"
    src.write_text(DRIVER)
    exe = d / "drv"
    subprocess.run([cxx, "-std=c++17", "-O1", "-Wall", "-Werror", "-I", str(DISPLAY_DIR), str(src), "-o", str(exe)],
                   check=True)
    return exe


def run(exe, lines):
    out = subprocess.run([str(exe)], input="".join(l + "\n" for l in lines), capture_output=True, text=True,
                         check=True).stdout
    return out.splitlines()


def hexs(s):
    return s.encode("latin-1").hex() if s else "-"


def test_set_rejects_bad_values(drv):
    good = f"set {hexs('claude')} 32 18 60 1000"
    for bad in ("nan 18 60", "32 nan 60", "-0.1 18 60", "32 100.1 60", "inf 18 60", "32 18 -1"):
        out = run(drv, [good, f"set {hexs('x')} {bad} 2000"])
        assert out[0].startswith("1 1 32.00 18.00 claude 60 1000")
        assert out[1] == "0 1 32.00 18.00 claude 60 1000", bad  # rejected, state unchanged


def test_set_accepts_and_sanitises(drv):
    out = run(drv, [f"set {hexs(chr(1).join(['daybreak', 'longname!']))} 41.6 9.2 540 5000"])
    assert out[0] == "1 1 41.60 9.20 daybreak?lon 540 5000"
    assert run(drv, ["set - 0 100 0 7"])[0] == "1 1 0.00 100.00  0 7"  # bounds accepted, empty account


def test_age_across_millis_wrap(drv):
    assert run(drv, ["age 4294963200 100 4096"]) == ["108"]  # rx 0xFFFFF000, now 0x00001000: 8 s later
    assert run(drv, ["age 1000 0 61999"]) == ["60"]


def test_look(drv):
    NONE, FRESH, STALE = "0", "1", "2"
    assert run(drv, ["look 0 0", "look 1 0", "look 1 3600", "look 1 3601"]) == [NONE, FRESH, FRESH, STALE]


def test_corner_text(drv):
    assert run(drv, [
        "corner 0 0 - 0", "corner 1 59 - 0", "corner 1 120 - 0", "corner 1 10800 - 0", "corner 1 172800 - 0",
        "corner 1 540 daybreak 1", "corner 1 30 daybreak 1", "corner 1 540 - 1", "corner 0 0 daybreak 1",
    ]) == ["—", "now", "2m ago", "3h ago", "2d ago",
           "daybreak · 9m", "daybreak · now", "9m", "—"]


def test_pct_and_bar(drv):
    assert run(drv, ["pct 41.6", "pct 41.4", "pct -3", "pct 250"]) == ["42", "41", "0", "100"]
    assert run(drv, ["bar 32 144", "bar -5 144", "bar 250 144", "bar 100 142"]) == ["46", "0", "144", "142"]


def test_ink_inside_safe_area(drv):
    x0, y0, x1, y1 = (int(v) for v in run(drv, ["ink"])[0].split())
    assert 3 <= x0 < x1 <= 157
    assert 17 <= y0 < y1 <= 125  # below the page dots (BOUNCE_TOP_MARGIN), inside the bottom margin


def _page_lambda():
    yaml = (ROOT / "cgdn1.yaml").read_text()
    start = yaml.index("const Entry pg[] = {")
    return yaml[start:yaml.index("draw_page_dots(shown, COUNT, plot)", start)]


def test_draw_loop_checks_info_before_reading_pg():
    # pg[] holds the pages before info; the loop also visits k == INFO, so the first pg[k] read in it
    # must sit behind a k != INFO test (the info page used to read pg[INFO], past the array).
    loop = _page_lambda().split("for (int k = 0; k < COUNT; k++) {", 1)[1]
    first = next(line for line in loop.splitlines() if "pg[k]" in line)
    assert "k != INFO" in first and first.index("k != INFO") < first.index("pg[k]"), first.strip()


def test_page_list_size_is_asserted():
    assert "static_assert(sizeof(pg) / sizeof(pg[0]) == INFO" in _page_lambda()


def test_usage_pages_light_the_led():
    lam = _page_lambda()
    assert '{PageKind::PM25, NAN, cgdn1_led::SENSOR_CLAUDE, &id(usage_claude), "Claude", false}' in lam
    assert '{PageKind::PM25, NAN, cgdn1_led::SENSOR_CODEX, &id(usage_codex), "Codex", true}' in lam
    yaml = (ROOT / "cgdn1.yaml").read_text()
    assert "id(led_shown) = shown == INFO ? cgdn1_led::SENSOR_NONE : pg[shown].led;" in yaml
