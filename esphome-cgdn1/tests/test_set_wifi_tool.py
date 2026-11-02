"""Tests for tools/cgdn1_set_wifi.py (the Mac side of the set_wifi / forget_wifi API actions)."""
import pytest

import cgdn1_set_wifi as tool


def test_check_matches_firmware_rules():
    assert tool.check("Home", "password1") is None
    assert tool.check("Home", "") is None
    assert tool.check("Home", "0123456789abcdef" * 4) is None
    assert tool.check("", "password1") == "network name must be 1-32 bytes"
    assert tool.check("s" * 33, "password1") == "network name must be 1-32 bytes"
    assert tool.check("café", "password1") is None  # 5 bytes UTF-8
    assert tool.check("Ho\x01me", "password1") == "network name has control characters"
    assert tool.check("Home", "1234567") == "password must be empty (open network), 8-63 characters or 64 hex digits"
    assert tool.check("Home", "p" * 64) == "password must be empty (open network), 8-63 characters or 64 hex digits"
    assert tool.check("Home", "pässwort") == "password must be printable ASCII"


def test_read_api_key(tmp_path):
    p = tmp_path / "s.yaml"
    p.write_text('wifi_ssid: "x"\napi_key: "abc+/="\n')
    assert tool.read_api_key(p) == "abc+/="
    p.write_text("wifi_ssid: x\n")
    with pytest.raises(SystemExit):
        tool.read_api_key(p)


def test_no_password_on_the_command_line():
    parser = tool.parser()
    with pytest.raises(SystemExit):
        parser.parse_args(["Home", "--password", "secret123"])
    args = parser.parse_args(["Home", "--host", "192.168.4.1"])
    assert (args.ssid, args.host, args.forget) == ("Home", "192.168.4.1", False)
    args = parser.parse_args(["--forget"])
    assert args.forget and args.ssid is None and args.host == "cgdn1.local"


def test_ask_password_confirms_and_validates(monkeypatch):
    answers = iter(["password1", "password1"])
    monkeypatch.setattr(tool.getpass, "getpass", lambda prompt="": next(answers))
    assert tool.ask_password("Home") == "password1"

    answers = iter(["password1", "different1", "password2", "password2"])
    monkeypatch.setattr(tool.getpass, "getpass", lambda prompt="": next(answers))
    assert tool.ask_password("Home") == "password2"  # mismatch -> asked again

    answers = iter(["short", "password3", "password3"])
    monkeypatch.setattr(tool.getpass, "getpass", lambda prompt="": next(answers))
    assert tool.ask_password("Home") == "password3"  # invalid -> asked again
