"""Serviço de visitas de sete dias do Little Farm."""
import argparse
import hashlib
import json
import re
import sqlite3
from contextlib import closing
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

EVENT = "daily-visits-v1"
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
                CREATE TABLE IF NOT EXISTS visits (
                    installation TEXT NOT NULL,
                    event TEXT NOT NULL,
                    last_day TEXT,
                    visited INTEGER NOT NULL DEFAULT 0,
                    claimed INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (installation, event)
                )
            """)

    def visit(self, token):
        return self._update(token, None)

    def claim(self, token, day):
        if type(day) is not int or not 1 <= day <= len(REWARDS):
            raise ClaimUnavailable
        return self._update(token, day)

    def _update(self, token, claim):
        installation = hashlib.sha256(token.encode("ascii")).hexdigest()
        with closing(sqlite3.connect(self.path, timeout=5)) as db, db:
            db.execute("BEGIN IMMEDIATE")
            db.execute(
                "INSERT OR IGNORE INTO visits (installation, event) VALUES (?, ?)",
                (installation, EVENT),
            )
            last_day, visited, claimed = db.execute(
                "SELECT last_day, visited, claimed FROM visits "
                "WHERE installation = ? AND event = ?",
                (installation, EVENT),
            ).fetchone()

            today = self.clock().astimezone(EVENT_ZONE).date().isoformat()
            if claim is None:
                if visited < len(REWARDS) and (last_day is None or today > last_day):
                    visited += 1
                    last_day = today
            elif claim > claimed:
                if claim != claimed + 1 or claim > visited:
                    raise ClaimUnavailable
                claimed = claim

            db.execute(
                "UPDATE visits SET last_day = ?, visited = ?, claimed = ? "
                "WHERE installation = ? AND event = ?",
                (last_day, visited, claimed, installation, EVENT),
            )
            return {"event": EVENT, "visited": visited, "claimed": claimed,
                    "rewards": REWARDS}


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
            if self.path in ("/v1/visits", "/v1/claims"):
                self._reply(204)
            else:
                self._reply(404)

        def do_POST(self):
            if self.path not in ("/v1/visits", "/v1/claims"):
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
                if self.path == "/v1/visits":
                    if length:
                        raise ValueError
                    result = store.visit(token)
                else:
                    body = json.loads(self.rfile.read(length))
                    if not isinstance(body, dict):
                        raise ValueError
                    result = store.claim(token, body.get("day"))
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
