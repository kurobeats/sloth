<p align="center">
  <img src="assets/sloth.png" alt="Sloth" width="160">
</p>

<h1 align="center">Sloth</h1>

<p align="center">
  An Android task client for a self-hosted <a href="https://vikunja.io">Vikunja</a> server, written in Flutter.
</p>

<p align="center">
  <a href="#screenshots">Screenshots</a> ·
  <a href="#features">Features</a> ·
  <a href="#themes">Themes</a> ·
  <a href="#build-and-install">Build</a> ·
  <a href="#vikunja-api-notes">API notes</a> ·
  <a href="#known-gaps">Gaps</a>
</p>

---

Sloth is a list-first task app: a drawer of smart lists, projects, filters and
labels; flat task rows with a round check target; and a bottom add-a-task bar.
Wording follows Vikunja's own interface strings, so what you see here is what the
web UI calls it too.

## Screenshots

<p align="center">
  <img src="docs/screenshots/tasks.png" width="270" alt="Task list">
  <img src="docs/screenshots/drawer.png" width="270" alt="Drawer">
  <img src="docs/screenshots/notifications.png" width="270" alt="Notifications">
</p>

<p align="center">
  <img src="docs/screenshots/task-detail.png" width="270" alt="Task detail">
  <img src="docs/screenshots/task-detail-extras.png" width="270" alt="Assignees, related tasks, attachments, comments">
  <img src="docs/screenshots/themes.png" width="270" alt="Theme picker">
</p>

<p align="center">
  <img src="docs/screenshots/kanban.png" width="760" alt="Kanban board in landscape">
</p>

<p align="center">
  <img src="docs/screenshots/project-settings.png" width="270" alt="Project settings, sharing and link shares">
</p>

## Features

### Tasks

| Screen | Vikunja query |
|---|---|
| Due Today | tasks due today or overdue (`due_date < tomorrow`) |
| Favorite Tasks | `is_favorite` (computed client-side; not a filterable field) |
| Upcoming | tasks due in the next 7 days, grouped by day |
| All Tasks | tasks across all projects |
| Assigned to Me | tasks whose assignees include you |
| Done section | completed tasks, collapsible, recent first |
| Add a new task… bar | `PUT /projects/{id}/tasks` |
| Task detail | title, Done, Favorite, Description, Due Date, Reminders, Repeat, Priority, Project, Labels |
| Labels on a task | `POST /tasks/{id}/labels/bulk` |
| Assignees | `PUT/DELETE /tasks/{id}/assignees[/{userID}]` |
| Related tasks (subtask, parent, related, duplicate) | `PUT/DELETE /tasks/{id}/relations`, `…/{kind}/{otherTaskID}` |
| Attachments: upload, download/share, delete | `PUT/GET /tasks/{id}/attachments`, `DELETE …/{attachmentID}` |
| Comments: read, add, delete your own | `GET/PUT /tasks/{id}/comments`, `DELETE …/{commentID}` |
| Notifications: assignments, comments, team changes | `GET /notifications`, `POST /notifications/{id}` |
| Kanban board: columns from the project's kanban view, drag to move | `GET /projects/{id}/views/{view}/tasks`, `POST …/buckets/{bucketID}/tasks` |
| Search | `GET /tasks?s=` |

Subtasks are shown as related tasks with their own done checkbox, so a checklist
stays a Vikunja subtask relation rather than a private format. Tapping any
related task opens it in the normal detail screen.

### Projects, teams and labels

| Screen | Vikunja API |
|---|---|
| Projects list (favourites first), quick create | `GET/PUT /projects` |
| Project settings: title, description, identifier, colour, favorite, archive, delete | `POST /projects/{id}`, `DELETE /projects/{id}` |
| Share with users | `GET/PUT/POST/DELETE /projects/{id}/users[/{userID}]` |
| Share with teams | `GET/PUT/POST/DELETE /projects/{id}/teams[/{teamID}]` |
| Link shares: create (optionally password protected), copy URL, delete | `GET/PUT /projects/{id}/shares`, `DELETE …/shares/{id}` |
| Saved filters | listed under **Filters** (read-only pseudo-projects) |
| Teams: list, create, rename, delete | `GET/PUT/POST/DELETE /teams[/{id}]` |
| Team members: add, remove, admin toggle | `GET /teams/{id}` (members embedded), `PUT/DELETE /teams/{id}/members…`, `POST /teams/{id}/members/{username}/admin` |
| Labels: list, create, edit, delete, per-label task lists | `GET/PUT/POST/DELETE /labels[/{id}]` |

### Account

| Screen | Vikunja API |
|---|---|
| Account settings: display name, language, timezone, week start, default project, discoverability, email/overdue reminders | `POST /user/settings/general`, read from `GET /user` |
| Sidebar avatar | `GET /avatar/{username}?size=128` |
| Login / logout, session expiry recovery | `POST /login`, `POST /user/settings/…` |

### Offline

Every successful refresh stores a snapshot on the device. Launch the app with no
network and Sloth opens the last snapshot instead of an empty screen, with a
banner saying how old it is. The cache is read-only: while offline the add-a-task
bar is disabled and every edit reports *"Editing is disabled while offline.
Reconnect to your server to make changes."* Retry re-fetches when the server is
back.

