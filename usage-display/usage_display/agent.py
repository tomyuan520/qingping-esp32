"""Send the Claude / Codex usage numbers to the CGDN1 (cgdn1.local) for its usage pages.

Reads the two snapshots (see snapshots.py) every 30 s and, when a number or the Codex account changed
or 5 minutes passed, calls the device's encrypted API action set_usage. Numbers and a short account
label only. When the device can't be reached (Mac off its WiFi, device rebooting) it just tries again
next time. Run: python -m usage_display.agent (launchd: local.qingping.usage-agent.plist).
"""
from __future__ import annotations

import asyncio
import json
import re
import sys
import time
from pathlib import Path

from usage_display.snapshots import CLAUDE_SNAPSHOT, CODEX_SNAPSHOT, number

HOST = "cgdn1.local"
PORT = 6053
POLL_S = 30
HEARTBEAT_S = 300
ACCOUNT_MAX = 12
AGE_MAX_S = 2**31 - 1  # set_usage's age_s is an int32 on the device
SECRETS = Path.home() / "qingping-flash" / "esphome-secrets.yaml"


def log(msg: str) -> None:
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", flush=True)


def load_json(path: Path) -> dict | None:
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _payload(service: str, snap: dict | None, now: float) -> dict | None:
    if not snap:
        return None
    five, week, updated = (number(snap.get(k)) for k in ("five_hour", "seven_day", "updated_at"))
    if five is None or week is None or updated is None:
        return None
    account = snap.get("account")
    account = "".join(c for c in account if " " <= c <= "~")[:ACCOUNT_MAX] if isinstance(account, str) else ""
    return {"service": service, "five_hour": min(max(five, 0.0), 100.0), "seven_day": min(max(week, 0.0), 100.0),
            "account": account, "age_s": min(max(0, int(now - updated)), AGE_MAX_S)}


def build_payloads(claude: dict | None, codex: dict | None, now: float) -> list[dict]:
    return [p for p in (_payload("claude", claude, now), _payload("codex", codex, now)) if p is not None]


def _key(p: dict) -> tuple:
    return (p["five_hour"], p["seven_day"], p["account"])


def due(payloads: list[dict], last: dict, last_sent_at: float, now: float, heartbeat_s: float = HEARTBEAT_S) -> bool:
    if not payloads:
        return False
    changed = any(last.get(p["service"]) != _key(p) for p in payloads)
    return changed or now - last_sent_at >= heartbeat_s


def new_state() -> dict:
    return {"last": {}, "sent_at": 0.0, "failing": False}


def read_api_key(path: Path = SECRETS) -> str:
    m = re.search(r'^api_key:\s*"([^"]+)"', Path(path).read_text(), re.M)
    if not m:
        raise SystemExit(f"no api_key in {path}")
    return m.group(1)


async def send(payloads: list[dict], psk: str, host: str = HOST, port: int = PORT) -> bool:
    from aioesphomeapi import APIClient

    client = APIClient(host, port, None, noise_psk=psk)
    await client.connect(login=True)
    try:
        _, services = await client.list_entities_services()
        service = next((s for s in services if s.name == "set_usage"), None)
        if service is None:
            raise LookupError("device firmware has no set_usage action")
        for p in payloads:
            await client.execute_service(service, p)
        return True
    finally:
        await client.disconnect()


async def run_once(state: dict, sender, now=time.time, claude_path: Path = CLAUDE_SNAPSHOT,
                   codex_path: Path = CODEX_SNAPSHOT) -> None:
    t = now()
    try:
        payloads = build_payloads(load_json(claude_path), load_json(codex_path), t)
    except Exception as e:  # never let one bad snapshot end the loop
        log(f"skipping this poll: {type(e).__name__}: {e}")
        return
    if not due(payloads, state["last"], state["sent_at"], t):
        return
    try:
        ok = await sender(payloads)
        error = ""
    except Exception as e:  # unreachable, refused, timed out: try again next poll
        ok, error = False, f"{type(e).__name__}: {e}"
    if ok:
        state["last"] = {p["service"]: _key(p) for p in payloads}
        state["sent_at"] = t
        if state["failing"]:
            log("device reachable again")
        state["failing"] = False
        log("sent " + ", ".join(f"{p['service']} 5h {p['five_hour']:.0f}% 7d {p['seven_day']:.0f}%"
                                + (f" ({p['account']})" if p["account"] else "") for p in payloads))
    elif not state["failing"]:
        state["failing"] = True
        log(f"cannot reach {HOST} ({error or 'set_usage failed'}); retrying every {POLL_S} s")


async def loop() -> None:
    psk = read_api_key()
    state = new_state()

    async def sender(payloads):
        return await send(payloads, psk)

    log(f"usage agent started: {HOST}, poll {POLL_S} s, heartbeat {HEARTBEAT_S} s")
    while True:
        await run_once(state, sender)
        await asyncio.sleep(POLL_S)


def main() -> None:
    try:
        asyncio.run(loop())
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
