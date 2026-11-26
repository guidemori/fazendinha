import json
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
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

    def test_midnight_in_brasilia_uses_server_clock(self):
        self.assertEqual(self.store.visit(self.token)["visited"], 1)
        self.assertEqual(self.store.visit(self.token)["visited"], 1)
        self.now += timedelta(minutes=1)
        self.assertEqual(self.store.visit(self.token)["visited"], 2)
        self.now -= timedelta(days=1)
        self.assertEqual(self.store.visit(self.token)["visited"], 2)
        self.assertEqual(self.store.visit("B" * 43)["visited"], 1)

    def test_claim_is_durable_and_idempotent_under_concurrency(self):
        self.store.visit(self.token)
        with self.assertRaises(ClaimUnavailable):
            self.store.claim(self.token, 2)
        with ThreadPoolExecutor(max_workers=8) as pool:
            responses = list(pool.map(lambda _: self.store.claim(self.token, 1), range(12)))
        self.assertTrue(all(response["claimed"] == 1 for response in responses))
        reopened = VisitStore(self.path, lambda: self.now)
        self.assertEqual(reopened.visit(self.token)["claimed"], 1)
        self.assertEqual(reopened.claim(self.token, 1)["rewards"][0],
                         {"coins": 12, "seeds": 1})

    def test_http_requires_key_and_does_not_accept_client_timestamp(self):
        with ThreadingHTTPServer(
            ("127.0.0.1", 0), handler_for(self.store, None)
        ) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = f"http://127.0.0.1:{server.server_port}/v1/"

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
                self.assertEqual(request("visits")["visited"], 1)
                self.assertEqual(request("claims", b'{"day":1}')["claimed"], 1)
                self.assertEqual(request("claims", b'{"day":1}')["claimed"], 1)
            finally:
                server.shutdown()
                worker.join()
