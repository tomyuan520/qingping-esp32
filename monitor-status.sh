#!/bin/bash
# Show the stock CGDN1's state from the broker on this computer: connection, clock (fresh boot?),
# WiFi signal, and a live battery reading (asks for one realtime report, documented type 12).
#   ~/qingping-flash/monitor-status.sh            (office monitor)
#   MAC=AABBCCDDEEFF ~/qingping-flash/monitor-status.sh

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MAC="${MAC:-CCB5D131D278}"
SUB="$HERE/mosquitto/data/sub.log"
PW="$(cat "$HERE/broker.pw")"

echo "== broker connection (latest events)"
docker logs qingping-mosquitto 2>&1 | grep -iE "as qingping-$MAC|qingping-$MAC .* disconnect" | tail -2 |
  while read -r l; do echo "   $(date -r "${l%%:*}" +%T 2>/dev/null || date -d "@${l%%:*}" +%T) $(echo "$l" | grep -oiE 'New client connected|disconnected[^.]*')"; done

[ -f "$SUB" ] || { echo "No $SUB: start the payload logger (see HOWTO-flash-cgdn1.md, step 1)"; exit 1; }
size=$(wc -c < "$SUB")
docker exec qingping-mosquitto mosquitto_pub -h localhost -u qingping -P "$PW" \
  -t "qingping/$MAC/down" -m '{"type": "12", "up_itvl": "10", "duration": "60"}'
end=$(( $(date +%s) + 30 ))
until tail -c +$((size + 1)) "$SUB" | grep -q '{"type":"12"' || [ "$(date +%s)" -gt $end ]; do sleep 2; done

python3 -I - "$SUB" "$size" <<'EOF'
import sys, re, json
log, size = sys.argv[1], int(sys.argv[2])
s = open(log, encoding="utf-8", errors="replace").read()
hello = re.findall(r'(\S+) \| qingping/\S+/up \| len=\d+ \| \{[^}]*?"type":\s*"13"[^}]*?"wifi_info":\s*"([^"]+)"[^}]*?"timestamp":\s*(\d+)', s, re.S)
if hello:
    t, wifi, clock = hello[-1]
    kind = "seconds since boot (fresh boot, clock not set)" if int(clock) < 86400 else "real time (no reboot since it was set)"
    print(f"== last hello {t[11:19]} UTC: WiFi {wifi.split(',')[1]} dBm, clock {clock} = {kind}")
new = s.encode()[size:].decode("utf-8", "replace")
rt = re.findall(r'(\S+) \| qingping/\S+/up \| len=\d+ \| (\{"type":"12".*)', new)
if rt:
    d = json.loads(rt[0][1])["sensorData"][0]
    vals = {k: v.get("value") for k, v in d.items() if isinstance(v, dict) and k != "timestamp"}
    off = [k for k, v in d.items() if isinstance(v, dict) and v.get("status")]
    print(f"== live report {rt[0][0][11:19]} UTC: {vals}" + (f" (off: {', '.join(off)})" if off else ""))
else:
    print("== no live report within 30 s (monitor offline right now?)")
EOF
