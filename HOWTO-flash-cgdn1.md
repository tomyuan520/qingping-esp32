# Flashing a Qingping Air Monitor Lite (CGDN1) with ESPHome — runbook

What we did on 2026-10-30 for the office monitor, written so it can be repeated on another monitor
or from another computer. Firmware: [nemethhh/esphome-qingping-cgdn1](https://github.com/nemethhh/esphome-qingping-cgdn1)
(read its README and `docs/install.md` first). Menubar app: [andreugordillovazquez/QingpingMenuBar](https://github.com/andreugordillovazquez/QingpingMenuBar),
forked locally with a "Local (ESPHome)" data source.

> **Risk:** the stock OTA has no signature check and no rollback. An image that boots but dies before
> WiFi comes up can only be recovered over UART, which means opening the case (glued-in screen).
> Always do the trial install first.

## How it works in one paragraph

The stock firmware (4.8.x) can be pointed at your own MQTT broker ("Private Access Config" on
developer.qingping.co). Once it talks to your broker, a `type "23"` message on its *down* topic makes
it download a firmware URL from your computer, write it to the spare OTA slot, check a CRC trailer
and reboot into it. Stock stays in the other slot. A *trial* ESPHome build marks stock as the next boot
on every boot, so any reboot returns to stock; the *permanent* build is pushed the same way, from stock,
and only overwrites the trial slot, so "Boot other firmware slot" can still bring stock back.

## What you need

- The monitor on stock firmware **4.8.x** (Settings → About), on **mains power** for the flash.
- A computer on the **same network** as the monitor, and a network where devices can reach each
  other (guest WiFi often blocks this — test: can your computer ping your phone on that WiFi?).
  2.4 GHz WiFi with a WPA2 password (ESPHome can't click through a captive portal).
- Docker (for Mosquitto and the ESPHome build). On a Mac: Xcode for the menubar app.
- The monitor's **Wi-Fi MAC** (upper case, no separators, e.g. `CCB5D131D278`). It's in the Qingping
  developer API device list, or in the MQTT topic once it connects.

## Per-device / per-location values

| Value | Office unit (2026-10-30) | Where it's used |
|---|---|---|
| Wi-Fi MAC | `CCB5D131D278` | push tool `--mac`, topics `qingping/<MAC>/up|down` |
| Broker host | `192.168.10.209` (the Mac) | portal config `host=`; push tool `--broker` |
| WiFi | OfficeGuest | `secrets.yaml` `wifi_ssid` / `wifi_password` |
| Device IP / mDNS | 192.168.10.200 / `cgdn1.local` | dashboard, API, menubar app host |

For another monitor, change the MAC, WiFi, and the broker IP (and keep the computer's IP stable —
see gotchas). For two ESPHome monitors on one network, give the second a different `name`
substitution in `cgdn1.yaml` so mDNS names don't clash.

## Steps

### 1. Broker (Mosquitto in Docker)

```sh
mkdir -p ~/qingping-flash/mosquitto/{config,data}
docker run --rm -v ~/qingping-flash/mosquitto/config:/mosquitto/config eclipse-mosquitto:2 \
  mosquitto_passwd -b -c /mosquitto/config/passwd qingping '<broker-password>'
cat > ~/qingping-flash/mosquitto/config/mosquitto.conf <<'EOF'
listener 1883 0.0.0.0
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest stdout
log_type all
connection_messages true
EOF
docker run -d --name qingping-mosquitto --restart unless-stopped -p 1883:1883 \
  -v ~/qingping-flash/mosquitto/config:/mosquitto/config \
  -v ~/qingping-flash/mosquitto/data:/mosquitto/data eclipse-mosquitto:2
# Payload logger: every message to mosquitto/data/sub.log (re-run after a container restart;
# resume-flash.sh does it for you). monitor-status.sh reads it.
docker exec -d qingping-mosquitto sh -c "mosquitto_sub -h localhost -u qingping -P '<broker-password>' \
  -t '#' -v -F '%I | %t | len=%l | %p' >> /mosquitto/data/sub.log 2>&1"
```

### 2. Point the monitor at it (developer.qingping.co)

Private Access Config → Configurations → new, model "Qingping Air Monitor Lite", type "Self-built MQTT":

```
endpoint=
protocol=mqtt
host=<computer IP>
port=1883
username=qingping
password=<broker-password>
clientId=qingping-{mac}
topicUp=qingping/{mac}/up
topicDown=qingping/{mac}/down
```

Then Private Access Config → Device → add the monitor, assign the config, and power-cycle it.
Check it arrives: `docker logs -f qingping-mosquitto` should show client `qingping-<MAC>` and a
~300-byte publish on `qingping/<MAC>/up` (a `"type": "13"` hello with `sw_version`).
No factory reset was needed for the first config; per GreyEarl's notes, *changing* an assigned config
does need one. Once on private MQTT the monitor stops uploading to the Qingping cloud/app.

### 3. Build the trial image

```sh
git clone https://github.com/nemethhh/esphome-qingping-cgdn1 && cd esphome-qingping-cgdn1
cp secrets.yaml.example secrets.yaml   # wifi_ssid/password, api_key (openssl rand -base64 32),
                                        # ota_password, ap_password, (web_username/web_password)
docker run --rm -v "$PWD":/config ghcr.io/esphome/esphome:2026.9.1 \
  -s trial_mode true -s api_reboot_timeout 15min compile cgdn1.yaml
docker run --rm -v "$PWD":/config --entrypoint bash ghcr.io/esphome/esphome:2026.9.1 -c \
  "pip install -q pytest paho-mqtt; cd /config && python -m pytest tests/test_esphome_image.py -rs"   # 7 passed, no skips
```

(`api_reboot_timeout` exists only in our local branch, see step 7; upstream already uses 15 min.)

### 4. Push it

The push tool must run **natively** on the computer, not in Docker: Docker's NAT makes its delivery
check report success too early (that's how you brick it). On macOS it needs our `SO_NWRITE` patch
(branch `local-dashboard`, `tools/cgdn1_ota_push.py`); on Linux it runs as-is.

```sh
python3 -m venv venv && venv/bin/pip install paho-mqtt
venv/bin/python tools/cgdn1_ota_push.py .esphome/build/cgdn1/build/firmware.ota.bin --append-crc \
  --broker <computer IP> --mac <MAC> --pw-file broker.pw --dry-run      # check the URL, then without --dry-run
```

The monitor only listens while it's connected (see gotchas), so use a **retained** command and a
long-running server instead of the tool's one-shot message — `resume-flash.sh` in this folder does
exactly that for the office unit (start server, publish retained `type 23`, watch, clear on success).

### 5. Check the trial

ESPHome comes up as `cgdn1.local`; the stock MQTT hellos stop. Read it over the API
(`read_esphome.py` in this folder) or, with the dashboard, open `http://cgdn1.local`.
Check `dump_config` says `Trial mark result: OK` (`esphome logs`).

### 6. Back to stock for the permanent push

Press **Restart** (API: `press_button.py <api_key> Restart`) or leave it 15 min without an API client:
trial mode boots stock. **Never** use ESPHome's own OTA while stock should be kept — it writes the
other slot (= stock).

### 7. Build and push the permanent image

Our branch `local-dashboard` changes upstream `cgdn1.yaml` to:
- add `web_server` (v3, local assets, **digest** login) for a browser dashboard;
- **remove `captive_portal`** — it auto-loads `ota.web_server`, which would expose a firmware upload
  on the LAN that overwrites stock (verify: `grep USE_WEBSERVER_OTA .esphome/build/cgdn1/src/esphome/core/defines.h` must be empty);
- make the API `reboot_timeout` a substitution, default `0s` (otherwise, without Home Assistant, it reboots every 15 min).

Build without `-s trial_mode true`, run the image test, push like step 4 from stock.
Stamp the build so the dashboard's Device info → Firmware row names the commit:
`docker run --rm -v "$PWD":/config ghcr.io/esphome/esphome:2026.9.1 -s fw_rev "$(git rev-parse --short HEAD)" compile cgdn1.yaml`

### 8. Menubar app (macOS)

Fork branch `esphome-source` adds "Local (ESPHome)": host / username / password in Settings, live
readings from the dashboard's `/events` stream. Build without opening Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project QingpingMenuBar.xcodeproj \
  -scheme QingpingMenuBar -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
```

## Different network or a different computer (e.g. at home, Linux)

**Another monitor, flashed at home from a Linux box.** Everything per-network has to be redone:
- Pair the monitor with your home WiFi in the Qingping+ app first (it needs WiFi + cloud once to
  receive the portal config).
- Make a **new** portal config (don't edit "local-mac": changing an assigned config needs a factory
  reset, and the office unit uses it) with `host=` the Linux box's home IP; assign it to the new monitor.
- `secrets.yaml`: home `wifi_ssid` / `wifi_password`; new keys are cheap (`openssl rand`).
- Linux is the easier host: the push tool runs unmodified (no `SO_NWRITE` patch needed), Docker has
  no NAT in front of the host if you run Mosquitto with `--network host` or natively (`apt install mosquitto`).
- With Bluetooth on the Linux box there's an alternative to the portal: `bitrate16/qingping`
  (`pip install qingping`, pygatt/BlueZ) sets WiFi **and** the MQTT broker over BLE in pairing mode,
  fully offline. We didn't use it, so treat it as untested (see the ESPHome repo's `docs/install.md`).

**Taking the office monitor home while it's still on stock** (the plan if the office flash doesn't
finish). Its stock firmware knows OfficeGuest and the broker 192.168.10.209 — neither exists at home:
1. Clear the stuck update state first: battery flat (unplugged overnight), then plug in.
2. Qingping+ app: re-pair it with the home WiFi.
3. Portal: new config with `host=` the Linux box's IP; reassign the monitor to it, then factory-reset
   it so it takes the new config (or use the BLE tool above instead of steps 2–3).
4. On the Linux box: unpack `qingping-flash-portable.tgz` into your home directory, then
   `git -C ~/qingping-flash/esphome-cgdn1 worktree repair .claude/worktrees/permanent` (the worktrees
   recorded this Mac's paths). `python3 -m pip install paho-mqtt`; in the `permanent` worktree set
   `secrets.yaml` → home WiFi, rebuild (step 3, without `-s trial_mode true`), run the image test.
5. `BROKER_IP=<linux ip> ./resume-flash.sh`, then make sure the monitor (re)connects.

**Moving an already-flashed monitor to another WiFi** (since 2026-11-02, commit 12376fc). Only the
office WiFi is built in. Anywhere else it can't connect, so after about a minute it opens its fallback
hotspot `cgdn1 Fallback` (password `ap_password` in esphome-secrets.yaml):
1. Join `cgdn1 Fallback` from a phone or laptop and open **http://192.168.4.1** (not cgdn1.local);
   log in with the dashboard login.
2. In the **Add WiFi** section type the network name and password, press **Connect to WiFi**. The
   status line confirms; it joins the network when in reach and the hotspot closes. (iPhone hotspot:
   turn on "Maximize Compatibility" — the ESP32 is 2.4 GHz only.)
3. The network shows as **Extra WiFi** in Device info. It is kept next to the built-in one, survives
   reboots and reflashes, and is replaced by the next one you add.

The page only accepts entries while the fallback hotspot is up (the dashboard is plain HTTP; only the
hotspot link is encrypted). From a computer on the same network as the monitor, use the encrypted API
instead: `venv/bin/python ~/qingping-flash/set-wifi.py "Network name"` (asks for the password;
`--host 192.168.4.1` over the fallback hotspot; `--forget --restart` removes it). No captive portal, so
phones don't pop the page up by themselves. Flashing still needs the stock route at the office.

## Gotchas we hit (read these)

1. **The monitor isn't always connected.** Stock connects for a while (we saw ~15 min when idle),
   drops off for ~10 min, reconnects. A one-shot OTA command sent in a gap is lost. Use a retained
   command, keep the image server up, clear the retained message after success.
2. **A download needs ~4–8 min** (1.5 MB at 3–7 KB/s; the monitor writes flash between reads). No resume:
   every attempt starts from 0.
3. **Don't interrupt downloads.** After several aborted downloads the stock firmware got stuck on its
   "updating" screen, ignored the button, and every new attempt aborted within ~3 min regardless of
   speed (`--max-rate` didn't help). Only a real reboot clears it.
4. **The back button only powers off on battery, and only when released** after ≥2 s (the button
   powers the board while held). It does nothing in the stuck update state. Last resort: unplug and
   let the battery run flat, then plug in with the broker and server already running.
5. **Keep the computer's IP fixed** — the portal config has it hard-coded; changing the config later
   needs a factory reset. On a Mac: Wi-Fi → Details → TCP/IP → "Using DHCP with manual address".
6. **Docker on Mac** is fine for Mosquitto and building, not for the push (NAT); the broker sees the
   monitor as `192.168.65.1` because of that NAT, which is expected.
7. **`captive_portal` + `web_server` = firmware upload on the LAN** (see step 7).
8. **The menubar app's Bluetooth mode stops working after ESPHome** (no stock BLE advertisement); use
   the Local (ESPHome) mode.
9. macOS needs Bluetooth permission per app; a terminal (iTerm) needs it granted before BLE scans work.
10. **There is no remote reboot.** Qingping's official CGDN1 ("Dany") MQTT protocol
    (`https://developer.qingping.co/static/media/dany_mqtt_protocol_en.63683337.md`) lists only:
    17 = settings (report intervals, screen, offsets; acked with 18), 12 = temporary realtime
    interval, 28 = read config, **16 = change MQTT server**. OTA (23/24) isn't documented. Sending type 16 with
    the same settings made the monitor reconnect to MQTT within a second — no reboot, stuck screen stayed.
11. **Type 16 re-points the broker live**, no portal and no factory reset — but only while the monitor
    is connected to the current broker. Payload: `{"type":"16","desc":"change env","timestamp":<now>,
    "host":{"host":"<ip>","port":"1883","user":"…","password":"…","client_id":"qingping-<MAC>",
    "sub_topic":"qingping/<MAC>/down","pub_topic":"qingping/<MAC>/up"}}`. Untested whether a later
    Qingping+ WiFi re-pair keeps or overwrites it.
12. The `"timestamp"` in the type-13 hello is the monitor's clock: seconds since boot until something
    sets it (type 16's `timestamp` does), then real Unix time. Once it's real time, a hello with a
    small clock again is the reliable sign of a fresh boot / real power loss.
13. **Don't detect a dead battery by ping.** Losing ping for 3 min was just weak WiFi (-77 dBm after the
    monitor was moved); the clock showed it never lost power. Weak signal alone also breaks downloads
    (one died after 20 s) — keep the monitor where the signal is ~-60 dBm or better.
14. **On battery, stock switches off the CO₂ and PM sensors** (`status: 1` in the type-12 report), so the
    battery lasts long: about 100 % → 85 % in 2.5 h (roughly 6 %/h, readings are coarse). Draining it
    for a hard reboot takes most of a night.
15. **Live battery reading:** send `{"type": "12", "up_itvl": "10", "duration": "60"}` on the down topic;
    the monitor answers with a type-12 report (battery, temperature, humidity, CO₂, PM). Or just run
    `monitor-status.sh` (connection, clock/fresh boot, WiFi, battery).

16. **Stock BLE broadcast format** (captured 2026-11-02 from stock 4.8.5, name "Qingping Air Monitor Lite"):
    service data UUID 0xFDCD = `88 24 <MAC reversed> 01 04 <T*10 LE> <RH*10 LE> 12 04 <PM2.5> <PM10> 13 02 <CO2>`
    — one 31-byte packet, no battery. Our ESPHome build re-creates it (interval "Qingping BLE broadcast",
    `esp32_ble: advertising: true`) as three rotating packets (T/RH + CO₂, PM + CO₂, T/RH + battery).
17. **IP conflict on OfficeGuest:** another device (MAC `de:44:89:5a:ea:bf`, a locally administered
    address; its web page says "Web Image Monitor", i.e. a Ricoh printer) sometimes answers at
    192.168.10.200 — likely asleep when the DHCP check ran. Mac→.200 traffic then lands on it and gets
    reset (the "Broken pipe" aborts). Fixed 2026-11-02 in firmware: `CONFIG_LWIP_DHCP_DOES_ACD_CHECK`
    (RFC 5227 ongoing detection: defend once, on a second conflict within 10 s decline the lease and get
    a new one). The monitor moved to 192.168.10.117. Use `cgdn1.local`, not a fixed IP. Worth telling IT.

## Files in this folder

| File | What |
|---|---|
| `resume-flash.sh` | finish the permanent flash after a reboot (`BROKER_IP=…` elsewhere) |
| `watch-success.sh` | wait for the monitor (by IP) to finish a download, then clear the command |
| `live.py` | live readings in the terminal every 10 s (stock via broker; ESPHome via dashboard), `venv/bin/python live.py` on the Mac, `python3 live.py` elsewhere |
| `monitor-status.sh` | connection, fresh-boot check, WiFi, live battery of the stock monitor |
| `docs/dany_mqtt_protocol_en.md`, `_zh.md` | Qingping's official CGDN1 ("Dany") MQTT protocol |
| `esphome-cgdn1/.claude/worktrees/permanent` | firmware repo, branch `local-dashboard` |
| `QingpingMenuBar/.claude/worktrees/esphome-source` | menubar app fork, branch `esphome-source` |
| `esphome-secrets.yaml`, `BROKER-CREDS.txt`, `broker.pw` | secrets (WiFi, API key, logins) — keep private |
| `mosquitto/` | broker config, password file, data |
| `read_esphome.py`, `press_button.py` | read sensors / press a button over the ESPHome API |
| `DESIGN-cgdn1-esphome.md` | design notes written before the flash |
| `chat-2026-10-30.md`, `chat-2026-10-30.jsonl` | this session's conversation (contains secrets) |

## Status of the office unit (2026-11-02) — done (BLE broadcast added 10:23)

**Flashed.** After the user reset the monitor (fresh boot cleared the stuck update state),
`resume-flash.sh` pushed the permanent image in one clean 4m43s download (09:47–09:52, on USB, Mac
on OfficeGuest at 192.168.10.209). It booted ESPHome: dashboard `http://cgdn1.local` with digest
login (401 without login, basic refused, `/update` behaves like any unknown page), live CO₂/PM/T/RH,
stock firmware kept in the other slot.

Menubar app fork installed in `/Applications` (original backed up to
`QingpingMenuBar-original.app`), Local (ESPHome) mode streaming. After the swap macOS asked for the
Keychain items the original app had created (Cloud API key/secret); we deleted those two entries.
Grant the app Local Network access (System Settings → Privacy & Security → Local Network).

**Updating the firmware later:** keep stock → dashboard "Boot other firmware slot", then
`resume-flash.sh` with the new image (stock writes only the ESPHome slot). Don't care about stock →
`esphome run cgdn1.yaml --device cgdn1.local` (ESPHome OTA, uses `ota_password`; first time overwrites
stock). There's deliberately no upload button on the dashboard.

**10:23 update:** reflashed (stock-preserving route: "Boot other firmware slot" → captured stock BLE packet →
`resume-flash.sh`, 3m48s) with the stock-compatible BLE broadcast; verified all three packets decode. The
menubar app fork (b98d1bd) keeps the last value per reading in Bluetooth mode, so it works off-network
within Bluetooth range.

**10:43 update:** reflashed again (commit e3ba592) with lwIP ongoing conflict detection; the stock boot in
between already declined .200 (other device awake) and got 192.168.10.117, which ESPHome kept. Verified:
dashboard 401/digest, BLE broadcast (all 3 packets), uptime steady.

**11:41 update:** Claude / Codex usage pages (after CO₂; PM1.0 page dropped), fed by the Mac launchd agent
`local.qingping.usage-agent` over the encrypted API action `set_usage` (numbers + account label only).

**14:53 update:** commit c7b6ceb — status LED steady orange on the Claude page, blue on the Codex page
(was off). Same route, 3m47s; the agent re-sent its numbers 30 s after the reboot (the device doesn't keep
them across reboots, so the pages show "—" until then).

**15:20 update:** commits 264f988 + f416d29 — dashboard "Device info" group (name, IP, MAC, WiFi,
signal dBm/%, uptime, firmware + `fw_rev` stamp, OTA slots, chip, flash, panel, memory, last reset)
and a "Log factory info" button. Readings on this unit: slots are named `miio_fw1`/`miio_fw2` on the
device (not the CSV names); the other slot reports `miio_app Sparrow_v1.0.2-264-g6c0ce49` (= stock);
ESP32 package code 3 (not in Espressif's list), rev v1.0, 2 cores 240 MHz; flash Boya 4 MB (684016).
"Last reset: exception/panic" right after a flash is stock's post-update restart, not an ESPHome crash.
Factory block (0x3d2000, redacted readout): 8-byte header starting 'Z', a 16-char upper+digit id at
+0x4b (length byte at +0x4a), panel byte 01 at +0x5d, nothing else — no PCB revision stored there.


> **Don't test the image server by downloading the image yourself** while a success watcher runs: the
> server logs "acknowledged all bytes" for any client. `watch-success.sh` and `resume-flash.sh` only count
> a download whose client isn't this computer (`watch-success.sh` takes the monitor's IP explicitly).
