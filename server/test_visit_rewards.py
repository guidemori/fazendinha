import hashlib
import json
import sqlite3
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from datetime import datetime, timedelta, timezone
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server.visit_rewards import ClaimUnavailable, VisitStore, handler_for


class VisitRewardsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "visits.sqlite3"
        self.now = datetime(2026, 1, 2, 2, 59, tzinfo=timezone.utc)
        self.store = VisitStore(self.path, lambda: self.now)
        self.token = "A" * 43

    def test_midnight_in_brasilia_and_missed_date(self):
        self.assertEqual(self.store.visit(self.token)["streak"], 1)
        self.assertEqual(self.store.visit(self.token)["streak"], 1)
        self.now += timedelta(minutes=1)
        self.assertEqual(self.store.visit(self.token)["streak"], 2)
        self.now += timedelta(days=2)
        reset = self.store.visit(self.token)
        self.assertEqual(reset["streak"], 1)
        self.assertEqual(reset["rewardDay"], 1)
        self.now -= timedelta(days=1)
        self.assertFalse(self.store.visit(self.token)["claimable"])

    def test_seventh_day_and_next_reward_cycle(self):
        for day in range(1, 9):
            snapshot = self.store.visit(self.token)
            self.assertEqual(snapshot["streak"], day)
            self.assertEqual(snapshot["rewardDay"], (day - 1) % 7 + 1)
            self.now += timedelta(days=1)

    def test_claim_is_durable_and_idempotent_under_concurrency(self):
        date = self.store.visit(self.token)["date"]
        with self.assertRaises(ClaimUnavailable):
            self.store.claim(self.token, "2099-01-01")
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: self.store.claim(self.token, date), range(12)))
        self.assertTrue(all(result["coinsPaid"] == 12 for result in results))
        reopened = VisitStore(self.path, lambda: self.now)
        self.assertTrue(reopened.visit(self.token)["claimedToday"])
        self.assertEqual(reopened.claim(self.token, date)["seedsPaid"], 1)

    def test_migration_preserves_previous_claims(self):
        installation = hashlib.sha256(self.token.encode("ascii")).hexdigest()
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TABLE visits (installation TEXT, event TEXT, claimed INTEGER)")
            db.execute("INSERT INTO visits VALUES (?, 'daily-visits-v1', 2)", (installation,))
        snapshot = self.store.visit(self.token)
        self.assertEqual(snapshot["coinsPaid"], 36)
        self.assertEqual(snapshot["streak"], 1)
        self.assertEqual(self.store.claim(self.token, snapshot["date"])["coinsPaid"], 48)

    def test_http_requires_key_and_does_not_accept_client_timestamp(self):
        with ThreadingHTTPServer(
            ("127.0.0.1", 0), handler_for(self.store, None)
        ) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = f"http://127.0.0.1:{server.server_port}/v2/"

            def request(path, data=b"", authorized=True):
                headers = {"Authorization": f"Bearer {self.token}"} if authorized else {}
                with urlopen(Request(base + path, data=data, headers=headers)) as response:
                    return json.load(response)

            try:
                with self.assertRaises(HTTPError) as unauthorized:
                    request("visits", authorized=False)
                self.assertEqual(unauthorized.exception.code, 401)
                with self.assertRaises(HTTPError) as invalid:
                    request("visits", b'{"date":"2099-12-31"}')
                self.assertEqual(invalid.exception.code, 400)
                snapshot = request("visits")
                payload = json.dumps({"date": snapshot["date"]}).encode()
                self.assertEqual(snapshot["streak"], 1)
                self.assertEqual(request("claims", payload)["coinsPaid"], 12)
                self.assertEqual(request("claims", payload)["coinsPaid"], 12)
            finally:
                server.shutdown()
                worker.join()
