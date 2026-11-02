#!/bin/bash
# Resume the permanent ESPHome flash of the CGDN1 ("Office Air Monitor", Wi-Fi MAC CCB5D131D278).
#
# Run on the Mac while it is on the OfficeGuest WiFi with Docker running, BEFORE plugging the
# monitor back in after it has drained its battery (a fresh boot clears the stuck update screen):
#   ~/qingping-flash/resume-flash.sh
# Then plug the monitor in. It boots its official firmware, connects to the broker on this Mac,
# picks up the waiting update command and downloads the image from this Mac. A failed download is
# harmless (the monitor stays on its official firmware); the command stays queued for its next try.

# Elsewhere (e.g. at home, on Linux) override the defaults, which are the office setup:
#   BROKER_IP=192.168.1.20 ~/qingping-flash/resume-flash.sh
# BROKER_IP must be this computer's address AND the host= in the monitor's portal MQTT config.
# Build the image for that network first (secrets.yaml WiFi), see HOWTO-flash-cgdn1.md.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FW="${FW:-$HERE/esphome-cgdn1/.claude/worktrees/permanent}"
LOG="$HERE/push-resume.log"
BROKER_IP="${BROKER_IP:-192.168.10.209}"   # office: portal config "local-mac"
MAC="${MAC:-CCB5D131D278}"
TOPIC="qingping/$MAC/down"
CMD='{"type": "23", "url": "http://'"$BROKER_IP"':8070/firmware.ota.crc.bin", "ota_type": 1}'
PW="$(cat "$HERE/broker.pw")"

if [ "$(uname)" = Darwin ]; then
  ip="$(ipconfig getifaddr en0 || true)"
else
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
fi
if [ "$ip" != "$BROKER_IP" ]; then
  echo "This computer is on '${ip:-no address}', but the monitor looks for its broker at $BROKER_IP."
  echo "Fix the network (Mac: Wi-Fi > Details > TCP/IP > 'Using DHCP with manual address'), or set"
  echo "BROKER_IP if the monitor's portal config points somewhere else, and run this again."
  exit 1
fi

# Broker: reuse the container, or create it from the config in this folder
if ! docker start qingping-mosquitto >/dev/null 2>&1; then
  docker run -d --name qingping-mosquitto --restart unless-stopped -p 1883:1883 \
    -v "$HERE/mosquitto/config:/mosquitto/config" -v "$HERE/mosquitto/data:/mosquitto/data" \
    eclipse-mosquitto:2 >/dev/null
fi
# Payload logger (mosquitto/data/sub.log): monitor-status.sh and debugging read it
if ! docker exec qingping-mosquitto pgrep mosquitto_sub >/dev/null 2>&1; then
  docker exec -d qingping-mosquitto sh -c "mosquitto_sub -h localhost -u qingping -P '$PW' -t '#' -v \
    -F '%I | %t | len=%l | %p' >> /mosquitto/data/sub.log 2>&1"
fi
pkill -f "tools/cgdn1_ota_push.py" || true
sleep 1

# The venv in this folder is macOS-only; elsewhere use python3 with paho-mqtt installed
PY="$HERE/venv/bin/python"
[ "$(uname)" = Darwin ] && [ -x "$PY" ] || PY=python3
"$PY" -c "import paho.mqtt.client" 2>/dev/null || { echo "Install paho-mqtt for $PY first"; exit 1; }

cd "$FW"
[ -f .esphome/build/cgdn1/build/firmware.ota.bin ] || { echo "No built image in $FW; compile it first"; exit 1; }
nohup "$PY" tools/cgdn1_ota_push.py \
  .esphome/build/cgdn1/build/firmware.ota.bin --append-crc \
  --broker "$BROKER_IP" --mac "$MAC" --pw-file "$HERE/broker.pw" --yes --timeout 21600 \
  > "$LOG" 2>&1 &
sleep 4
grep -q "CRC trailer ok" "$LOG" || { echo "Image server failed to start, see $LOG"; exit 1; }

# Retained, so the monitor gets it whenever it (re)connects
docker exec qingping-mosquitto mosquitto_pub -h localhost -u qingping -P "$PW" -t "$TOPIC" -r -m "$CMD"

echo "Ready. Plug the monitor in now. Progress below (Ctrl-C stops watching; the server keeps running)."
# Success only if the full image went to the monitor, not to a test download from this computer
by_monitor() { awk -v me="$BROKER_IP" '/ downloading /{who=$3} /acknowledged all/{if (who!=me) f=1} END{exit !f}' "$LOG"; }
last=""
until by_monitor; do
  line="$(grep -E "downloading|OTA status|aborted" "$LOG" | tail -1 || true)"
  [ -n "$line" ] && [ "$line" != "$last" ] && { echo "$line"; last="$line"; }
  sleep 5
done

# Done: clear the command so a later boot into the official firmware can't flash again
docker exec qingping-mosquitto mosquitto_pub -h localhost -u qingping -P "$PW" -t "$TOPIC" -r -n
grep "acknowledged all" "$LOG"
echo "Flashed. The monitor reboots into ESPHome; in ~1 min open http://cgdn1.local (login in esphome-secrets.yaml)."
