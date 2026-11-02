#!/bin/bash
# Move the monitor off an IP shared with another device (seen: a Ricoh printer on 192.168.10.200).
# Waits until the other device answers at the address (so it's awake), then restarts the monitor as
# soon as it's reachable: its DHCP ARP check (CONFIG_LWIP_DHCP_DOES_ARP_CHECK) then finds the offered
# address taken, declines it and gets another. Checks the result via cgdn1.local.
#   move-off-conflict.sh [ip] [hours]
HERE="$(cd "$(dirname "$0")" && pwd)"
IP="${1:-192.168.10.200}"; HOURS="${2:-3}"
MONITOR_MAC="cc:b5:d1:31:d2:78"
KEY="$(awk -F'"' '/^api_key:/{print $2}' "$HERE/esphome-secrets.yaml")"
end=$(( $(date +%s) + HOURS * 3600 )); seen=0; restarts=0; last_restart=0

monitor_ip() {  # fresh mDNS lookup (dns-sd doesn't use the resolver cache)
  dns-sd -G v4 cgdn1.local > /tmp/.cgdn1-dnssd.$$ 2>/dev/null & local p=$!
  sleep 4; kill $p 2>/dev/null
  awk '/cgdn1.local/{for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i}' \
    /tmp/.cgdn1-dnssd.$$ | tail -1; rm -f /tmp/.cgdn1-dnssd.$$
}

echo "$(date +%T) watching $IP (monitor = $MONITOR_MAC)"
while [ "$(date +%s)" -lt $end ] && [ $restarts -lt 5 ]; do
  ping -c1 -t1 "$IP" >/dev/null 2>&1
  mac=$(arp -n "$IP" 2>/dev/null | awk '{print $4}')
  now=$(date +%s)
  if [ -n "$mac" ] && [ "$mac" != "$MONITOR_MAC" ] && [ "$mac" != "(incomplete)" ]; then
    [ $(( now - seen )) -gt 30 ] && echo "$(date +%T) other device at $IP: MAC $mac  <- for IT"
    seen=$now
  elif [ "$mac" = "$MONITOR_MAC" ] && [ $(( now - seen )) -lt 60 ] && [ $(( now - last_restart )) -gt 60 ]; then
    if "$HERE/venv/bin/python" "$HERE/press_button.py" "$KEY" "Restart" >/dev/null 2>&1; then
      restarts=$((restarts + 1)); last_restart=$now
      echo "$(date +%T) other device seen $(( now - seen ))s ago: restarted the monitor (#$restarts)"
      sleep 30
      new=$(monitor_ip)
      echo "$(date +%T) cgdn1.local is now ${new:-?}"
      if [ -n "$new" ] && [ "$new" != "$IP" ]; then
        echo "=== moved: monitor is at $new ==="; exit 0
      fi
    fi
  fi
  sleep 1
done
echo "=== not moved (restarts: $restarts) ==="
