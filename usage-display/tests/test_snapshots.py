import json
import os
import subprocess
import sys
from pathlib import Path

from usage_display.snapshots import claude_snapshot, codex_snapshot, write_json_atomic

ROOT = Path(__file__).resolve().parent.parent
NOW = 1793584000.0

STATUSLINE = {
    "model": {"display_name": "Opus"},
    "workspace": {"current_dir": "/tmp"},
    "rate_limits": {"five_hour": {"used_percentage": 32.4}, "seven_day": {"used_percentage": 18.0}},
}


def token_count(primary, secondary):
    return {"type": "token_count", "rate_limits": {"primary": primary, "secondary": secondary}}


def test_claude_snapshot():
    assert claude_snapshot(STATUSLINE, NOW) == {"five_hour": 32.4, "seven_day": 18.0, "account": "", "updated_at": NOW}


def test_claude_snapshot_without_limits():
    assert claude_snapshot({"model": {"display_name": "Opus"}}, NOW) is None
    assert claude_snapshot({"rate_limits": {"five_hour": {"used_percentage": "x"}, "seven_day": {}}}, NOW) is None
    nan = {"rate_limits": {"five_hour": {"used_percentage": float("nan")}, "seven_day": {"used_percentage": 1}}}
    assert claude_snapshot(nan, NOW) is None


def test_codex_snapshot_by_window():
    five = {"used_percent": 41.0, "window_minutes": 300}
    week = {"used_percent": 9.0, "window_minutes": 10080}
    for tc in (token_count(five, week), token_count(week, five)):  # either order
        snap = codex_snapshot(tc, None, NOW)
        assert (snap["five_hour"], snap["seven_day"]) == (41.0, 9.0)
    assert codex_snapshot(token_count(five, None), None, NOW) is None  # weekly window missing
    assert codex_snapshot(None, None, NOW) is None


def test_codex_account():
    tc = token_count({"used_percent": 1, "window_minutes": 300}, {"used_percent": 2, "window_minutes": 10080})
    assert codex_snapshot(tc, None, NOW)["account"] == "default"
    assert codex_snapshot(tc, str(Path.home() / ".codex"), NOW)["account"] == "default"
    assert codex_snapshot(tc, str(Path.home() / ".codex-daybreak"), NOW)["account"] == "daybreak"
    assert codex_snapshot(tc, str(Path.home() / ".codex-daybreak") + "/", NOW)["account"] == "daybreak"


def test_write_json_atomic(tmp_path):
    target = tmp_path / "sub" / "snap.json"
    write_json_atomic(target, {"five_hour": 1.5})
    assert json.loads(target.read_text()) == {"five_hour": 1.5}
    write_json_atomic(target, {"five_hour": 2.5})
    assert json.loads(target.read_text()) == {"five_hour": 2.5}
    assert sorted(p.name for p in target.parent.iterdir()) == ["snap.json"]  # no temp files left


def run_hook(home, stdin):
    env = {**os.environ, "HOME": str(home), "PYTHONPATH": str(ROOT)}
    return subprocess.run([sys.executable, str(ROOT / "claude_statusline_hook.py")], input=stdin, env=env,
                          capture_output=True, text=True, timeout=10)


def test_statusline_hook_writes_and_is_silent(tmp_path):
    res = run_hook(tmp_path, json.dumps(STATUSLINE))
    assert (res.returncode, res.stdout, res.stderr) == (0, "", "")
    snap = json.loads((tmp_path / ".claude" / "usage-snapshot.json").read_text())
    assert (snap["five_hour"], snap["seven_day"]) == (32.4, 18.0)

    other = tmp_path / "other"
    other.mkdir()
    res = run_hook(other, "{not json")
    assert (res.returncode, res.stdout, res.stderr) == (0, "", "")
    assert not (other / ".claude" / "usage-snapshot.json").exists()
