# Design: Claude / Codex usage pages on the CGDN1 screen

Date: 2026-11-02 · Device: office Qingping Air Monitor Lite (CGDN1), ESPHome build on branch
`local-dashboard` (this repo), reachable as `cgdn1.local` on the office guest WiFi (OfficeGuest).

## Intent and why

The owner wants to glance at the air monitor on their desk and see how much of their **Claude** and
**Codex** usage limits they've used: the **5-hour** and **weekly** windows, as percentages.

Two constraints shape everything:

1. **No credentials ever leave the owner's Mac.** No API keys, OAuth tokens or session files go to the
   monitor (it sits on a shared guest network and serves plain HTTP). Sending plain usage numbers is fine.
2. **The Mac isn't always on the guest WiFi.** At the desk it usually is — WiFi on OfficeGuest plus a
   wired company connection — but not always. The display must cope with not hearing from the Mac.

## Goals

- Two new screen pages in the style of mockup **B** (chosen by the owner): one service per page, large
  digits, full-width bars.
  - **Claude page:** title "Claude", age of the data ("2m ago") top right; row "5h" with big percentage
    and a bar; row "7d" with big percentage and a bar.
  - **Codex page:** same, title "Codex", top right shows the account the numbers belong to and the age
    ("daybreak · 9m").
  - Screen: 160 × 128 landscape. **Black and white only** (owner's decision): the display driver stores
    1 bit per pixel and lights every pixel at full brightness, so there are no grays; grayscale would mean
    rewriting the shared driver and was declined. Mockups (3× scale) in
    `~/qingping-flash/usage-display/.superpowers/brainstorm/*/content/`: `layout.html` option B (layout),
    `layout-bw.html` (**the approved look**: fresh / stale / no-data states).
- **Page order** (touch swipe/tap; there is no automatic carousel):
  PM2.5 → PM10 → CO₂ → **Claude** → **Codex** → temperature → humidity → info.
  ("After CO₂/PM" as the owner put it; the existing order already has PM before CO₂.)
- **Remove the PM1.0 page** (ESPHome-only; stock has none). The owner saw it as a "second PM10 page"
  because the decimal point is barely visible. The PM1.0 *sensor* stays (dashboard/API). Page count
  stays 8 + info → the existing 7 minus PM1.0 plus 2.
- **Codex: show the most recently used account's numbers.** The owner has two Codex logins:
  default `~/.codex` and `~/.codex-daybreak` (fish wrapper `codex-daybreak` sets `CODEX_HOME`).
- **Staleness is visible:** the age keeps counting on the device; after **60 minutes** without an update
  the percentages are drawn as **outlined (hollow) digits and the bars as empty boxes**. Before the first
  update after a boot the pages show "—" with empty bars.

## Non-goals

- Reset times, history/graphs, cost or token counts.
- More than one Claude account.
- Home Assistant, cloud relays, or any delivery path that works while the Mac is off the guest WiFi
  (nobody is looking at the screen then; stale-but-labelled is acceptable).
- Changing the RunCat setup or the visible Claude status line.

## Anti-goals (failure even if it "works")

- Any credential, token, auth file, prompt or transcript content reaching the device or the network.
- Breaking or slowing the owner's existing Claude status line or the Codex RunCat hook.
- An unauthenticated way to put text on the screen (anyone on the guest WiFi could spoof the numbers).
- Losing the stock firmware slot (see "Deploy").

## Data sources (decided; verified on the owner's Mac 2026-11-02)

- **Claude:** Claude Code passes `rate_limits.five_hour.used_percentage` and
  `rate_limits.seven_day.used_percentage` in the JSON it pipes to the status-line command on every
  refresh (the owner's current status line already prints them as `5h:`/`7d:`). Add to the status-line
  command a side effect that writes `{five_hour, seven_day, updated_at}` to a snapshot file, e.g.
  `~/.claude/usage-snapshot.json` (atomic write; must never fail or slow the status line; values only
  updated while a Claude Code session is open — accepted).
- **Codex:** both Codex homes run the same Stop hook `~/.codex/runcat-hook.py`, which writes
  `~/.codex/runcat-usage.json` (RunCat Neo format: metrics "5h", "7d" with `normalizedValue`, plus
  `lastUpdatedDate`). Both homes write the same file, so it already holds the last-used account. Add one
  field naming the account (derived from `CODEX_HOME`: `~/.codex` → "default", `~/.codex-daybreak` →
  "daybreak"), placed so RunCat ignores it.

## Delivery (decided)

- A small **agent on the Mac** (launchd user agent) watches both snapshot files. On a change, and as a
  heartbeat every ~5 minutes, if `cgdn1.local` is reachable it sends **numbers only** to the device;
  otherwise it does nothing and tries again next time.
- Transport: the device's existing **ESPHome native API** (encrypted with the device's `api_key`, which
  already lives in `~/qingping-flash/esphome-secrets.yaml` on the Mac). The firmware exposes one
  user-defined API action, roughly `set_usage(service, five_hour, seven_day, account, age_s)`:
  `service` ∈ {claude, codex}; percentages 0–100 (clamped/validated on the device); `account` a short
  label (≤ 12 chars, ASCII); `age_s` = seconds since the source file's own update time.
- **Age without trusting a clock:** the device keeps age as `age_s` + time since it received the update
  (its own uptime), not as a timestamp. Note: the firmware's `time: platform: homeassistant` asks API
  clients for the time, and `aioesphomeapi` answers with the Mac's time, so the agent's connections will
  set the device clock. Night mode is the only consumer and it is **off** (checked 2026-11-02, no window
  set), so this changes nothing visible; accepted (builder's call: don't block the reply).
- Values are not persisted across device reboots (pages show "—" until the next send).

## Firmware changes (this repo)

- Remove PM1.0 from the page list; add two usage page kinds after CO₂; page indicator for the new count.
- Draw the usage pages per `layout-bw.html` (1-bpp) with fonts available in the build (currently Roboto
  Condensed 900 at 18/16 px and Bold 14 px; a larger digit size for the percentages is needed — add one
  font size, or reuse the stock HUGE digit glyphs if they fit; the stale state needs an outlined look).
- New pages take part in the existing burn-in drift and slide animation like the other pages.
- The status LED shows no air-quality colour on the usage pages (they aren't a reading).
- API action as above; reject out-of-range values instead of drawing them.
- Keep every existing safety property: digest-protected dashboard, no web OTA, no captive portal, lwIP ACD,
  stock-compatible BLE broadcast.

## Deploy

Same stock-preserving route as before: dashboard/API "Boot other firmware slot" → stock boots →
`~/qingping-flash/resume-flash.sh` pushes the new image (stock writes only the ESPHome slot). Never ESPHome
OTA. The Mac must be on OfficeGuest at 192.168.10.209 (the stock broker address).

## Left to the builder

- Exact pixel layout within mockup B, font size choice, dim level.
- Agent language/structure (the Mac already has `~/qingping-flash/venv` with `aioesphomeapi`), file
  watching method, launchd plist, heartbeat interval within "a few minutes".
- Snapshot file names/locations and atomic-write details.
- Host tests for the new drawing/age logic in the style of `tests/test_stock_page.py`.

## Decisions made during review (2026-11-02)

- Black and white instead of grayscale (owner).
- Remove the PM1.0 page (owner asked to delete the "second PM10" page; it is the PM1.0 page).
- Page position after CO₂, before temperature (owner: "after CO₂/PM").
- Device clock gets set by the agent's API connection; accepted because night mode is off (my call).
- Codex account label: derived from `CODEX_HOME` in the hook; stored next to (not inside) RunCat's
  fields or as an extra key RunCat ignores — builder's call.
