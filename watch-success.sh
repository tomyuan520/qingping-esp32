#!/bin/bash
# Wait until the MONITOR (not some other client) has acknowledged the whole image, then clear the
# queued download command so a later boot into stock can't flash again.
#   watch-success.sh [push-log] [monitor-ip] [hours]
LOG="${1:-$HOME/qingping-flash/push-permanent2.log}"; IP="${2:-192.168.10.200}"; HOURS="${3:-12}"
PW="$(cat "$HOME/qingping-flash/broker.pw")"; end=$(( $(date +%s) + HOURS * 3600 ))
done_by_monitor() {
  awk -v ip="$IP" '/ downloading /{who=$3} /acknowledged all/{if (who==ip) found=1} END{exit !found}' "$LOG"
}
until done_by_monitor || [ "$(date +%s)" -gt $end ]; do sleep 15; done
if done_by_monitor; then
  echo "=== $(date +%T) SUCCESS: $IP acknowledged the full image ==="
  grep -E "downloading|acknowledged all" "$LOG" | tail -2
  docker exec qingping-mosquitto mosquitto_pub -h localhost -u qingping -P "$PW" -t qingping/CCB5D131D278/down -r -n && echo "download command cleared"
else
  echo "=== no completed download by $IP within $HOURS h ==="
fi
