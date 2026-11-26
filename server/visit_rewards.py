"""Serviço de login diário do Little Farm."""
import argparse
import hashlib
import json
import re
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

EVENT = "daily-login-v2"
EVENT_ZONE = ZoneInfo("America/Sao_Paulo")
REWARDS = tuple({"coins": day * 12, "seeds": day} for day in range(1, 8))
TOKEN = re.compile(r"[A-Za-z0-9_-]{43}")


class ClaimUnavailable(Exception):
    pass


class VisitStore:
    def __init__(self, path, clock=None):
        self.path = path
        self.clock = clock or (lambda: datetime.now(EVENT_ZONE))
        with closing(sqlite3.connect(path)) as db, db:
            db.execute("""
                CREATE TABLE IF NOT EXISTS daily_logins (
                    installation TEXT PRIMARY KEY,
                    last_day TEXT,
                    streak INTEGER NOT NULL DEFAULT 0,
                    last_claim_day TEXT,
                    coins_paid INTEGER NOT NULL DEFAULT 0,
                    seeds_paid INTEGER NOT NULL DEFAULT 0
                )
            """)

    def visit(self, token):
        return self._update(token, None)

    def claim(self, token, day):
        if not isinstance(day, str):
            raise ClaimUnavailable
        return self._update(token, day)

    def _update(self, token, claim_day):
        installation = hashlib.sha256(token.encode("ascii")).hexdigest()
        with closing(sqlite3.connect(self.path, timeout=5)) as db, db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT last_day, streak, last_claim_day, coins_paid, seeds_paid "
                "FROM daily_logins WHERE installation = ?",
                (installation,),
            ).fetchone()
            if row is None:
                legacy_exists = db.execute(
                    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'visits'"
                ).fetchone()
                legacy = db.execute(
                    "SELECT claimed FROM visits WHERE installation = ? "
                    "AND event = 'daily-visits-v1'", (installation,),
                ).fetchone() if legacy_exists else None
                legacy_grants = REWARDS[:legacy[0]] if legacy else ()
                row = (None, 0, None,
                       sum(reward["coins"] for reward in legacy_grants),
                       sum(reward["seeds"] for reward in legacy_grants))
            last_day, streak, last_claim_day, coins_paid, seeds_paid = row
            today = self.clock().astimezone(EVENT_ZONE).date()
            day = today.isoformat()
            yesterday = (today - timedelta(days=1)).isoformat()

            if claim_day is None:
                if last_day is None or day > last_day:
                    streak = streak + 1 if last_day == yesterday else 1
                    last_day = day
            elif claim_day != day or last_day != day:
                raise ClaimUnavailable

            reward_day = (streak - 1) % len(REWARDS) + 1
            if claim_day is not None and last_claim_day != day:
                reward = REWARDS[reward_day - 1]
                coins_paid += reward["coins"]
                seeds_paid += reward["seeds"]
                last_claim_day = day

            db.execute(
                "INSERT INTO daily_logins VALUES (?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(installation) DO UPDATE SET last_day = excluded.last_day, "
                "streak = excluded.streak, last_claim_day = excluded.last_claim_day, "
                "coins_paid = excluded.coins_paid, seeds_paid = excluded.seeds_paid",
                (installation, last_day, streak, last_claim_day, coins_paid, seeds_paid),
            )
            return {
                "event": EVENT,
                "date": day,
                "streak": streak,
                "rewardDay": reward_day,
                "claimable": last_day == day and last_claim_day != day,
                "claimedToday": last_claim_day == day,
                "coinsPaid": coins_paid,
                "seedsPaid": seeds_paid,
                "rewards": REWARDS,
            }


def handler_for(store, web_origin):
    class Handler(BaseHTTPRequestHandler):
        def _reply(self, status, body=None):
            self.send_response(status)
            self.send_header("Cache-Control", "no-store")
            origin = self.headers.get("Origin")
            self.send_header("Vary", "Origin")
            if origin is not None and origin == web_origin:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            payload = b"" if body is None else json.dumps(body).encode("utf-8")
            if body is not None:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if payload:
                self.wfile.write(payload)

        def do_OPTIONS(self):
            if self.path in ("/v2/visits", "/v2/claims"):
                self._reply(204)
            else:
                self._reply(404)

        def do_POST(self):
            if self.path not in ("/v2/visits", "/v2/claims"):
                self._reply(404, {"error": "not_found"})
                return
            auth = self.headers.get("Authorization", "")
            token = auth.removeprefix("Bearer ")
            if not auth.startswith("Bearer ") or not TOKEN.fullmatch(token):
                self._reply(401, {"error": "installation_required"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length < 0 or length > 256:
                    raise ValueError
                if self.path == "/v2/visits":
                    if length:
                        raise ValueError
                    result = store.visit(token)
                else:
                    body = json.loads(self.rfile.read(length))
                    if not isinstance(body, dict):
                        raise ValueError
                    result = store.claim(token, body.get("date"))
            except ClaimUnavailable:
                self._reply(409, {"error": "reward_unavailable"})
            except ValueError:
                self._reply(400, {"error": "invalid_request"})
            except sqlite3.Error:
                self._reply(503, {"error": "temporarily_unavailable"})
            else:
                self._reply(200, result)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--db", default="visits.sqlite3")
    parser.add_argument("--web-origin")
    args = parser.parse_args()
    with ThreadingHTTPServer(
        (args.host, args.port),
        handler_for(VisitStore(args.db), args.web_origin),
    ) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
