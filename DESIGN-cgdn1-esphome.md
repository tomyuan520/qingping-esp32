# Design: Flash ESPHome onto a Qingping Air Monitor Lite (CGDN1)

Date: 2026-10-30

## Intent and why

The owner has a Qingping Air Monitor Lite (CGDN1, "Office Air Monitor", MAC
`CCB5D131D278`, stock firmware 4.8.5, WiFi). Its uploads to the Qingping cloud
stopped on 2026-03-31 20:15 JST — the developer API still lists the device as
`offline: false` but has had no data points since. Bluetooth reads work, so the
hardware is fine; the cloud path is dead.

The owner wants **full local control of hardware they own** and the ability to
**customize it** (first target after this project: make the screen display
something other than stock). The chosen route is to replace the stock firmware
with the open-source ESPHome firmware from
[nemethhh/esphome-qingping-cgdn1](https://github.com/nemethhh/esphome-qingping-cgdn1),
which runs entirely local with the stock screen, touch slider, LED, battery and
all sensors re-created.

The owner is explicitly comfortable with the risk of bricking the device.

## Goals

- Get **stock (unmodified) ESPHome firmware running** on the CGDN1 — this is the
  whole scope of this project. "Stock ESPHome" means the repo's `cgdn1.yaml` as
  shipped, no feature customization yet.
- Do it via **Route A**: the owner's Mac plus a bridged-network Linux VM, no new
  hardware.
- Reach the device's readings locally after the flash (ESPHome's built-in web
  server + native API are sufficient; see non-goals).
- Along the way, inspect the Qingping developer portal to understand the March
  cloud outage (opportunistic, not blocking).

## Non-goals

- **No Home Assistant** in this project. ESPHome's own web page and native API
  are the consumer for now. HA can be added later and is out of scope here.
- **No feature customization** of the firmware yet (custom screen pages, LED
  thresholds, MQTT screen notifications). That is a separate follow-up project,
  decided after stock ESPHome boots.
- **No permanent change to the office network.** The office monitor normally
  lives on an isolated guest WiFi; this project only needs a temporary shared
  network for the flash.
- **No reliance on the Qingping cloud** as an end state.

## Anti-goals (these make it a failure even if it "works")

- Using the leaked eMudhra CA (or any forged-certificate / TLS-interception
  approach). Explicitly rejected: it is stolen cryptographic material whose scope
  is far beyond this device, and it does not advance the goal. Not part of this
  design in any form.
- Handing over or using the owner's Qingping developer-portal session cookie or
  password. Portal steps are performed by the owner in their own browser.
- Leaving the device in a state recoverable only by opening the glued-in case —
  mitigated by trial-mode (below), though the residual risk is accepted.

## Constraints and known risks

- **Guest-WiFi isolation.** The office guest network almost certainly blocks
  device-to-device traffic, so the flash cannot happen there. A temporary normal
  network (owner's home network preferred over a phone hotspot, because VM
  bridging is more reliable on a real LAN) is required for the flash window.
- **Both helper tools are Linux-only.**
  - The OTA push tool (`tools/cgdn1_ota_push.py`) confirms delivery with the
    Linux `TIOCOUTQ` socket ioctl; on macOS this does not report the socket
    output queue, and that check is how you know the image actually reached the
    device. Must run on Linux.
  - The BLE provisioning tool (`bitrate16/qingping`) uses `pygatt`, which needs
    Linux BlueZ. **This design avoids it entirely** by provisioning through the
    Qingping developer portal instead (browser, no Bluetooth, no Linux).
- **The push tool needs the device to connect back to it over TCP.** The Linux
  environment therefore needs its own reachable address on the shared LAN — a
  **bridged** VM NIC, not Docker-on-Mac NAT. If bridging cannot be obtained on
  the available network, fall back to Route B.
- **The provisioning channel rides the dead cloud, and the flash depends on it.**
  The three stock-firmware control actions Route A needs — set the MQTT broker,
  get the device onto the flash network (WiFi), and factory-reset to apply config —
  all normally go through the Qingping app/cloud, which is exactly the path that
  has had no traffic from this device since 2026-03-31. The OTA push itself also
  rides the broker (it commands the device over MQTT down/up topics; the device
  then pulls the image over TCP 8070). **There is no cloud-free / BLE-free way to
  flash.** So provisioning is the true go/no-go for the whole project, not an
  opportunistic aside. If the portal cannot reach this device, Route A is not
  executable and the only path is BLE provisioning (Route B).
