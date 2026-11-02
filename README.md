# qingping-esp32

Local control for a Qingping Air Monitor Lite (CGDN1): ESPHome firmware flashed through the stock
firmware's own update path (stock stays in the other OTA slot), a Mosquitto broker for that update,
a browser dashboard, a macOS menubar app, and Claude / Codex usage pages on the monitor's screen.

This is a single snapshot of the working folder; each project keeps its own licence.

| Folder | What | Based on |
|--------|------|----------|
| `esphome-cgdn1/` | ESPHome config + components for the CGDN1 (dashboard, Device info, usage pages, BLE broadcast, Add WiFi, ...). Change log: `esphome-cgdn1/docs/local-changes.md` | [nemethhh/esphome-qingping-cgdn1](https://github.com/nemethhh/esphome-qingping-cgdn1) (MIT) |
| `usage-display/` | Mac agent that sends the Claude / Codex 5h + weekly usage % to the monitor (numbers only, encrypted API). Notes: `usage-display/NOTES.md` | — |
| `QingpingMenuBar/` | macOS menubar app with a local ESPHome source and Bluetooth mode | [andreugordillovazquez/QingpingMenuBar](https://github.com/andreugordillovazquez/QingpingMenuBar) (MIT) |
| `HOWTO-flash-cgdn1.md` | Runbook: broker, building, the stock-preserving flash, gotchas | |
| `DESIGN-cgdn1-esphome.md` | Original design notes | |
| `resume-flash.sh`, `*.py`, `*.sh` | Flash, monitoring and API helper scripts | |
| `docs/` | Stock MQTT protocol notes (EN / ZH) | |
| `mosquitto/config/mosquitto.conf` | Broker config (the password file is not included) | |

## Not included (create your own)

- `esphome-cgdn1/secrets.yaml` (template: `esphome-cgdn1/secrets.yaml.example`) and
  `esphome-secrets.yaml` (same keys; read by the helper scripts and the usage agent)
- `broker.pw` (MQTT password for the helper scripts) and `mosquitto/config/passwd`
  (`mosquitto_passwd -c mosquitto/config/passwd qingping`)
- Python venv: `python3 -m venv venv && venv/bin/pip install paho-mqtt aioesphomeapi pytest`

## Safety

Never use ESPHome OTA or a web upload while you want to keep the stock firmware: they write the
other slot. Flash only through "Boot other firmware slot" + `resume-flash.sh`; see the runbook.
