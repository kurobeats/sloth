#!/usr/bin/env python3
"""Minimal Vikunja API stand-in for UI smoke testing (not part of the app).

Serves the endpoints Sloth uses: /info, /login, /user, /projects, /tasks,
/projects/{id}/views/{view}/tasks, /tasks/{id}, comments, labels.
Run: python3 tool/mock_vikunja.py [port]
"""
import json
import sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TODAY = datetime.now(timezone.utc).replace(hour=17, minute=0, second=0, microsecond=0)
ZERO = "0001-01-01T00:00:00Z"


def iso(days=0, hours=0):
    return (TODAY + timedelta(days=days, hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")


USER = {"id": 1, "username": "joe", "name": "Joe Bloggs", "email": "joe@example.com"}

LABELS = {
    1: {"id": 1, "title": "errand", "hex_color": ""},
    2: {"id": 2, "title": "home", "hex_color": "22a06b"},
}

PROJECTS = [
    {
        "id": 1, "title": "Tasks", "hex_color": "", "is_favorite": False,
        "is_archived": False, "position": 1.0,
        "views": [{"id": 1, "title": "List", "view_kind": "list", "position": 1}],
    },
    {
        "id": 2, "title": "Groceries", "hex_color": "", "is_favorite": True,
        "is_archived": False, "position": 2.0,
        "views": [{"id": 2, "title": "List", "view_kind": "list", "position": 1}],
    },
    {
        "id": 3, "title": "Work", "hex_color": "", "is_favorite": False,
        "is_archived": False, "position": 3.0,
        "views": [{"id": 3, "title": "List", "view_kind": "list", "position": 1}],
    },
]


def task(tid, pid, title, *, done=False, due=None, fav=False, desc=None,
         labels=(), priority=0, repeat=0, reminder=None, assignee=False):
    return {
        "id": tid, "project_id": pid, "title": title, "description": desc or "",
        "done": done, "done_at": iso(-1) if done else ZERO,
        "due_date": due or ZERO, "start_date": ZERO, "end_date": ZERO,
        "priority": priority, "is_favorite": fav, "percent_done": 1 if done else 0,
        "repeat_after": repeat, "repeat_mode": 0, "hex_color": "",
        "identifier": f"#{pid}-{tid}", "created": iso(-14), "updated": iso(-1),
        "position": float(tid), "comment_count": 1 if tid == 1 else 0,
        "labels": [LABELS[i] for i in labels],
        "assignees": [USER] if assignee else [],
        "reminders": [{"reminder": reminder}] if reminder else [],
    }


TASKS = [
    task(1, 1, "Book dentist appointment", due=iso(-2), fav=True, desc="Ask about the crown",
         labels=[1], priority=3, reminder=iso(0, -3)),
    task(2, 1, "Reply to Priya about the invoice", due=iso(0, -6), fav=True, desc="Attach the PDF"),
    task(3, 1, "Draft Q4 planning doc", due=iso(1), labels=[2], priority=2, repeat=604800),
    task(4, 2, "Milk", due=iso(0), labels=[1]),
    task(5, 2, "Sourdough starter", due=iso(2)),
    task(6, 3, "Stand-up notes", assignee=True),
    task(7, 3, "Fix login redirect", done=True, desc="Done last week"),
    task(8, 3, "Review PR #412", done=True),
    task(9, 1, "Water the plants", fav=True, repeat=86400),
    task(10, 2, "Coffee beans", due=iso(3), labels=[1, 2]),
]

COMMENTS = {1: [{"id": 1, "comment": "Rang them, next slot is Tuesday.",
                  "author": USER, "created": iso(-1)}]}

USERS = [
    USER,
    {"id": 2, "username": "priya", "name": "Priya Raman", "email": "priya@example.com"},
    {"id": 3, "username": "sam", "name": "Sam Okafor", "email": "sam@example.com"},
]

TEAMS = [
    {"id": 1, "name": "Household", "description": "Shared chores",
     "is_public": False, "external_id": "", "created": iso(-30), "updated": iso(-2),
     "members": [dict(USER, admin=True), dict(USERS[1], admin=False)]},
]

PROJECT_TEAMS = {1: [{"id": 1, "name": "Household", "description": "Shared chores",
                      "permission": 1, "members": TEAMS[0]["members"]}]}
PROJECT_USERS = {1: [dict(USERS[2], permission=0)]}
LINK_SHARES = {1: [{"id": 1, "hash": "abc123def456", "name": "Family link",
                    "permission": 0, "password": ""}]}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def _json(self, payload, status=200):
        raw = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _authed(self):
        token = (self.headers.get("Authorization") or "").replace("Bearer ", "")
        if token != "mock-token":
            self._json({"code": 11, "message": "missing, malformed or invalid token"}, 401)
            return False
        return True

    def do_GET(self):
        url = urlparse(self.path)
        path, q = url.path, parse_qs(url.query)
        if path == "/api/v1/info":
            return self._json({
                "version": "v2.7.1", "max_items_per_page": 50,
                "frontend_url": "http://mock/", "task_attachments_enabled": True,
                "auth": {"local": {"enabled": True, "registration_enabled": False}},
            })
        if not self._authed():
            return
        if path == "/api/v1/user":
            return self._json(USER)
        if path == "/api/v1/projects":
            return self._json(PROJECTS)
        if path == "/api/v1/labels":
            return self._json(list(LABELS.values()))
        if path == "/api/v1/tasks":
            if "s" in q:
                needle = q["s"][0].lower()
                return self._json([t for t in TASKS if needle in t["title"].lower()])
            return self._json(TASKS)
        if path.startswith("/api/v1/projects/") and path.endswith("/tasks"):
            pid = int(path.split("/")[4])
            return self._json([t for t in TASKS if t["project_id"] == pid])
        if path == "/api/v1/teams":
            return self._json(TEAMS)
        if path == "/api/v1/users":
            needle = (q.get("s") or [""])[0].lower()
            return self._json([u for u in USERS
                               if needle in u["username"].lower()
                               or needle in (u["name"] or "").lower()])
        if path.startswith("/api/v1/teams/"):
            parts = path.split("/")
            tid = int(parts[4])
            team = next((t for t in TEAMS if t["id"] == tid), None)
            if team is None:
                return self._json({"message": "not found"}, 404)
            if len(parts) == 5:
                return self._json(team)
            if parts[5] == "members":
                return self._json(team["members"])
        if path.startswith("/api/v1/projects/"):
            parts = path.split("/")
            pid = int(parts[4])
            if len(parts) == 6 and parts[5] == "teams":
                return self._json(PROJECT_TEAMS.get(pid, []))
            if len(parts) == 6 and parts[5] == "users":
                return self._json(PROJECT_USERS.get(pid, []))
            if len(parts) == 6 and parts[5] == "shares":
                return self._json(LINK_SHARES.get(pid, []))
        if path.startswith("/api/v1/tasks/") and path.endswith("/comments"):
            tid = int(path.split("/")[4])
            return self._json(COMMENTS.get(tid, []))
        if path.startswith("/api/v1/tasks/"):
            tid = int(path.rsplit("/", 1)[1])
            match = next((t for t in TASKS if t["id"] == tid), None)
            return self._json(match or {"message": "not found"}, 200 if match else 404)
        self._json({"message": f"unhandled GET {path}"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/v1/login":
            body = self._body()
            if body.get("username") == "joe" and body.get("password") == "secret":
                return self._json({"token": "mock-token"})
            return self._json({"code": 1011, "message": "Wrong username or password."}, 412)
        if not self._authed():
            return
        if path.startswith("/api/v1/teams/"):
            parts = path.split("/")
            tid = int(parts[4])
            if len(parts) >= 7 and parts[6] == "admin":
                uid = int(parts[5])
                for team in TEAMS:
                    for m in team["members"]:
                        if m["id"] == uid:
                            m["admin"] = not m["admin"]
                return self._json({"message": "success"})
            team = next((t for t in TEAMS if t["id"] == tid), None)
            if team is None:
                return self._json({"message": "not found"}, 404)
            body = self._body()
            team.update({k: v for k, v in body.items() if k in ("name", "description")})
            return self._json(team)
        if path.startswith("/api/v1/projects/"):
            parts = path.split("/")
            pid = int(parts[4])
            body = self._body()
            if len(parts) == 7 and parts[5] == "teams":
                team_id = int(parts[6])
                for share in PROJECT_TEAMS.get(pid, []):
                    if share["id"] == team_id:
                        share["permission"] = body.get("permission", share["permission"])
                return self._json({"message": "success"})
            if len(parts) == 7 and parts[5] == "users":
                uid = int(parts[6])
                if uid == 0:
                    pass
                for share in PROJECT_USERS.get(pid, []):
                    if share["id"] == uid:
                        share["permission"] = body.get("permission", share["permission"])
                return self._json({"message": "success"})
            if len(parts) == 5:
                project = next((p for p in PROJECTS if p["id"] == pid), None)
                if project is None:
                    return self._json({"message": "not found"}, 404)
                for k in ("title", "description", "hex_color", "is_favorite"):
                    if k in body:
                        project[k] = body[k]
                if "is_archived" in body:
                    project["is_archived"] = body["is_archived"]
                return self._json(project)
        if path.startswith("/api/v1/tasks/"):
            tid = int(path.rsplit("/", 1)[1])
            body = self._body()
            for i, t in enumerate(TASKS):
                if t["id"] == tid:
                    t.update({k: v for k, v in body.items() if k in t})
                    if body.get("due_date", "").startswith("0001"):
                        t["due_date"] = ZERO
                    return self._json(t)
            return self._json({"message": "not found"}, 404)
        self._json({"message": f"unhandled POST {path}"}, 404)

    def do_PUT(self):
        path = urlparse(self.path).path
        if not self._authed():
            return
        if path == "/api/v1/teams":
            body = self._body()
            new = {"id": max([t["id"] for t in TEAMS] or [0]) + 1,
                   "name": body.get("name", "New team"),
                   "description": body.get("description", ""),
                   "is_public": False, "external_id": "",
                   "created": iso(), "updated": iso(), "members": []}
            TEAMS.append(new)
            return self._json(new)
        if path.startswith("/api/v1/projects/"):
            parts = path.split("/")
            pid = int(parts[4])
            body = self._body()
            if len(parts) == 6 and parts[5] == "teams":
                team_id = body.get("team_id")
                team = next((t for t in TEAMS if t["id"] == team_id), None)
                share = {"id": team_id, "name": team["name"] if team else "Team",
                         "description": team.get("description", "") if team else "",
                         "permission": body.get("permission", 0),
                         "members": team["members"] if team else []}
                PROJECT_TEAMS.setdefault(pid, []).append(share)
                return self._json(share)
            if len(parts) == 6 and parts[5] == "users":
                uid = body.get("user_id")
                user = next((u for u in USERS if u["id"] == uid), None)
                share = dict(user or USER, permission=body.get("permission", 0))
                PROJECT_USERS.setdefault(pid, []).append(share)
                return self._json(share)
            if len(parts) == 6 and parts[5] == "shares":
                share = {"id": max([s["id"] for s in LINK_SHARES.get(pid, [])] or [0]) + 1,
                         "hash": "newhash0123456",
                         "name": body.get("name", "Shared link"),
                         "permission": body.get("permission", 0),
                         "password": body.get("password", "")}
                LINK_SHARES.setdefault(pid, []).append(share)
                return self._json(share)
        if path == "/api/v1/projects":
            body = self._body()
            new = {"id": len(PROJECTS) + 1, "title": body.get("title", "New list"),
                   "hex_color": "", "is_favorite": False, "is_archived": False,
                   "position": 9.0,
                   "views": [{"id": 9, "title": "List", "view_kind": "list", "position": 1}]}
            PROJECTS.append(new)
            return self._json(new)
        if path.startswith("/api/v1/projects/") and path.endswith("/tasks"):
            pid = int(path.split("/")[4])
            body = self._body()
            created = task(max(t["id"] for t in TASKS) + 1, pid, body["title"])
            TASKS.insert(0, created)
            return self._json(created)
        if path == "/api/v1/teams":
            return self._json(TEAMS)
        if path == "/api/v1/users":
            needle = (q.get("s") or [""])[0].lower()
            return self._json([u for u in USERS
                               if needle in u["username"].lower()
                               or needle in (u["name"] or "").lower()])
        if path.startswith("/api/v1/teams/"):
            parts = path.split("/")
            tid = int(parts[4])
            team = next((t for t in TEAMS if t["id"] == tid), None)
            if team is None:
                return self._json({"message": "not found"}, 404)
            if len(parts) == 5:
                return self._json(team)
            if parts[5] == "members":
                return self._json(team["members"])
        if path.startswith("/api/v1/projects/"):
            parts = path.split("/")
            pid = int(parts[4])
            if len(parts) == 6 and parts[5] == "teams":
                return self._json(PROJECT_TEAMS.get(pid, []))
            if len(parts) == 6 and parts[5] == "users":
                return self._json(PROJECT_USERS.get(pid, []))
            if len(parts) == 6 and parts[5] == "shares":
                return self._json(LINK_SHARES.get(pid, []))
        if path.startswith("/api/v1/tasks/") and path.endswith("/comments"):
            tid = int(path.split("/")[4])
            body = self._body()
            entry = {"id": 99, "comment": body.get("comment", ""), "author": USER,
                     "created": iso()}
            COMMENTS.setdefault(tid, []).append(entry)
            return self._json(entry)
        self._json({"message": f"unhandled PUT {path}"}, 404)

    def do_DELETE(self):
        path = urlparse(self.path).path
        if not self._authed():
            return
        if path.startswith("/api/v1/teams/"):
            parts = path.split("/")
            tid = int(parts[4])
            if len(parts) >= 7 and parts[5] == "members":
                username = parts[6]
                for team in TEAMS:
                    if team["id"] == tid:
                        team["members"] = [m for m in team["members"]
                                           if m["username"] != username]
                return self._json({"message": "success"})
            TEAMS[:] = [t for t in TEAMS if t["id"] != tid]
            return self._json({"message": "success"})
        if path.startswith("/api/v1/projects/"):
            parts = path.split("/")
            pid = int(parts[4])
            if len(parts) == 7 and parts[5] == "teams":
                team_id = int(parts[6])
                PROJECT_TEAMS[pid] = [s for s in PROJECT_TEAMS.get(pid, [])
                                      if s["id"] != team_id]
                return self._json({"message": "success"})
            if len(parts) == 7 and parts[5] == "users":
                uid = int(parts[6])
                PROJECT_USERS[pid] = [s for s in PROJECT_USERS.get(pid, [])
                                      if s["id"] != uid]
                return self._json({"message": "success"})
            if len(parts) == 7 and parts[5] == "shares":
                sid = int(parts[6])
                LINK_SHARES[pid] = [s for s in LINK_SHARES.get(pid, [])
                                    if s["id"] != sid]
                return self._json({"message": "success"})
            if len(parts) == 5:
                PROJECTS[:] = [p for p in PROJECTS if p["id"] != pid]
                return self._json({"message": "success"})
        if path.startswith("/api/v1/tasks/"):
            tid = int(path.rsplit("/", 1)[1])
            TASKS[:] = [t for t in TASKS if t["id"] != tid]
            return self._json({"message": "success"})
        self._json({"message": f"unhandled DELETE {path}"}, 404)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8199
    print(f"mock vikunja on http://127.0.0.1:{port} (joe / secret)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
