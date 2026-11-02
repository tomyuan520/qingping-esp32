# Local changes on `local-dashboard` — update log and handoff

Branch `local-dashboard` = upstream `main` (nemethhh/esphome-qingping-cgdn1, 81e2719) + the owner's
local build. Not published yet: `origin` is still the upstream repo, nothing has been pushed.
This file is the starting point for continuing the work on another machine.

## State (2026-11-02 16:00 JST)

- Flashed on the office unit ("Office Air Monitor", Wi-Fi MAC CC:B5:D1:31:D2:78, `cgdn1.local`):
  **12376fc**, built with `-s fw_rev 12376fc`. Stock 4.8.5 is kept in the other OTA slot.
- Tests: `pytest` (host, Python + system C++ compiler) → 264 passed, 4 skipped (stock image /
  esptool not available); image test in the ESPHome container → 7 passed.
- Everything is committed; the working tree is clean.

## Update log (oldest first)

| Commit | Date | Change |
|--------|------|--------|
| 1a5850c | 10-30 | Web dashboard (web_server v3, local assets), API reboot timeout as a substitution (default 0s), macOS `SO_NWRITE` support in `tools/cgdn1_ota_push.py` |
| 161760a | 10-30 | Drop `captive_portal`: it adds a firmware upload that would overwrite stock |
| 2695276 | 10-30 | Dashboard digest login |
| 2ba67de | 10-30 | `cgdn1_ota_push.py --max-rate` (paced image serving) |
| b0dc8a7 | 11-02 | Stock-compatible BLE broadcast (Qingping service data 0xFDCD), so the Qingping menubar app's Bluetooth mode works |
| e3ba592 | 11-02 | lwIP ongoing address conflict detection (guest WiFi printer took our DHCP address) |
| af07927, cf8e1d0 | 11-02 | Design + plan: Claude/Codex usage pages (`docs/superpowers/`) |
| 94ece0d, 0417e61, 14d9f33 | 11-02 | Usage pages "Claude" / "Codex" after CO₂ (5h + 7d %, stale after 1 h, "—" without data), API action `set_usage`, PM1.0 page dropped; info-page out-of-bounds fix |
| c7b6ceb | 11-02 | Status LED orange on the Claude page, blue on the Codex page |
| 264f988, f416d29 | 11-02 | Dashboard "Device info" group (name, IP, MAC, WiFi + signal %, uptime, firmware + `fw_rev`, OTA slots, chip, flash, panel, memory, last reset); "Log factory info" button whose readout never prints codes or keys |
| d51a955, 12376fc | 11-02 | Extra WiFi network: dashboard "Add WiFi" section (only while the fallback hotspot is up) and API actions `set_wifi` / `forget_wifi` (`tools/cgdn1_set_wifi.py`); kept across reflashes, added next to the built-in network |

## Build and flash (stock-preserving)

```sh
docker run --rm -v "$PWD":/config ghcr.io/esphome/esphome:2026.9.1 \
  -s fw_rev "$(git rev-parse --short HEAD)" compile cgdn1.yaml
docker run --rm -v "$PWD":/config --entrypoint bash ghcr.io/esphome/esphome:2026.9.1 -c \
  "pip install -q pytest paho-mqtt; cd /config && python -m pytest tests/test_esphome_image.py -q"
```

Then: start `resume-flash.sh` (image server + retained MQTT type-23 command), press the dashboard's
"Boot other firmware slot"; stock downloads the image and writes only the ESPHome slot. **Never** use
ESPHome OTA / a web upload while stock should be kept (it writes the stock slot). Before flashing,
check `grep USE_WEBSERVER_OTA .esphome/build/cgdn1/src/esphome/core/defines.h` is empty. Full
procedure and gotchas: the owner's runbook `~/qingping-flash/HOWTO-flash-cgdn1.md` (outside git).

## Moving to another machine

- Copy the whole repo directory (the `local-dashboard` worktree lives inside it at
  `.claude/worktrees/permanent`), then `git worktree repair .claude/worktrees/permanent` — worktrees
  record absolute paths.
- `secrets.yaml` is git-ignored and **not** in the repo: carry it separately (keys in
  `secrets.yaml.example`). Without the same `api_key`, the dashboard tools and the usage agent can't
  talk to the flashed unit.
- The flash route needs the broker machine at the address stock was configured with (office:
  192.168.10.209 on the guest WiFi); elsewhere stock needs a new MQTT config first (runbook, "home").
- The `main` checkout has an uncommitted copy of the early `SO_NWRITE` patch in
  `tools/cgdn1_ota_push.py`; the committed version on this branch supersedes it — safe to discard.

## Open issues / next steps

1. **Usage pages blank for up to 5 min after a device reboot.** The device doesn't keep usage
   numbers across reboots; the Mac agent resends only on change or every 5 min. Fix on the agent side
   (resend right after a reconnect) or keep them in the device's RAM-backed RTC memory.
2. **Codex page goes stale** when no Codex session has finished for an hour: the Codex hook writes
   its snapshot only on Stop. Expected behaviour, but reads as "no numbers" (hollow digits).
3. Deferred minors from the usage review: a long (>~9 char) Codex account label can overprint the
   title; the age counter wraps after 49.7 days; the agent's send has no overall timeout; the agent
   logs a line every heartbeat.
4. Not tested on the device: saving a network from the "Add WiFi" page on the fallback hotspot (the
   same store() is tested through `set_wifi`).
5. Factory block holds no PCB revision; stock's `hw_version "0001"` is in its code or the 8-byte
   header (deliberately not printed).

## Before publishing

- Pick your own remote (`origin` is upstream); push `local-dashboard` there, not to upstream.
- Secrets: no secrets file was ever committed and no API key is in a tracked file (checked).
- Personal details in tracked files you may want to generalise: the network name and broker IP in
  `docs/superpowers/` (design/plan), the device MAC in `tests/test_info.py`. Consider dropping
  `docs/superpowers/` and this file from a public branch.
- Upstream licence/README: credit nemethhh/esphome-qingping-cgdn1 as the base.
