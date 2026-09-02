#!/usr/bin/env python3
"""Focused tests for collector input and match parsing."""

from __future__ import annotations

import importlib.util
import tempfile
from importlib.machinery import SourceFileLoader
import unittest
from pathlib import Path
from unittest.mock import patch


COLLECT = Path(__file__).resolve().parent.parent / "bin" / "collect"
LOADER = SourceFileLoader("collect", str(COLLECT))
SPEC = importlib.util.spec_from_loader("collect", LOADER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load collector")
collect = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collect)


class CollectorTest(unittest.TestCase):
    def test_account_id_must_be_decimal(self):
        self.assertEqual(collect.valid_account_id("83730627"), "83730627")
        self.assertIsNone(collect.valid_account_id("83730627/../heroes"))
        self.assertIsNone(collect.valid_account_id("1e8"))
        self.assertIsNone(collect.valid_account_id("１２３"))
        self.assertEqual(collect.resolve_account_id("83730627/../heroes"), "")

    def test_match_modes_are_classified_once(self):
        self.assertEqual(collect.match_mode({"game_mode": 23, "lobby_type": 8}), "turbo")
        self.assertEqual(collect.match_mode({"game_mode": 1, "lobby_type": 8}), "ranked")
        self.assertEqual(collect.match_mode({"game_mode": 1, "lobby_type": 0}), "unranked")

    def test_rollup_uses_safe_match_parsing(self):
        matches = [
            {"game_mode": 23, "player_slot": 0, "radiant_win": True, "kills": "4", "deaths": 0, "assists": 6},
            {"game_mode": 23, "player_slot": 128, "radiant_win": True, "kills": "bad", "deaths": 2, "assists": 3},
        ]
        rollup = collect.bucket_matches(matches)["turbo"]
        self.assertEqual(rollup["games"], 2)
        self.assertEqual(rollup["win"], 1)
        self.assertEqual(rollup["lose"], 1)
        self.assertEqual(rollup["kda"], 6.5)

    def test_recent_matches_ignore_invalid_results(self):
        matches = [
            {"game_mode": 23, "player_slot": 0, "radiant_win": True, "hero_id": 14},
            {"game_mode": 23, "player_slot": "bad", "radiant_win": True, "hero_id": 15},
        ]
        recent = collect.recent_for_mode(matches, {"14": "Pudge"}, "turbo")
        self.assertEqual(len(recent), 1)
        self.assertEqual(recent[0]["heroName"], "Pudge")

    def test_oversized_response_is_rejected(self):
        class Response:
            headers = {}

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, size):
                return b"x" * size

        class Opener:
            def open(self, request, timeout):
                return Response()

        with patch.object(collect.urllib.request, "build_opener", return_value=Opener()):
            self.assertIsNone(collect.http_get_json("https://api.opendota.com/api/heroes"))

    def test_external_redirect_is_rejected(self):
        handler = collect.OpenDotaRedirectHandler()
        with self.assertRaises(collect.urllib.error.URLError):
            handler.redirect_request(None, None, 302, "Found", {}, "https://example.com/data")

    def test_oversized_cache_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.json"
            path.write_bytes(b"x" * (collect.MAX_CACHE_BYTES + 1))
            self.assertIsNone(collect.load_cached(path))

    def test_cache_ttl_requires_matching_account(self):
        now_ms = 1_000_000
        cached = {"accountId": "42", "__fetchedAtMs": now_ms}
        self.assertTrue(collect.cache_is_fresh(cached, "42", now_ms))
        self.assertFalse(collect.cache_is_fresh(cached, "43", now_ms))
        self.assertFalse(collect.cache_is_fresh(cached, "42", now_ms + collect.AUTO_REFRESH_TTL_SEC * 1000))


if __name__ == "__main__":
    unittest.main()
