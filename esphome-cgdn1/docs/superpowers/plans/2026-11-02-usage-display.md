# Claude / Codex Usage Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Claude and Codex 5-hour / weekly usage percentages as two black-and-white pages on the CGDN1 screen, fed by an agent on the Mac that sends numbers only.

**Architecture:** Firmware (this repo): a pure header `usage_page.h` holds state, validation, age and layout math (host-tested); the display lambda draws two text pages from two `UsageState` globals; an ESPHome API action `set_usage` fills them. Mac side (new repo `~/qingping-flash/usage-display`): Claude's status line and the Codex Stop hook each write a small JSON snapshot; a launchd agent reads both and calls `set_usage` over the encrypted native API when `cgdn1.local` is reachable.

**Tech Stack:** ESPHome 2026.9.1 (ESP-IDF), C++17 header-only component code, Python 3 + `aioesphomeapi` (in `~/qingping-flash/venv`), pytest, launchd.

**Spec:** `docs/superpowers/specs/2026-11-02-usage-display-design.md`

## Global Constraints

- No credential, token, auth file, prompt or transcript content is sent anywhere; only numbers + a ≤ 12-char ASCII account label.
- The existing Claude status-line output and the Codex RunCat file (`~/.codex/runcat-usage.json`) must be unchanged; new code there must never fail, print, or block.
- Display is 1 bit per pixel (black/white). Look per `~/qingping-flash/usage-display/.superpowers/brainstorm/*/content/layout-bw.html`.
- Page order: PM2.5 → PM10 → CO₂ → Claude → Codex → temperature → humidity → info. PM1.0 page removed; `pm1` sensor, `PageKind::PM1`, `SENSOR_PM1` stay.
- Stale after **3600 s** without an update (hollow digits + empty bars); before the first update: "—" + empty bars.
- Percentages accepted only in **0–100** (finite); out-of-range is rejected on the device, clamped in the agent.
- Heartbeat send every **300 s**; poll the snapshot files every **30 s**.
- Keep: digest web auth, no web OTA, no captive portal, lwIP ACD, the BLE broadcast. Deploy only via "Boot other firmware slot" → `~/qingping-flash/resume-flash.sh`; never ESPHome OTA.
- Status LED shows nothing (`cgdn1_led::SENSOR_NONE`) on usage pages.

## Review Focus

1. Monitor unreachable (Mac off OfficeGuest, monitor rebooting, IP conflict) → agent logs one line, retries next cycle, never exits. *Test: Task 4 `test_run_once_survives_send_failure`.*
2. Snapshot missing/half-written/malformed (no Claude session yet, Codex hook never ran) → that service is skipped, the other is still sent. *Tests: Task 4 `test_build_payloads_skips_missing`, `test_load_json_bad_file`.*
3. Out-of-range, NaN or non-numeric percentages → agent clamps/drops; device rejects and keeps the previous values. *Tests: Task 1 `test_set_rejects_bad_values`, Task 4 `test_build_payloads_clamps`.*
4. `millis()` wrap and device reboot → age stays right across the 49-day wrap; after reboot pages show "—". *Test: Task 1 `test_age_across_millis_wrap`.*
5. Codex `rate_limits` with windows in the other order or one missing → match by `window_minutes` (300 / 10080); if either is missing, write no snapshot. *Test: Task 3 `test_codex_snapshot_by_window`.*

## File Structure

Firmware repo (`~/qingping-flash/esphome-cgdn1/.claude/worktrees/permanent`, branch `local-dashboard`):
- Create `components/cgdn1_display/usage_page.h` — pure state/validation/age/text/layout helpers (no ESPHome includes).
- Modify `components/cgdn1_display/cgdn1_display.h:46-47` — `#include "usage_page.h"`.
- Create `tests/test_usage_page.py` — g++ host tests in the style of `tests/test_stock_page.py`.
- Modify `cgdn1.yaml` — fonts (958-997), globals (601-656), `api:` (131), display lambda page block (1031-1234), comments (624-627, 1031-1044).
- Modify `README.md:25`, `components/cgdn1_display/stock_page.h:3` — drop "PM1.0 page" wording.

