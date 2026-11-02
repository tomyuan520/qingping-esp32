# usage-display — update log and handoff

Mac side of the CGDN1 (ESPHome) usage pages: sends the Claude and Codex 5-hour / weekly used
percentages to the monitor's encrypted API action `set_usage`. Numbers and a short Codex account
label only — no credentials, tokens or auth files ever leave the Mac. The firmware side lives in
`esphome-cgdn1` branch `local-dashboard` (see its `docs/local-changes.md`). Not published; no remote.

## State (2026-11-02 16:00 JST)

- Installed and running as the launchd agent `local.qingping.usage-agent` (from this checkout through
  the symlink `~/qingping-flash/usage-agent`); log `agent.log` here (git-ignored).
- Tests: `~/qingping-flash/venv/bin/python -m pytest` → 13 passed.

## Update log

| Commit | Change |
|--------|--------|
| 39f7e86 | `usage_display/snapshots.py` + `claude_statusline_hook.py`: snapshot writers (Claude status line JSON `rate_limits`; Codex `token_count.rate_limits` windows 300 / 10080 min, account from `CODEX_HOME`) |
| e4e9636 | `usage_display/agent.py`: poll every 30 s, send on change or every 5 min, API key from `~/qingping-flash/esphome-secrets.yaml` |
| 3ad137e | Reject NaN/inf, cap age at int32, a bad snapshot can't stop the loop |
| 6529d2e | launchd plist |

## Wiring outside this repo (re-create on another Mac)

- `~/.claude/settings.json` → `statusLine.command` starts with
  `input=$(cat); (printf '%s' "$input" | /usr/bin/python3 ~/qingping-flash/usage-agent/claude_statusline_hook.py >/dev/null 2>&1 &); …`
  (backup of the original: `~/.claude/settings.json.bak-usage-display`).
- Codex Stop hook `runcat-hook.py` (`~/.codex/runcat-hook.py` → `~/.codex-daybreak/runcat-hook.py`):
  `write_usage_display_snapshot(token_count)` after `latest_token_count(...)` writes
  `~/.codex/usage-display.json` (backup `~/.codex/runcat-hook.py.bak`).
- `sed "s#/Users/YOUR_USER#$HOME#g" local.qingping.usage-agent.plist > ~/Library/LaunchAgents/local.qingping.usage-agent.plist && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.qingping.usage-agent.plist`
  — then allow Python in System Settings → Privacy & Security → **Local Network** (without it every
  connect fails with errno 65 "No route to host").
- The plist's absolute paths use the placeholder `/Users/YOUR_USER/`; the `sed` above fills in your home folder.

## Open issues / next steps

1. **Pages blank up to 5 min after a monitor reboot** (it forgets the numbers; we resend only on
   change or heartbeat). Fix: resend immediately after a failed→reachable transition, i.e. reset
   `state["sent_at"]` when "device reachable again" is logged, or use a shorter heartbeat.
2. Codex snapshot updates only when a Codex session stops; after 1 h the page shows the stale look.
3. Deferred minors: `send()` has no overall timeout; a "sent" line every heartbeat (~288/day) and
   `agent.log` is never rotated.

## Before publishing

- Generalise the absolute paths in the plist and the account name "daybreak" in the tests if wanted.
- Secrets: none in the repo (`agent.log` ignored; the API key is read at runtime).
