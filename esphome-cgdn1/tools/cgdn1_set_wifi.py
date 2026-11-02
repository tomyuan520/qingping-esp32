#!/usr/bin/env python3
"""Add (or forget) the CGDN1's extra WiFi network over the encrypted ESPHome API.

The firmware keeps its built-in network and tries this one too (the same one the dashboard's
"Add WiFi" section sets); it survives
reboots and reflashes until replaced or forgotten (components/cgdn1_wifi). The password is asked for
at a hidden prompt, never taken from the command line, and is sent only inside the encrypted API.

  # monitor on a network this computer is on:
  venv/bin/python tools/cgdn1_set_wifi.py "Home WiFi"
  # monitor somewhere new: join its "cgdn1 Fallback" hotspot (password: ap_password), then
  venv/bin/python tools/cgdn1_set_wifi.py "Home WiFi" --host 192.168.4.1
  # remove it again (takes effect after a restart; --restart presses Restart for you)
  venv/bin/python tools/cgdn1_set_wifi.py --forget --restart

Needs aioesphomeapi; the API key is read from --secrets (default ~/qingping-flash/esphome-secrets.yaml).
"""
from __future__ import annotations

import argparse
import asyncio
import getpass
import re
import sys
from pathlib import Path

SECRETS = Path.home() / "qingping-flash" / "esphome-secrets.yaml"

SSID_MAX = 32
BAD_SSID_LENGTH = "network name must be 1-32 bytes"
BAD_SSID_CHARS = "network name has control characters"
BAD_PASSWORD_LENGTH = "password must be empty (open network), 8-63 characters or 64 hex digits"
BAD_PASSWORD_CHARS = "password must be printable ASCII"


def check(ssid: str, password: str) -> str | None:
    """Same rules as the firmware (extra_wifi.h check()); None = fine, else the reason."""
    raw = ssid.encode()
    if not 1 <= len(raw) <= SSID_MAX:
        return BAD_SSID_LENGTH
    if any(b < 0x20 or b == 0x7F for b in raw):
        return BAD_SSID_CHARS
    if any(not " " <= c <= "~" for c in password):
        return BAD_PASSWORD_CHARS
    if len(password) == 0 or 8 <= len(password) <= 63:
        return None
    if len(password) == 64 and re.fullmatch(r"[0-9a-fA-F]{64}", password):
        return None
    return BAD_PASSWORD_LENGTH


def read_api_key(path: Path = SECRETS) -> str:
    m = re.search(r'^api_key:\s*"([^"]+)"', Path(path).read_text(), re.M)
    if not m:
        raise SystemExit(f"no api_key in {path}")
    return m.group(1)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Add or forget the CGDN1's extra WiFi network.")
    p.add_argument("ssid", nargs="?", help="network name to add (the password is asked for)")
    p.add_argument("--host", default="cgdn1.local", help="monitor address (192.168.4.1 on its fallback hotspot)")
    p.add_argument("--forget", action="store_true", help="remove the extra network")
    p.add_argument("--restart", action="store_true", help="with --forget: restart the monitor so it takes effect")
    p.add_argument("--secrets", type=Path, default=SECRETS, help="file with api_key")
    return p


def ask_password(ssid: str) -> str:
    while True:
        pw = getpass.getpass(f"Password for '{ssid}' (empty = open network): ")
        problem = check(ssid, pw)
        if problem:
            print(f"  {problem}; try again.", file=sys.stderr)
            continue
        if getpass.getpass("Again: ") != pw:
            print("  They don't match; try again.", file=sys.stderr)
            continue
        return pw


async def call(host: str, key: str, action: str, data: dict, restart: bool = False) -> None:
    from aioesphomeapi import APIClient, ButtonInfo

    client = APIClient(host, 6053, None, noise_psk=key)
    await client.connect(login=True)
    try:
        entities, services = await client.list_entities_services()
        service = next((s for s in services if s.name == action), None)
        if service is None:
            raise SystemExit(f"the monitor's firmware has no {action} action (flash a newer build)")
        await client.execute_service(service, data)
        if restart:
            button = next((e for e in entities if isinstance(e, ButtonInfo) and e.name == "Restart"), None)
            if button is not None:
                await asyncio.sleep(1)  # let the forget be saved first
                client.button_command(button.key)
                await asyncio.sleep(1)
    finally:
        await client.disconnect()


def main(argv: list[str] | None = None) -> None:
    args = parser().parse_args(argv)
    if args.forget == (args.ssid is not None):
        raise SystemExit("give a network name to add, or --forget")
    key = read_api_key(args.secrets)
    if args.forget:
        asyncio.run(call(args.host, key, "forget_wifi", {}, restart=args.restart))
        print("Extra network forgotten" + (", monitor restarting." if args.restart else
                                           "; it leaves the WiFi list after the next restart."))
        return
    problem = check(args.ssid, "")  # name only; the password is checked at the prompt
    if problem:
        raise SystemExit(problem)
    password = ask_password(args.ssid)
    asyncio.run(call(args.host, key, "set_wifi", {"ssid": args.ssid, "password": password}))
    print(f"Sent. The monitor now also tries '{args.ssid}'; check its dashboard row \"Extra WiFi\".")
    if args.host == "192.168.4.1":
        print("It joins that network once it's in reach and then drops the fallback hotspot (give it a minute).")


if __name__ == "__main__":
    main()
