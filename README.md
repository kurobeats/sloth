<p align="center">
  <img src="assets/sloth.png" alt="Sloth" width="160">
</p>

<h1 align="center">Sloth</h1>

<p align="center">
  An Android task client for a self-hosted <a href="https://vikunja.io">Vikunja</a> server, written in Flutter.
</p>

<p align="center">
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
| Search | `GET /tasks?s=` |

### Projects, teams and labels

| Screen | Vikunja API |
|---|---|
| Projects list (favourites first), quick create | `GET/PUT /projects` |
| Project settings: title, description, identifier, colour, favorite, archive, delete | `POST /projects/{id}`, `DELETE /projects/{id}` |
| Share with users | `GET/PUT/POST/DELETE /projects/{id}/users[/{userID}]` |
| Share with teams | `GET/PUT/POST/DELETE /projects/{id}/teams[/{teamID}]` |
| Link shares: create, copy URL, delete | `GET/PUT /projects/{id}/shares`, `DELETE …/shares/{id}` |
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
cleartext HTTP so the mock server below can be used; release builds keep Android's
HTTPS-only policy.

## Development

```bash
flutter test                    # formatting, grouping, contrast, task row behaviour
tool/mock_vikunja.py            # fake server for UI work (joe / secret, port 8199)
tool/shot.sh                    # Linux build under Xvfb + screenshot
```

To drive the app against the mock on a device:

```bash
python3 tool/mock_vikunja.py 8199
adb reverse tcp:8199 tcp:8199   # then log in to http://127.0.0.1:8199
```

Layout:

```
lib/
  api.dart              thin REST client
  models.dart           Task / Project / Team / Label / User / settings
  state.dart            AppState: session, caches, smart lists, mutations
  todo_theme.dart       Gogh schemes, contrast enforcement, Material theme
  todo_format.dart      due-date, repeat and grouping formatting
  screens/              login, home, task detail, search, settings, account,
                        teams, team detail, project settings, labels
  widgets/              task row, add-a-task bar
```

## Vikunja API notes

Collected by testing against a live Vikunja v2.7.1 instance, in case they help
anyone else writing a client:

- `/tasks` rejects `expand=labels,assignees,reminders`; those come back by default.
  Valid values are `subtasks, buckets, reactions, comments, comment_count,
  time_entries_count, is_unread`.
- `is_favorite` is a task field but **not** a valid filter field, so favourite tasks
  are computed client-side. Vikunja's own "Favorites" pseudo-project (−1) lists
  favourite *projects*, hence the separate name "Favorite Tasks" here.
- Saved filters are served as pseudo-projects with negative ids; they are read-only
  views. Listing them as task targets makes task creation fail.
- Team members are embedded in `GET /teams/{id}`; there is no GET on `/members`.
  Adding a member validates on `username` (an `id` alone returns `Invalid Data`), and
  the returned id is the membership id, not the user id.
- `GET /users?s=` only returns users who enabled "Discoverable by name".
- Avatars live at `/avatar/{username}` (the OpenAPI document's `/{username}/avatar`
  returns 404).
- Demoting a team's last admin leaves the team unmanageable — every management call
  then returns 403, including delete. Sloth blocks that locally.
- Sessions expire per the server's `jwtTTL`; the app keeps the server URL, drops the
  token and asks for a fresh login.

## Known gaps

- No offline cache; a failed write is rolled back by refetching.
- No background reminders/notifications — Vikunja's own notifier is authoritative.
- No attachments, comments, assignee editing, task relations, kanban/table/gantt
  views, or link-share passwords.
- No subtasks/steps: Vikunja models those as task relations rather than checklists.
- Cleartext HTTP is release-blocked by Android's default policy.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
