#!/usr/bin/env python3
"""Fill a throwaway Vikunja with demo data, for README screenshots.

    python3 tool/seed_demo.py http://172.16.23.114:3456 joe hellojoe

Idempotent-ish: projects, labels and tasks are reused by title, so running it
twice does not double everything.
"""

import json
import sys
import urllib.request
import uuid
from datetime import date, timedelta

BASE = sys.argv[1].rstrip("/") + "/api/v1"
USER, PASSWORD = sys.argv[2], sys.argv[3]
TOKEN = ""


def call(method, path, body=None, raw=None, ctype="application/json"):
    data = None
    if raw is not None:
        data = raw
    elif body is not None:
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req) as res:
            payload = res.read()
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as e:
        print(f"  ! {method} {path} -> {e.code} {e.read()[:200]}")
        return None


def login():
    global TOKEN
    with urllib.request.urlopen(
        urllib.request.Request(
            BASE + "/login",
            data=json.dumps({"username": USER, "password": PASSWORD}).encode(),
            headers={"Content-Type": "application/json"},
        )
    ) as res:
        TOKEN = json.load(res)["token"]


def multipart(path, filename, content):
    boundary = uuid.uuid4().hex
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="files"; filename="{filename}"\r\n'
        f"Content-Type: text/plain\r\n\r\n"
    ).encode() + content + f"\r\n--{boundary}--\r\n".encode()
    return call(
        "PUT", path, raw=body, ctype=f"multipart/form-data; boundary={boundary}"
    )


def project(title, hex_color, description):
    for p in call("GET", "/projects") or []:
        if p["title"] == title:
            return p
    p = call("PUT", "/projects", {"title": title, "hex_color": hex_color})
    if description:
        call("POST", f"/projects/{p['id']}", {"description": description})
    print(f"  + project {title}")
    return p


def label(title, hex_color):
    for l in call("GET", "/labels") or []:
        if l["title"] == title:
            return l
    l = call("PUT", "/labels", {"title": title, "hex_color": hex_color})
    print(f"  + label {title}")
    return l


def task(pid, title, **fields):
    """Reuse a task by title in this project, otherwise create and patch it."""
    for t in call("GET", f"/projects/{pid}/tasks") or []:
        if t["title"] == title:
            if fields:
                call("POST", f"/tasks/{t['id']}", fields)
            return t
    t = call("PUT", f"/projects/{pid}/tasks", {"title": title})
    if t is None:
        return None
    if fields:
        call("POST", f"/tasks/{t['id']}", fields)
        t.update(fields)
    print(f"  + task {title}")
    return t


def iso(days):
    return (date.today() + timedelta(days=days)).isoformat() + "T12:00:00Z"


login()
me = call("GET", "/user")
print(f"seeding for {me['username']}")

inbox = next(p for p in call("GET", "/projects") or [] if p["title"] == "Inbox")
home = project("Home", "d97f2b", "Flat, garden, paperwork.")
bike = project("Bike Restoration", "2e7dd1", "Bring the 1987 tourer back to life.")
reading = project("Reading", "1a9c9c", "Books and notes.")

errands = label("Errands", "2e7dd1")
weekend = label("Weekend", "3d9a4a")
flat = label("Home", "d97f2b")
deep = label("Deep Work", "7b5cd6")
urgent = label("Urgent", "c0392b")
books = label("Reading", "1a9c9c")

priya = next(u for u in call("GET", "/users?s=priya") or [] if u["username"] == "priya")

oat = task(inbox["id"], "Buy Oat Milk", done=True, priority=1)
filter_change = task(home["id"], "Replace kitchen filter", due_date=iso(0), priority=3)
plumber = task(
    home["id"],
    "Call the plumber about the radiator",
    due_date=iso(0),
    priority=4,
    description="Radiator in the back room never heats up. Ask about a flush.",
)
shelf = task(home["id"], "Sort the bookshelf", due_date=iso(3), priority=1)
biking = task(
    bike["id"],
    "Fix bike",
    due_date=iso(1),
    priority=4,
    description="Rear derailleur skips under load; check chain wear first.",
)
chain = task(bike["id"], "Order new chain", due_date=iso(-1), priority=5)
lube = task(bike["id"], "Clean and lube drivetrain", due_date=iso(5), priority=2)
wheel = task(bike["id"], "True the front wheel", priority=2)
book = task(reading["id"], "Finish The Pragmatic Programmer", due_date=iso(10), priority=1)
notes = task(reading["id"], "Write notes on chapter 4", due_date=iso(2), priority=0)

