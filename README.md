<<<<<<< HEAD
# sloth
An Android app for your Vikunja server.
=======
# Sloth

An Android task client for a self-hosted [Vikunja](https://vikunja.io) server, written in Flutter.

The interface follows a single-accent, list-first task app layout: a drawer of smart
lists, flat task rows with a round check target, and a bottom add-a-task bar.

## What it does

Wording follows Vikunja's own UI strings (`src/i18n/lang/en.json` in their
frontend): Favorites, Upcoming, Projects, Labels, Assignees, Done,
"Mark task done!", "Add to Favorites", "Add a new task…".

| Sidebar entry | Vikunja query |
|---|---|
| Due Today | tasks due today or overdue (`due_date < tomorrow`) |
| Favorites | `is_favorite` |
| Upcoming | tasks with a due date, grouped by day |
| All Tasks | tasks across all projects |
| Assigned to Me | tasks whose assignees include you |
| Projects | Vikunja projects, coloured, with open counts |
| Labels | Vikunja labels, each as its own list |
| Task detail | title, Done, Favorite, Description, Due Date, Reminders, Repeat, Priority, Project, Labels |
| Done section | `done` tasks, collapsible, recent first |
| "Add a new task…" bar | `PUT /projects/{id}/tasks` |
| Sidebar avatar | `GET /avatar/{username}?size=128` |

Also: login to any Vikunja instance, search (`s=`), create projects, delete
tasks, and the user's server avatar (initials when none is uploaded). Creating a
task while a label is selected applies that label.

## Themes

Six colour schemes from [Gogh](https://gogh.website) (the terminal-theme
collection at [github.com/Gogh-Co/Gogh](https://github.com/Gogh-Co/Gogh),
MIT / Apache-2.0), with the original names and authors:

| Theme | Author | Mode |
|---|---|---|
| Oceanic Next | mhartington ([oceanic-next-iterm](https://github.com/mhartington/oceanic-next-iterm)) | dark, default |
| Panda | Siamak Mokhtari (Panda Syntax) | dark |
| Catppuccin Mocha | [Catppuccin](https://github.com/catppuccin) | dark |
| Gruvbox Light | morhetz ([gruvbox](https://github.com/morhetz/gruvbox)) | light, default |
| Everforest Light | sainnhe ([everforest](https://github.com/sainnhe/everforest)) | light |
| Patina Light | PoshPalette ([posh-palette](https://github.com/livlign/posh-palette)) | light |

Pick one dark and one light scheme in *Appearance*, plus system / light / dark
mode. Gogh palettes are tuned for terminal text, so the accent, muted text and
danger colours are nudged towards the background's opposite until they clear
WCAG 4.5:1 — `test/theme_contrast_test.dart` enforces that for every scheme.

## Run

```bash
flutter pub get
flutter run -d <android-device>
flutter build apk --release --split-per-abi
```

Sign in with your server URL (for example `https://tasks.example.com`), username and
password. The JWT is stored in Android EncryptedSharedPreferences via
`flutter_secure_storage`; the server URL is stored next to it.

## Tests

```bash
flutter test          # date/repeat formatting, grouping, task row behaviour
tool/mock_vikunja.py  # fake server for UI smoke tests (joe / secret, port 8199)
```

`tool/shot.sh` runs the Linux build under Xvfb and captures a screenshot; it needs
`Xvfb`, `openbox`, `xdotool`, `imagemagick`.

## Layout

```
lib/
  api.dart            thin REST client (auth, projects, tasks, comments)
  models.dart         Task / Project / Label / User / Reminder
  state.dart          AppState (ChangeNotifier): session, caches, smart lists, mutations
  todo_theme.dart     colours, type scale and spacing tokens
  todo_format.dart    due-date, repeat and grouping formatting
  screens/            login, home (drawer + list), task detail, search
  widgets/            task row, add-a-task bar
```

## Deliberate gaps

- No offline cache: the app reads from the server each launch; a failed write rolls
  back by refetching.
- No background reminders/notifications. Reminder times are stored on the server
  (Vikunja's own notifier is authoritative).
- No subtasks/steps (Vikunja has task *relations*, not checklists). Use the note field.
- No attachments, comments UI, kanban/table/gantt views, or labels editing.
- Cleartext HTTP is blocked by Android's default policy; a `http://` server needs a
  network-security config addition.
- The launcher icon is the Flutter default.

## Install

Grab `app-arm64-v8a-release.apk` from the releases page (or `flutter build apk
--release --split-per-abi`), then `adb install app-arm64-v8a-release.apk`.

Package id `io.github.kurobeats.sloth`, minSdk 24, targetSdk 36.
Debug builds allow cleartext HTTP for local mock servers; release builds keep
Android's HTTPS-only policy.
>>>>>>> 03b73a7 (Sloth: Vikunja client with Gogh themes, labels, avatar)

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
