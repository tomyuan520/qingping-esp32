import asyncio
import json

from usage_display.agent import build_payloads, due, load_json, new_state, run_once

NOW = 1793584000.0
CLAUDE = {"five_hour": 32.4, "seven_day": 18.0, "account": "", "updated_at": NOW - 60}
CODEX = {"five_hour": 41.0, "seven_day": 9.0, "account": "daybreak", "updated_at": NOW - 540}


def test_build_payloads_skips_missing():
    assert build_payloads(None, CODEX, NOW) == [
        {"service": "codex", "five_hour": 41.0, "seven_day": 9.0, "account": "daybreak", "age_s": 540}]
    assert [p["service"] for p in build_payloads(CLAUDE, None, NOW)] == ["claude"]
    assert [p["service"] for p in build_payloads(CLAUDE, CODEX, NOW)] == ["claude", "codex"]
    assert build_payloads(None, None, NOW) == []


def test_build_payloads_clamps():
    p = build_payloads({**CLAUDE, "five_hour": 120, "seven_day": -3}, None, NOW)[0]
    assert (p["five_hour"], p["seven_day"]) == (100.0, 0.0)
    assert build_payloads({**CLAUDE, "five_hour": "x"}, None, NOW) == []
    assert build_payloads({**CLAUDE, "seven_day": True}, None, NOW) == []
    assert build_payloads({**CODEX, "account": "daybéreak_longer"}, None, NOW)[0]["account"] == "daybreak_lon"
    assert build_payloads({**CODEX, "account": None}, None, NOW)[0]["account"] == ""
    for bad in (float("nan"), float("inf"), float("-inf")):  # json.loads accepts NaN / Infinity
        assert build_payloads({**CLAUDE, "five_hour": bad}, None, NOW) == []


def test_age_from_updated_at():
    assert build_payloads({**CLAUDE, "updated_at": NOW - 540}, None, NOW)[0]["age_s"] == 540
    assert build_payloads({**CLAUDE, "updated_at": NOW + 100}, None, NOW)[0]["age_s"] == 0  # clock skew
    assert build_payloads({**CLAUDE, "updated_at": "later"}, None, NOW) == []
    for bad in (float("nan"), float("inf"), float("-inf")):
        assert build_payloads({**CLAUDE, "updated_at": bad}, None, NOW) == []
    assert build_payloads({**CLAUDE, "updated_at": -1e12}, None, NOW)[0]["age_s"] == 2**31 - 1  # device int32


def test_due_on_change_and_heartbeat():
    payloads = build_payloads(CLAUDE, CODEX, NOW)
    assert due(payloads, {}, 0.0, NOW)  # nothing sent yet
    sent = {"claude": (32.4, 18.0, ""), "codex": (41.0, 9.0, "daybreak")}
    assert not due(payloads, sent, NOW, NOW + 10)
    assert due(build_payloads({**CLAUDE, "five_hour": 33.0}, CODEX, NOW), sent, NOW, NOW + 10)  # value changed
    assert due(build_payloads(CLAUDE, {**CODEX, "account": "default"}, NOW), sent, NOW, NOW + 10)  # account switched
    assert due(payloads, sent, NOW, NOW + 300)  # heartbeat
    assert not due([], sent, NOW, NOW + 3000)  # nothing to send


def test_load_json_bad_file(tmp_path):
    assert load_json(tmp_path / "missing.json") is None
    (tmp_path / "half.json").write_text("{half")
    assert load_json(tmp_path / "half.json") is None
    (tmp_path / "list.json").write_text("[1, 2]")
    assert load_json(tmp_path / "list.json") is None
    (tmp_path / "ok.json").write_text(json.dumps(CLAUDE))
    assert load_json(tmp_path / "ok.json") == CLAUDE


def test_run_once_survives_send_failure(tmp_path):
    claude_path, codex_path = tmp_path / "claude.json", tmp_path / "codex.json"
    claude_path.write_text(json.dumps(CLAUDE))
    calls = []

    async def failing(payloads):
        calls.append(payloads)
        return False

    async def raising(payloads):
        calls.append(payloads)
        raise OSError("cgdn1.local unreachable")

    async def working(payloads):
        calls.append(payloads)
        return True

    state = new_state()
    for sender in (failing, raising):
        asyncio.run(run_once(state, sender, lambda: NOW, claude_path, codex_path))
        assert state["last"] == {} and state["sent_at"] == 0.0  # nothing recorded, retried next time
    asyncio.run(run_once(state, working, lambda: NOW, claude_path, codex_path))
    assert state["last"] == {"claude": (32.4, 18.0, "")} and state["sent_at"] == NOW
    asyncio.run(run_once(state, working, lambda: NOW + 30, claude_path, codex_path))
    assert len(calls) == 3  # unchanged and before the heartbeat: not sent again


def test_run_once_survives_bad_snapshot(tmp_path, monkeypatch):
    import usage_display.agent as agent

    def broken(*args):
        raise ValueError("bad snapshot")

    monkeypatch.setattr(agent, "build_payloads", broken)
    state = new_state()
    asyncio.run(run_once(state, None, lambda: NOW, tmp_path / "a.json", tmp_path / "b.json"))  # must not raise
    assert state["last"] == {}