- **WiFi change may require BLE regardless.** The repo documents exactly one way
  to change the stock device's WiFi — the BLE command in pairing mode. The portal's
  Private Access Config is documented as setting MQTT, not WiFi. If the portal
  can't set WiFi, getting the device off the isolated guest network and onto the
  flash network requires either BLE, or cloning the office guest SSID+password
  onto the temp network (needs the guest creds). This is an open risk, resolved
  empirically at step 4–5 below.
- **Firmware is tested on exactly one unit** (stock 4.8.5, panel variant B). The
  owner's unit is also 4.8.5 (good match), but its panel variant is unknown until
  the flash; **panel variant A is untested**. This residual risk is accepted.
- **OTA has no signature check and no rollback.** A malformed image falls back to
  stock; a well-formed image that dies before WiFi comes up is only recoverable
  by opening the case. Trial mode narrows but does not eliminate this.
- The ESP32 factory-MAC eFuse fails CRC on this product line; the YAML already
  sets `ignore_efuse_mac_crc: true` (do not remove it).

## How it gets built (decisions made)

Route A, in order:

1. **Shared network.** Owner connects Mac + monitor to a temporary normal
   network with internet (home network preferred).
2. **Linux environment on the Mac.** A Linux VM with a **bridged** NIC so it gets
   its own IP on that LAN. VM tooling choice (UTM, Multipass, Lima, VirtualBox,
   etc.) is left to the builder; the hard requirement is a bridged NIC reachable
   by the monitor, plus Bluetooth is *not* needed (provisioning is via the
   portal). Inside it: Python 3.10+, `pip install -r requirements.txt` from the
   esphome repo (ESPHome 2026.9.1, paho-mqtt), and Mosquitto.
3. **Broker.** Run Mosquitto on the Linux VM with a username/password dedicated
   to this device. Note its LAN IP and port 1883.
4. **Provision the device → broker (owner, in browser), non-destructively first.**
   In the Qingping developer portal, "Private Access Config": create a config
   pointing at the VM's broker IP/port/credentials and the up/down topics, and
   assign it to the device. **Do not factory-reset yet.** While there, capture
   whatever explains the March outage (existing private config? wrong
   region/account? assigned server?) — that evidence also predicts whether the
   downlink is alive.
5. **GO/NO-GO: does the device publish to our broker?** Reboot the device and
   watch the broker for a type-13 "up" message (roughly once a minute, includes
   `sw_version`).
   - **It publishes →** the cloud downlink works, config took, proceed to step 6.
   - **Nothing after a reboot →** factory-reset the device (the GreyEarl note says
     a reset is needed to apply a changed config) **only now**, having first
     confirmed via the API/portal what stock state we're resetting from, then
     re-check. The reset is the one destructive, pre-flash, outside-trial-mode
     step; it is a deliberate decision point, not an automatic step.
   - **Still nothing →** the cloud/portal cannot reach this device (the March
     outage is the blocker). Route A is dead; **pivot to Route B** (BLE
     provisioning on a Linux box with Bluetooth). Do not attempt the flash.
   This step is the true go/no-go gate for the whole project.
6. **Build the trial image.** `cp secrets.yaml.example secrets.yaml` and fill it
   (`api_key: openssl rand -base64 32`, correct WiFi creds for the temp network,
   MQTT entries matching the broker). `esphome -s trial_mode true compile
   cgdn1.yaml`, then `pytest tests/test_esphome_image.py -rs` (must pass with no
   skips).
7. **Push it.** Allow TCP 8070 inbound in the VM firewall, then run
   `tools/cgdn1_ota_push.py` against `firmware.ota.bin` (never
   `firmware.factory.bin`) with `--append-crc`, `--broker`, `--mac` (WiFi MAC,
   no separators, upper case → `CCB5D131D278`), and `--pw-file`. `--dry-run`
   first. Wait for "monitor acknowledged all N bytes"; retry on undelivered
   bytes. "No hello from the new firmware yet" is the normal success outcome.
8. **Confirm boot.** ESPHome comes up on the temp WiFi; reach its web server /
   native API. Because trial mode is on, any reboot returns to stock — so after
   confirming it's healthy, a second (non-trial) build+push makes ESPHome
   permanent. Keeping stock bootable via the "Boot other firmware slot" button is
   available until an ESPHome OTA overwrites the stock slot.

