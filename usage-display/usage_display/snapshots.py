"""Usage snapshots for the CGDN1 usage pages: the 5-hour and weekly used percentages of Claude and
Codex, written by the Claude status line and the Codex Stop hook, read by the agent. Numbers and an
account label only; nothing here touches credentials.
"""
from __future__ import annotations

import json
import math
import os
import tempfile
from pathlib import Path

CLAUDE_SNAPSHOT = Path.home() / ".claude" / "usage-snapshot.json"
CODEX_SNAPSHOT = Path.home() / ".codex" / "usage-display.json"

FIVE_HOUR_MINUTES = 300
SEVEN_DAY_MINUTES = 10080


def number(value) -> float | None:
    """A finite int/float as float, else None (bools, strings, NaN and infinities are not numbers here)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    return float(value)


def _snapshot(five_hour, seven_day, account: str, now: float) -> dict | None:
    if five_hour is None or seven_day is None:
        return None
    return {"five_hour": five_hour, "seven_day": seven_day, "account": account, "updated_at": now}


def claude_snapshot(statusline: dict, now: float) -> dict | None:
    """From the JSON Claude Code pipes to the status-line command (rate_limits.*.used_percentage)."""
    limits = (statusline or {}).get("rate_limits") or {}
    return _snapshot(number((limits.get("five_hour") or {}).get("used_percentage")),
                     number((limits.get("seven_day") or {}).get("used_percentage")), "", now)


def codex_account(codex_home: str | None) -> str:
    """~/.codex (or CODEX_HOME unset) -> "default"; ~/.codex-<name> -> "<name>"."""
    name = Path(codex_home).name if codex_home else ".codex"
    return name[len(".codex-"):] if name.startswith(".codex-") and len(name) > len(".codex-") else "default"


def codex_snapshot(token_count: dict, codex_home: str | None, now: float) -> dict | None:
    """From a Codex session's latest token_count event; windows matched by length, not by key order."""
    limits = (token_count or {}).get("rate_limits") or {}
    by_window = {}
    for key in ("primary", "secondary"):
        limit = limits.get(key) or {}
        used = number(limit.get("used_percent"))
        if used is not None:
            by_window[limit.get("window_minutes")] = used
    return _snapshot(by_window.get(FIVE_HOUR_MINUTES), by_window.get(SEVEN_DAY_MINUTES), codex_account(codex_home), now)


def write_json_atomic(path: Path, obj: dict) -> None:
    """Write via a temp file in the same directory + rename, so readers never see half a file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
