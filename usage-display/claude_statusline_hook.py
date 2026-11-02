#!/usr/bin/env python3
"""Claude Code status-line side effect: save the 5h / 7d used percentages for the CGDN1 usage pages.

The status-line command pipes Claude Code's JSON here in the background. This must never print,
fail or slow the status line, so every error is swallowed.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main():
    try:
        from usage_display.snapshots import CLAUDE_SNAPSHOT, claude_snapshot, write_json_atomic

        snap = claude_snapshot(json.loads(sys.stdin.read()), time.time())
        if snap is not None:
            write_json_atomic(CLAUDE_SNAPSHOT, snap)
    except Exception:
        pass


if __name__ == "__main__":
    main()