**Fallback (Route B) — triggered by EITHER a bridging failure OR a provisioning
failure at step 5.** Do the whole thing from a Raspberry Pi or spare Linux laptop
on the LAN, which also becomes the permanent local home for the data. The machine
**must have a working Bluetooth adapter** (Pi onboard BT or a USB BT dongle),
because Route B provisions over BLE with `bitrate16/qingping` (pygatt/BlueZ) — the
one method that does not depend on the dead cloud and can also set WiFi. Note: a
Mac-hosted Linux VM generally cannot use the Mac's built-in Bluetooth reliably, so
Route B wants bare-metal Linux (Pi/laptop), not a VM. Same steps 3 and 6–8.

## Operational notes (builder, settled)

- Keep the device on **mains power** throughout both OTA pushes — OTA has no
  rollback, and a power loss mid-write is the worst case.
- The ESP32 is **2.4 GHz only**; the temp/flash network must offer a 2.4 GHz SSID.

## Left to the builder

- Specific VM/virtualization tool and how bridging is configured.
- Which temporary network is used.
- Exact Mosquitto config, topic names, and credential values.
- Whether, after a healthy trial boot, to immediately do the permanent
  (non-trial) push or dwell in trial mode first.
- How the owner reads the data post-flash (ESPHome web UI vs. a small script
  against the native API) — any of these satisfies the goal.

## Progress / status

- **2026-10-30 — Broker go/no-go PASSED.** Mosquitto running in Docker on the Mac
  (`192.168.10.209:1883`, user `qingping`). After the owner created a portal
  Private Access Config pointing at it and rebooted the monitor (NO factory reset),
  the device connected as client `qingping-CCB5D131D278` and published a type-13
  message on `qingping/CCB5D131D278/up`: `sw_version` 4.8.5, `hw_version` 0001, on
  SSID `OfficeGuest` at -58 dBm, `iot_platform` 0.
- Reviewer risks #1 (portal can reach device), #2 (WiFi change) and #3 (factory
  reset) are all **resolved/avoided**. The device stays on its own WiFi; config was
  applied on a plain reboot.
- Note: the device's connection arrived at the broker from the Docker gateway
  (`192.168.65.1`), confirming Docker-on-Mac NATs the source — so the **push step
  still needs a bridged path** (bridged VM, or a native-macOS patch of the push
  tool's delivery check), not plain Docker. This is the next open item.

### Next: the flash (push step)

The broker stays as the Mac Docker instance (device already connected). The OTA
push must reach the device over a direct socket for its delivery check to be
meaningful.

**CHOSEN: native-macOS push (option 2), validated 2026-10-30.**
- The push tool's delivery check IS the only safety net (no app-level byte-ack; it
  waits on the kernel's unsent+unacked count before telling the device to CRC and
  reboot). Through Docker-on-Mac NAT that count reads false-zero → brick risk, so
  Docker is out for the push.
- Confirmed the unmodified tool errors on a macOS socket (`TIOCOUTQ` → OSError 6).
- Confirmed macOS `SO_NWRITE` (const 0x1024) tracks delivery identically: 65536→0
  only after the peer ACKs. So the patch is a faithful one-function swap.
- Because the device already reaches the Mac at 192.168.10.209 directly, the HTTP
  server runs natively on the Mac — no VM, no bridging onto corporate guest WiFi.
- The tool's `lan_ip_towards()` will embed `http://192.168.10.209:8070/...` in the
  down message, which the device can reach (same path the broker uses).

Rejected: bridged VM (adds the guest-WiFi bridging gamble for no safety gain now
that the patch is validated) and Route B (unneeded).

### New required input / open risk: the OfficeGuest WiFi credentials

ESPHome bakes WiFi creds into `secrets.yaml` and must rejoin a network **at the
device's physical location** (the office). For the monitor to come back on
OfficeGuest after the flash, we need that network's PSK. If OfficeGuest is a
captive-portal / credential network rather than a simple WPA2-PSK, ESPHome can
associate but may not get usable LAN/API access — in which case fall back to the
firmware's built-in `cgdn1 Fallback` AP + captive portal to set WiFi, or flash
against a network we control and keep the device in its range. Confirm with owner.

## Follow-up (explicitly out of scope here)

Once stock ESPHome is confirmed running: decide and implement display
customization (the repo supports custom screen pages, LED color thresholds, and
tap-answerable MQTT screen messages). New project, back through brainstorming.