Mac repo (`~/qingping-flash/usage-display`, new; `.superpowers/` gitignored):
- `usage_display/snapshots.py` — build + atomically write the Claude/Codex snapshots.
- `claude_statusline_hook.py` — stdin → Claude snapshot (called from the status line).
- `usage_display/agent.py` — payloads, change/heartbeat decision, API send, main loop.
- `local.qingping.usage-agent.plist` — launchd agent (installed to `~/Library/LaunchAgents/`).
- `tests/test_snapshots.py`, `tests/test_agent.py`.
- Outside any repo (edited in place, backed up first): `~/.codex/runcat-hook.py`, `~/.claude/settings.json` (`statusLine.command`).

---

### Task 1: `usage_page.h` — usage state, validation, age, text, layout

**Files:**
- Create: `components/cgdn1_display/usage_page.h`
- Modify: `components/cgdn1_display/cgdn1_display.h:46-47` (add the include)
- Test: `tests/test_usage_page.py`

**Interfaces:**
- Produces (namespace `esphome::cgdn1_display`):
  - `static constexpr uint32_t USAGE_STALE_S = 3600;` `static constexpr size_t USAGE_ACCOUNT_MAX = 12;`
  - `enum class UsageLook : uint8_t { NONE, FRESH, STALE };`
  - `struct UsageState { bool has; float five_hour; float seven_day; char account[USAGE_ACCOUNT_MAX + 1]; uint32_t age_s; uint32_t rx_ms; };` (value-initialised = no data)
  - `bool usage_set(UsageState &s, const char *account, size_t account_len, float five_hour, float seven_day, int32_t age_s, uint32_t now_ms);` — returns false and leaves `s` untouched if either percentage is non-finite / < 0 / > 100 or `age_s < 0`; copies at most 12 account bytes, replacing bytes outside 0x20–0x7E with `?`.
  - `uint32_t usage_age_s(const UsageState &s, uint32_t now_ms);` — `s.age_s + (uint32_t)(now_ms - s.rx_ms) / 1000` (unsigned subtraction handles the wrap).
  - `UsageLook usage_look(const UsageState &s, uint32_t now_ms);` — `!has` → NONE; age > 3600 → STALE; else FRESH.
  - `void usage_corner_text(const UsageState &s, uint32_t now_ms, bool with_account, char *out, size_t n);` — NONE → `"—"`; age < 60 → `"now"`, < 3600 → `"<m>m"`, < 86400 → `"<h>h"`, else `"<d>d"`; without account append `" ago"` (except "now"); with account: `"<account> · <age>"` (account empty → just the age form).
  - `int usage_pct(float pct);` — clamp 0..100, `lroundf`.
  - `int usage_bar_fill(float pct, int inner_w);` — clamp 0..100, `lroundf(pct * inner_w / 100)`.
  - Layout constants (logical 160×128, relative to the page origin; tune visually, keep the bounds test green): `USAGE_TITLE_Y = 18`, `USAGE_ROW_Y[2] = {34, 76}` (top of the big digits), `USAGE_LABEL_X = 8`, `USAGE_DIGITS_X = 40`, `USAGE_BAR_X = 8`, `USAGE_BAR_W = 144`, `USAGE_BAR_H = 5`, `USAGE_BAR_DY = 31` (bar top below the row's digit top).
  - `Rect usage_ink();` — union box of everything drawn on a usage page (for `bounce_range`).

- [ ] **Step 1: Write the failing tests** in `tests/test_usage_page.py`, reusing the compile/run idiom of `tests/test_stock_page.py` (`drv` fixture compiling a stdin-command driver with `-std=c++17 -Wall -Werror -I components/cgdn1_display`):

```python
def test_set_rejects_bad_values(drv):      # nan, -0.1, 100.1, age -1 -> returns 0, state unchanged
def test_set_accepts_and_sanitises(drv):   # ("daybreak\x01longname!", 41.6, 9.2, 540) -> has, "daybreak?lon", age 540
def test_age_across_millis_wrap(drv):      # rx_ms=0xFFFFF000, now=0x00001000 -> age_s + 8
def test_look(drv):                        # no data NONE; age 3600 FRESH; 3601 STALE
def test_corner_text(drv):                 # "—"; "now"; "2m ago"; "3h ago"; "daybreak · 9m"; account "" -> "9m"
def test_pct_and_bar(drv):                 # usage_pct(41.6)==42; bar(32,144)==46; bar(-5,144)==0; bar(250,144)==144
def test_ink_inside_safe_area(drv):        # usage_ink(): x0>=3, y0>=17 (below page dots), x1<=157, y1<=125
```

- [ ] **Step 2: Run to verify they fail**
Run: `docker run --rm -v "$PWD":/config --entrypoint bash ghcr.io/esphome/esphome:2026.9.1 -c "pip install -q pytest paho-mqtt; cd /config && python -m pytest tests/test_usage_page.py -q"`
Expected: FAIL — `usage_page.h` not found.

- [ ] **Step 3: Implement `usage_page.h`** with the interfaces above (header-only, `inline`, `snprintf` for text; `·` is U+00B7 and `—` is U+2014 as UTF-8 literals). Add `#include "usage_page.h"` next to `stock_page.h` in `cgdn1_display.h`.

- [ ] **Step 4: Run to verify they pass** (same command). Expected: all pass. Also run `tests/test_stock_page.py tests/test_display_math.py` — still pass.

- [ ] **Step 5: Commit** — `git add components/cgdn1_display/usage_page.h components/cgdn1_display/cgdn1_display.h tests/test_usage_page.py && git commit -m "usage_page.h: usage state, validation, age and layout helpers"`

### Task 2: Firmware — pages, fonts, `set_usage` action

**Files:**
- Modify: `cgdn1.yaml` (fonts 958-997, globals 601-656, `api:` 131, lambda 1031-1234, comments 624-627)
- Modify: `README.md:25`, `components/cgdn1_display/stock_page.h:3`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces: API action `set_usage(service: string, five_hour: float, seven_day: float, account: string, age_s: int)` — `service` `"claude"` → `id(usage_claude)`, `"codex"` → `id(usage_codex)`, anything else ignored; calls `usage_set(..., millis())`. (Task 5 calls it by this exact name and these variable names.)

- [ ] **Step 1: Fonts.** Append `·—` to the `&all_glyphs` list. Add font `f_usage_big`: `gfonts://Roboto Condensed@900`, size **30**, glyphs `'0123456789%—'`.
- [ ] **Step 2: Globals.** Add `usage_claude` and `usage_codex`, `type: cgdn1_display::UsageState` (no initial value, no restore).
- [ ] **Step 3: API action** under `api:` with the variables above; `string` variables arrive as `StringRef` — copy/compare via `.str()`, pass `account.c_str()`/`account.size()`.
- [ ] **Step 4: Page list.** In the lambda: `Entry` gains `const UsageState *usage; const char *title; bool with_account;`. Entries: PM25, PM10, CO2, `{usage_claude,"Claude",false}`, `{usage_codex,"Codex",true}`, TEMP, HUMI. `INFO = 7, COUNT = 8, FIRST = 0`. `led_shown` = `SENSOR_NONE` for info **and** usage entries. Bounce range: usage target → `bounce_range(usage_ink(), W, H)`, else the existing `page_ink(make_page(...))`.
- [ ] **Step 5: Draw a usage page** at `(pos.x + px, pos.y)` (drift + slide like stock pages): title `f_info` TOP_LEFT at `USAGE_TITLE_Y`; `usage_corner_text` `f_info` TOP_RIGHT at x 152; per row (`5h`, `7d`): label `f_info`, percentage `"%d%%"` (`usage_pct`) in `f_usage_big`, bar = 1-px outline `USAGE_BAR_W`×`USAGE_BAR_H` plus a filled part of `usage_bar_fill(pct, USAGE_BAR_W - 2)` only when FRESH. STALE: digits outlined — print with `COLOR_ON` at the 8 one-pixel neighbour offsets, then with `COLOR_OFF` at the centre. NONE: `"—"` in place of each percentage, empty bars.
- [ ] **Step 6: Comments/docs.** Update the lambda header comment (1031-1044: order, 8-dot indicator, info slides on to PM2.5), globals comment (624-627), `README.md:25`, `stock_page.h:3`.
- [ ] **Step 7: Build + tests.** Run `docker run --rm -v "$PWD":/config ghcr.io/esphome/esphome:2026.9.1 compile cgdn1.yaml` → "Successfully compiled"; full host tests (`python -m pytest -q` in the container, as Task 1) → all pass, `test_esphome_image.py` with no skips; `grep -E "USE_WEBSERVER_OTA|USE_CAPTIVE_PORTAL" .esphome/build/cgdn1/src/esphome/core/defines.h` → no output; `USE_ESP32_BLE_ADVERTISING`, `USE_WEBSERVER_AUTH_DIGEST` present; `grep CONFIG_LWIP_DHCP_DOES_ACD_CHECK=y .esphome/build/cgdn1/sdkconfig.cgdn1` → match.
- [ ] **Step 8: Commit** — `git commit -am "Usage pages (Claude, Codex) after CO2, set_usage API action; drop PM1.0 page"`

### Task 3: Mac repo + snapshot writers

**Files:**
- Create: `~/qingping-flash/usage-display/` git repo (`.gitignore`: `.superpowers/`, `agent.log`, `__pycache__/`), `usage_display/__init__.py`, `usage_display/snapshots.py`, `claude_statusline_hook.py`, `tests/test_snapshots.py`
- Modify (backup to `*.bak` first): `~/.codex/runcat-hook.py` (`write_snapshot`, line 82), `~/.claude/settings.json` (`statusLine.command`)

**Interfaces:**
- Produces:
  - `CLAUDE_SNAPSHOT = Path.home() / ".claude/usage-snapshot.json"`, `CODEX_SNAPSHOT = Path.home() / ".codex/usage-display.json"`
  - `claude_snapshot(statusline: dict, now: float) -> dict | None` — from `rate_limits.five_hour.used_percentage` / `rate_limits.seven_day.used_percentage`; both numeric else None.
  - `codex_snapshot(token_count: dict, codex_home: str | None, now: float) -> dict | None` — picks `rate_limits.primary/secondary` by `window_minutes` 300 → five_hour, 10080 → seven_day; account: basename `.codex` or unset → `"default"`, `.codex-<name>` → `<name>`.
  - Snapshot shape (both): `{"five_hour": float, "seven_day": float, "account": str, "updated_at": float}` (Claude account `""`).
  - `write_json_atomic(path: Path, obj: dict) -> None` — temp file in the same dir + `os.replace`.

- [ ] **Step 1: Install pytest** — `~/qingping-flash/venv/bin/pip install -q pytest`.
- [ ] **Step 2: Write failing tests** in `tests/test_snapshots.py`:

```python
def test_claude_snapshot():                 # sample statusline JSON (32.4 / 18.0) -> five_hour 32.4, seven_day 18.0, account ""
def test_claude_snapshot_without_limits():  # no "rate_limits" -> None
def test_codex_snapshot_by_window():        # windows swapped (primary=10080, secondary=300) -> mapped correctly; one missing -> None
def test_codex_account():                   # None/"~/.codex" -> "default"; "~/.codex-daybreak" -> "daybreak"
def test_write_json_atomic(tmp_path):       # file content round-trips; no temp files left
def test_statusline_hook_writes_and_is_silent(tmp_path):  # run claude_statusline_hook.py with HOME=tmp_path and sample stdin -> exit 0, empty stdout, snapshot written; garbage stdin -> exit 0, nothing written
```

- [ ] **Step 3: Run** `cd ~/qingping-flash/usage-display && ../venv/bin/python -m pytest -q` → FAIL (module missing).
- [ ] **Step 4: Implement** `snapshots.py` and `claude_statusline_hook.py` (reads stdin, `claude_snapshot`, `write_json_atomic(CLAUDE_SNAPSHOT)`, swallow every exception, exit 0, no output).
- [ ] **Step 5: Run tests** → pass.
- [ ] **Step 6: Wire the hooks.** In `runcat-hook.py` `write_snapshot`, after the token count is read: `try:` insert `~/qingping-flash/usage-display` into `sys.path`, `codex_snapshot(token_count, os.environ.get("CODEX_HOME"), time.time())`, write to `CODEX_SNAPSHOT` if not None; `except Exception: pass`. In `statusLine.command`, right after `input=$(cat);` add `(printf '%s' "$input" | /usr/bin/python3 ~/qingping-flash/usage-display/claude_statusline_hook.py >/dev/null 2>&1 &);`.
- [ ] **Step 7: Verify the hooks.** `T=$(ls -t ~/.codex-daybreak/sessions/*/*/*/*.jsonl | head -1); printf '{"transcript_path":"%s"}' "$T" | CODEX_HOME=~/.codex-daybreak ~/.codex/runcat-hook.py` → `~/.codex/usage-display.json` has `"account": "daybreak"`, and `~/.codex/runcat-usage.json` keeps its exact key set. Pipe a sample status-line JSON through the full `statusLine.command` → same printed line as before, and `~/.claude/usage-snapshot.json` appears within 1 s.
- [ ] **Step 8: Commit** (Mac repo) — `git add -A && git commit -m "Claude/Codex usage snapshot writers"`

### Task 4: Agent — payloads, decision, send loop

**Files:**
- Create: `usage_display/agent.py`, `tests/test_agent.py`

**Interfaces:**
- Consumes: `CLAUDE_SNAPSHOT`, `CODEX_SNAPSHOT`, snapshot shape (Task 3); API action `set_usage` (Task 2).
- Produces:
  - `load_json(path: Path) -> dict | None` (None on missing/invalid)
  - `build_payloads(claude: dict | None, codex: dict | None, now: float) -> list[dict]` — each `{"service", "five_hour", "seven_day", "account", "age_s"}`; percentages clamped 0..100 (non-numeric → service dropped); account ASCII-only, ≤ 12; `age_s = max(0, int(now - updated_at))`.
  - `due(payloads: list[dict], last: dict[str, tuple], last_sent_at: float, now: float, heartbeat_s: float = 300) -> bool` — True when any `(five_hour, seven_day, account)` differs from `last[service]` or `now - last_sent_at >= heartbeat_s`.
  - `async send(payloads, host="cgdn1.local", port=6053, psk=...) -> bool` — `APIClient(host, port, None, noise_psk=psk)`, `connect(login=True)`, find the user service named `set_usage` in `list_entities_services()`, `execute_service(svc, payload)` per payload, disconnect; any exception → False.
  - `async run_once(state: dict, sender=send, now=time.time) -> None` and `main()` (30 s poll loop; key from `api_key:` in `~/qingping-flash/esphome-secrets.yaml`, read once, never logged).

- [ ] **Step 1: Failing tests** in `tests/test_agent.py`:

```python
def test_build_payloads_skips_missing():        # (None, codex) -> only codex; (claude, None) -> only claude
def test_build_payloads_clamps():               # 120 -> 100, -3 -> 0, "x" -> service dropped; account "daybéreak_long" -> ASCII, 12 chars
def test_age_from_updated_at():                 # updated_at now-540 -> age_s 540; future updated_at -> 0
def test_due_on_change_and_heartbeat():         # same values, 10 s later -> False; changed -> True; 300 s later -> True
def test_load_json_bad_file(tmp_path):          # missing -> None; "{half" -> None
def test_run_once_survives_send_failure():  # asyncio.run(run_once(...)) with a sender returning False / raising -> no exception, state unchanged, next call retries
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** `agent.py`. **Step 4: Run** → pass.
- [ ] **Step 5: Commit** — `git add usage_display/agent.py tests/test_agent.py && git commit -m "Usage agent: payloads, change/heartbeat, API send"`

### Task 5: launchd agent, flash, end-to-end check

**Files:**
- Create: `local.qingping.usage-agent.plist` (repo) → copied to `~/Library/LaunchAgents/`

- [ ] **Step 1: plist** — Label `local.qingping.usage-agent`; ProgramArguments `[~/qingping-flash/venv/bin/python, -m, usage_display.agent]`; WorkingDirectory the repo; RunAtLoad, KeepAlive true; stdout/stderr `agent.log`. Commit.
- [ ] **Step 2: Flash** — confirm `.200`-style conflicts aren't active (`arp -n` for `cgdn1.local`'s IP shows `cc:b5:d1:31:d2:78`), press "Boot other firmware slot" via `~/qingping-flash/press_button.py`, run `~/qingping-flash/resume-flash.sh`; expect "monitor acknowledged all … bytes". Stop the image server afterwards.
- [ ] **Step 3: Device checks** — ESPHome API up, dashboard 401 without login, BLE scan shows the three packet types, page order on screen (owner): PM2.5, PM10, CO₂, Claude, Codex, T, RH, info; no PM1.0 page.
- [ ] **Step 4: Load the agent** — `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.qingping.usage-agent.plist`; within 60 s `agent.log` shows a successful send (if macOS blocks local-network access for the venv python, grant it in System Settings → Privacy & Security → Local Network and restart the agent).
- [ ] **Step 5: States on the real screen** (owner looks): live numbers match `5h:`/`7d:` in the Claude status line and the RunCat Codex values; a manual `set_usage` with `age_s: 7200` shows hollow digits + empty bars; after "Restart" both pages show "—" until the agent's next send (≤ 300 s).
- [ ] **Step 6: Docs** — add the agent, hooks and new firmware behaviour to `~/qingping-flash/HOWTO-flash-cgdn1.md`, update the memory note, repack `~/qingping-flash-portable.tgz`; commit the plan's checkboxes.
