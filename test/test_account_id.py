#!/usr/bin/env python3
"""Tests for account id precedence ordering.

Order, highest to lowest:
  1. --account-id CLI flag
  2. OPENDOTA_ACCOUNT_ID env var
  3. ~/.config/omarchy/agents/opendota.json (or $XDG_CONFIG_HOME equivalent)
  4. Local Steam install (userdata/ folder or loginusers.vdf)

Runs `bin/collect --demo` in a subprocess with controlled env vars and a
fake HOME, then parses the emitted JSON for accountId. Demo mode skips
network calls and returns the resolved id synchronously.

Run from the plugin root:
  python3 test/test_account_id.py
Exit 0 on success, non-zero on any precedence failure.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
COLLECT = PLUGIN_ROOT / "bin" / "collect"


def resolve_id(env: dict[str, str], flag: str | None = None) -> str | None:
    cmd = [str(COLLECT), "--demo"]
    if flag is not None:
        cmd += ["--account-id", flag]
    result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
    if result.returncode != 0:
        raise RuntimeError(f"collect failed: {result.stderr}")
    parsed = json.loads(result.stdout)
    return parsed.get("accountId")


class ResolveAccountIdTest(unittest.TestCase):
    def setUp(self):
        self._orig_env = dict(os.environ)
        self.tmp = Path(tempfile.mkdtemp(prefix="opendota-precedence-test-"))

        self.steam_dir = self.tmp / ".steam" / "steam" / "userdata" / "83730627"
        self.steam_dir.mkdir(parents=True, exist_ok=True)
        (self.steam_dir / "config").write_text("{}")

        self.env = dict(self._orig_env)
        self.env["HOME"] = str(self.tmp)
        self.env["XDG_CACHE_HOME"] = str(self.tmp / ".cache")
        self.env.pop("OPENDOTA_ACCOUNT_ID", None)
        self.env.pop("XDG_CONFIG_HOME", None)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_config(self, account_id):
        cfg_dir = self.tmp / ".config" / "omarchy" / "agents"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        (cfg_dir / "opendota.json").write_text(json.dumps({"accountId": account_id}))

    def test_cli_flag_wins_over_everything(self):
        self._write_config("11111")
        self.env["OPENDOTA_ACCOUNT_ID"] = "999"
        self.assertEqual(resolve_id(self.env, flag="42"), "42")

    def test_env_wins_over_config(self):
        self._write_config("11111")
        self.env["OPENDOTA_ACCOUNT_ID"] = "999"
        self.assertEqual(resolve_id(self.env), "999")

    def test_env_wins_over_steam(self):
        self.env["OPENDOTA_ACCOUNT_ID"] = "999"
        self.assertEqual(resolve_id(self.env), "999")

    def test_config_wins_over_steam(self):
        self._write_config("11111")
        self.assertEqual(resolve_id(self.env), "11111")

    def test_steam_fallback_when_nothing_else_set(self):
        self.assertEqual(resolve_id(self.env), "83730627")

    def test_empty_config_falls_through_to_steam(self):
        cfg_dir = self.tmp / ".config" / "omarchy" / "agents"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        (cfg_dir / "opendota.json").write_text("{}")
        self.assertEqual(resolve_id(self.env), "83730627")

    def test_whitespace_cli_arg_is_skipped(self):
        self._write_config("11111")
        self.env["OPENDOTA_ACCOUNT_ID"] = "999"
        self.assertEqual(resolve_id(self.env, flag="   "), "999")

    def test_whitespace_env_is_skipped(self):
        self._write_config("11111")
        self.env["OPENDOTA_ACCOUNT_ID"] = "   "
        self.assertEqual(resolve_id(self.env), "11111")

    def test_steam_userdata_picks_most_recently_used_account(self):
        newer = self.tmp / ".steam" / "steam" / "userdata" / "12345678"
        newer.mkdir(parents=True, exist_ok=True)
        (newer / "config").write_text("{}")
        time.sleep(0.05)
        newer.touch()
        self.assertEqual(resolve_id(self.env), "12345678")


if __name__ == "__main__":
    print("Running account id precedence tests...\n")
    runner = unittest.TextTestRunner(stream=sys.stdout, verbosity=2)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ResolveAccountIdTest)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