Self-hosted servers on a private CA (Caddy's internal authority, for example) are
supported: tick **Allow self-signed certificate** on the login screen. Trust is
granted per server, for that host only, and is stored with the server URL.

## Themes

Six colour schemes from [Gogh](https://gogh.website) (the terminal-theme collection
at [github.com/Gogh-Co/Gogh](https://github.com/Gogh-Co/Gogh), MIT / Apache-2.0),
with their original names and authors:

| Theme | Author | Mode |
|---|---|---|
| Oceanic Next | mhartington ([oceanic-next-iterm](https://github.com/mhartington/oceanic-next-iterm)) | dark, default |
| Panda | Siamak Mokhtari (Panda Syntax) | dark |
| Catppuccin Mocha | [Catppuccin](https://github.com/catppuccin) | dark |
| Gruvbox Light | morhetz ([gruvbox](https://github.com/morhetz/gruvbox)) | light, default |
| Everforest Light | sainnhe ([everforest](https://github.com/sainnhe/everforest)) | light |
| Patina Light | PoshPalette ([posh-palette](https://github.com/livlign/posh-palette)) | light |

Pick one dark and one light scheme in **Settings**, plus system / light / dark mode.
Gogh palettes are tuned for terminal text, so accent, muted text and danger colours
are nudged until they clear WCAG 4.5:1 against their background; every UI colour
comes from the active scheme. The exception is labels, whose colours are server data.

## Build and install

```bash
flutter pub get
flutter build apk --release --split-per-abi
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Package id `io.github.kurobeats.sloth`, minSdk 24, targetSdk 36. Debug builds allow
cleartext HTTP so a local mock server can be used; release builds keep Android's
HTTPS-only policy.

## Development

```bash
flutter test                    # formatting, grouping, contrast, tiles, API bodies
tool/mock_vikunja.py            # fake server for UI work (joe / secret, port 8199)
tool/seed_demo.py URL USER PASS # fill a throwaway server with the demo data above
tool/shot.sh                    # Linux build under Xvfb + screenshot
```

To drive the app against the mock on a device:

```bash
python3 tool/mock_vikunja.py 8199
adb reverse tcp:8199 tcp:8199   # then log in to http://127.0.0.1:8199
```

`tool/seed_demo.py` is what produced the screenshots: four projects, six labels,
a dozen tasks with due dates, priorities, assignees, comments, an attachment,
subtask relations, a kanban board with moved cards, a team and a password
protected link share.

Layout:

```
lib/
  api.dart              thin REST client
  models.dart           Task / Project / Team / Label / User / Notification / …
  state.dart            AppState: session, caches, smart lists, mutations
  offline_cache.dart    read-only snapshot of the last successful refresh
  todo_theme.dart       Gogh schemes, contrast enforcement, Material theme
  todo_format.dart      due-date, repeat and grouping formatting
  screens/              login, home, task detail, board, notifications, search,
                        settings, account, teams, team detail, project settings,
                        labels
  widgets/              task row, add-a-task bar, offline banner,
                        assignees/relations/attachments/comments, notification row
test/                   formatting, grouping, contrast, row and tile behaviour,
                        multipart upload, update payloads
```

The presentation widgets take plain data plus callbacks and never reach for the
app state themselves, which is why the tiles and rows can be tested without a
server.

## Vikunja API notes

Collected by testing against a live Vikunja v2.7.1 instance, in case they help
anyone else writing a client:

- `/tasks` rejects `expand=labels,assignees,reminders`; those come back by default.
  Valid values are `subtasks, buckets, reactions, comments, comment_count,
  time_entries_count, is_unread`.
- `POST /tasks/{id}` replaces the task: an omitted `due_date` is cleared rather
  than kept. Send the whole task back, including `labels`, `assignees` and
  `reminders` (nested collections are replaced wholesale).
- Relation kinds are **strings** in both the request body and the `related_tasks`
  map (`subtask`, `parenttask`, `related`, `duplicateof`, …). Integers are
  rejected with `Invalid model provided`.
- `is_favorite` is a task field but **not** a valid filter field, so favourite tasks
  are computed client-side. Vikunja's own "Favorites" pseudo-project (−1) lists
  favourite *projects*, hence the separate name "Favorite Tasks" here.
- Saved filters are served as pseudo-projects with negative ids; they are read-only
  views. Listing them as task targets makes task creation fail.
- Kanban columns come from `GET /projects/{id}/views/{kanbanViewID}/tasks`, which
  returns buckets with their tasks embedded. `GET …/buckets` alone returns the
  columns without cards, and `expand=buckets` does nothing for list views.
- Project and team shares take `permission` (`0` read, `1` write, `2` admin);
  a `right` field is silently ignored and the share lands as read-only.
- Team members are embedded in `GET /teams/{id}`; there is no GET on `/members`.
  Adding a member validates on `username` (an `id` alone returns `Invalid Data`), and
  the returned id is the membership id, not the user id.
- `GET /users?s=` only returns users who enabled "Discoverable by name".
- Avatars live at `/avatar/{username}` (the OpenAPI document's `/{username}/avatar`
  returns 404).
- Attachments upload as multipart with the field name `files`.
- Notifications are `{id, name, created, read_at, notification}` where `name` is
  e.g. `task.assigned`, `task.comment`, `team.member.added` and the payload differs
  per kind. `read_at` is the zero timestamp (`0001-01-01…`) until read; marking read
  is `POST /notifications/{id}` with `{"read": true}`.
- Demoting a team's last admin leaves the team unmanageable — every management call
  then returns 403, including delete. Sloth blocks that locally.
- Sessions expire per the server's `jwtTTL`; the app keeps the server URL, drops the
  token and asks for a fresh login.

## Known gaps

- Table and Gantt views are not rendered; only list and kanban.
- Offline is read-only: no offline queue, a failed write is simply reported.
- No background reminders or push. Notifications are pulled when you open them.
- Repeat rules can be set but not edited per-occurrence; Vikunja decides what a
  completed repeating task turns into.
- Cleartext HTTP is release-blocked by Android's default policy.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