for t, labels in [
    (oat, [errands]),
    (filter_change, [flat]),
    (plumber, [urgent, flat]),
    (shelf, [flat, weekend]),
    (biking, [errands, weekend]),
    (chain, [urgent]),
    (lube, [weekend]),
    (book, [books]),
    (notes, [books, deep]),
]:
    call(
        "POST",
        f"/tasks/{t['id']}/labels/bulk",
        {"labels": [{"id": l["id"], "title": l["title"]} for l in labels]},
    )

# Assignees need project access first.
for p in (home, bike):
    call("PUT", f"/projects/{p['id']}/users", {"username": "priya", "permission": 1})
for t in (plumber, biking):
    call("PUT", f"/tasks/{t['id']}/assignees", {"user_id": priya["id"]})

def favorite(t):
    # POST /tasks/{id} replaces the task, so send the fields back with it.
    call(
        "POST",
        f"/tasks/{t['id']}",
        {
            "title": t["title"],
            "project_id": t["project_id"],
            "done": t["done"],
            "due_date": t["due_date"],
            "priority": t["priority"],
            "description": t["description"],
            "is_favorite": True,
        },
    )


for t in (biking, book):
    favorite(t)
for p in (bike, home):
    call("POST", f"/projects/{p['id']}", {"title": p["title"], "is_favorite": True})

if not call("GET", f"/tasks/{biking['id']}/comments"):
    for text in (
        "Chain is stretched past 0.75%, so it goes.",
        "Ordered a 9-speed KMC, arrives Thursday.",
    ):
        call("PUT", f"/tasks/{biking['id']}/comments", {"comment": text})

call(
    "PUT",
    f"/tasks/{biking['id']}/relations",
    {"other_task_id": oat["id"], "relation_kind": "subtask"},
)
call(
    "PUT",
    f"/tasks/{biking['id']}/relations",
    {"other_task_id": chain["id"], "relation_kind": "related"},
)

if not call("GET", f"/tasks/{biking['id']}/attachments"):
    multipart(
        f"/tasks/{biking['id']}/attachments",
        "chain-specs.txt",
        b"KMC X9 chain, 116 links\nWear limit 0.75%\nRear derailleur: Shimano Deore\n",
    )

# Kanban: put a few tasks in the Doing bucket of the bike project.
views = call("GET", f"/projects/{bike['id']}/views") or []
kanban = next((v for v in views if v["view_kind"] == "kanban"), None)
if kanban:
    buckets = call("GET", f"/projects/{bike['id']}/views/{kanban['id']}/buckets") or []
    doing = next((b for b in buckets if b["title"] == "Doing"), None)
    todo = next((b for b in buckets if b["title"] == "To-Do"), None)
    if doing and todo:
        call(
            "POST",
            f"/projects/{bike['id']}/views/{kanban['id']}/buckets/{doing['id']}/tasks",
            {"task_id": biking["id"]},
        )
        for t in (chain, wheel):
            call(
                "POST",
                f"/projects/{bike['id']}/views/{kanban['id']}/buckets/{todo['id']}/tasks",
                {"task_id": t["id"]},
            )

# A team and a password-protected link share to show in project settings.
teams = call("GET", "/teams") or []
club = next((t for t in teams if t.get("name") == "Bike Club"), None)
if not club:
    club = call("PUT", "/teams", {"name": "Bike Club"})
    call("PUT", f"/teams/{club['id']}/members", {"username": "priya"})
    print("  + team Bike Club")

if not call("GET", f"/projects/{bike['id']}/shares"):
    call(
        "PUT",
        f"/projects/{bike['id']}/shares",
        {"right": 0, "label": "Bike Club read-only", "password": "chainwax"},
    )

print("done")
