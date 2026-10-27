import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'home_widget_sync.dart';
import 'models.dart';
import 'offline_cache.dart';
import 'todo_theme.dart';

enum SmartList {
  // Names follow Vikunja's vocabulary: Favorite tasks, Upcoming, Assignees.
  dueToday('Due Today'),
  // "Favorite Tasks": Vikunja's own "Favorites" pseudo-project (-1) lists
  // favorite *projects*, so the task list needs its own name.
  favorites('Favorite Tasks'),
  upcoming('Upcoming'),
  allTasks('All Tasks'),
  assigned('Assigned to Me');

  const SmartList(this.label);

  final String label;
}

/// Task-list order, chosen in the home screen overflow menu.
enum SortMode { dueDate, alphabetical }

/// Natural A→Z compare: case-insensitive, digit runs compared numerically so
/// Johnny.Decimal prefixes ("1.2", "1.10", "11") sort correctly.
int compareNatural(String a, String b) {
  int i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ca = a[i], cb = b[j];
    final da = _isDigit(ca), db = _isDigit(cb);
    if (da && db) {
      int sa = i, sb = j;
      while (i < a.length && _isDigit(a[i])) {
        i++;
      }
      while (j < b.length && _isDigit(b[j])) {
        j++;
      }
      final na = int.tryParse(a.substring(sa, i));
      final nb = int.tryParse(b.substring(sb, j));
      if (na != nb) return (na ?? 0).compareTo(nb ?? 0);
    } else {
      final cmp = ca.toLowerCase().compareTo(cb.toLowerCase());
      if (cmp != 0) return cmp;
      i++;
      j++;
    }
  }
  return (a.length - i).compareTo(b.length - j);
}

bool _isDigit(String ch) => ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

/// What the task list is currently showing: a smart list, a project, or a tag.
class ListSelection {
  const ListSelection.smart(this.smart) : project = null, tag = null;
  const ListSelection.project(this.project) : smart = null, tag = null;
  const ListSelection.tag(this.tag) : smart = null, project = null;

  final SmartList? smart;
  final VikunjaProject? project;
  final VikunjaLabel? tag;

  String get title => smart?.label ?? project?.title ?? tag?.title ?? 'Tasks';

  bool get groupsByDay => smart == SmartList.upcoming;

  /// Whether rows in this list need the project name beside the task: the
  /// lists that mix projects (a tag, or a smart list across all of them) do, a
  /// single project's own list and the upcoming window do not.
  bool get showProject =>
      tag != null ||
      smart == SmartList.allTasks ||
      smart == SmartList.assigned ||
      smart == SmartList.favorites;

  String get key => tag != null
      ? 'tag:${tag!.id}'
      : smart != null
      ? 'smart:${smart!.name}'
      : 'project:${project!.id}';

  @override
  bool operator ==(Object other) => other is ListSelection && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Everything the app shell (the `MaterialApp`) renders: the appearance and
/// whether a session is up. Data notifications never produce a new value, so
/// loading flips, mutations and the notification poll no longer rebuild the
/// navigator and the route under it.
@immutable
class AppShell {
  const AppShell({
    required this.lightThemeId,
    required this.darkThemeId,
    required this.themeMode,
    required this.restoring,
    required this.signedIn,
  });

  final String lightThemeId;
  final String darkThemeId;
  final ThemeMode themeMode;
  final bool restoring;
  final bool signedIn;

  TodoColors get lightTheme => TodoColors.byId(lightThemeId, Brightness.light);

  TodoColors get darkTheme => TodoColors.byId(darkThemeId, Brightness.dark);

  @override
  bool operator ==(Object other) =>
      other is AppShell &&
      other.lightThemeId == lightThemeId &&
      other.darkThemeId == darkThemeId &&
      other.themeMode == themeMode &&
      other.restoring == restoring &&
      other.signedIn == signedIn;

  @override
  int get hashCode =>
      Object.hash(lightThemeId, darkThemeId, themeMode, restoring, signedIn);
}

class AppState extends ChangeNotifier {
  AppState({FlutterSecureStorage? storage})
    : _storage = storage ?? storageOptions;

  /// The session token, the theme ids and the offline snapshot live in the
  /// keychain/keystore. Both sides are pinned explicitly: on iOS the default
  /// item rides an encrypted backup to a new device, while
  /// `first_unlock_this_device` keeps the data on this phone.
  /// flutter_secure_storage 11 dropped v9's `encryptedSharedPreferences` flag —
  /// the Android side is Keystore-wrapped AES-GCM either way, so there is
  /// nothing left to switch on there.
  static const storageOptions = secureStorageOptions;

  static const _kBase = 'vikunja_base';
  static const _kToken = 'vikunja_token';
  static const _kRefresh = 'vikunja_refresh';
  static const _kAllowSelfSigned = 'vikunja_allow_self_signed';
  static const _kLightTheme = 'theme_light';
  static const _kDarkTheme = 'theme_dark';
  static const _kThemeMode = 'theme_mode';
  static const _kSortMode = 'sort_mode';

  final FlutterSecureStorage _storage;

  VikunjaApi? api;
  VikunjaUser? user;
  String? baseUrl;
  Uint8List? avatar;

  /// Last server used, so the login form can prefill it (e.g. after expiry).
  String? lastServer;

  /// True when the visible data came from the on-disk snapshot.
  bool offline = false;

  static const offlineEditError =
      'Editing is disabled while offline. Reconnect to your server to make changes.';

  /// What the user is told when the server rejects the stored token. One
  /// string for every path: the session ends once, wherever the 401 came from.
  static const sessionExpiredError =
      'Your session expired. Please log in again.';

  /// Vikunja lets the last admin of a team demote themselves, which locks
  /// everyone out of team management. Refused in the state, not in a screen.
  static const lastAdminError =
      'A team needs at least one admin. Promote someone else first.';

  /// How many times a session was actually torn down. A 401 must end it once,
  /// however many screens were talking to the server at the time.
  @visibleForTesting
  int signOuts = 0;

  /// Every write path checks this; offline is read-only.
  bool get canEdit => !offline;
  DateTime? cachedAt;

  OfflineCache? _cache;
  bool allowSelfSigned = false;

  /// How the task list is ordered; the projects list is always A→Z.
  SortMode sortMode = SortMode.dueDate;

  List<VikunjaProject> projects = const [];
  List<VikunjaLabel> labels = const [];
  List<VikunjaTeam> teams = const [];
  List<VikunjaTask> _allTasks = const [];
  Map<int, List<VikunjaTask>> _projectTasks = {};

  ListSelection selection = const ListSelection.smart(SmartList.dueToday);

  bool _restoring = true;
  bool get restoring => _restoring;

  /// Flipping [restoring] off is what completes [ready], so every way out of a
  /// restore — the real one, a failed one, or a fake in a test — releases the
  /// waiters.
  set restoring(bool value) {
    _restoring = value;
    if (value || _readyCompleter.isCompleted) return;
    _readyCompleter.complete();
  }

  /// Completes when the restore has finished. Startup waits on this instead of
  /// re-reading [restoring] every 100 ms.
  Future<void> get ready => _readyCompleter.future;
  final Completer<void> _readyCompleter = Completer<void>();

  bool loading = false;
  String? error;

  /// A paged read in the last refresh stopped at the client's row ceiling, so
  /// the list may be missing rows. The list screen says so instead of showing
  /// a silently cut list.
  bool listTruncated = false;

  /// What the list screen shows when [listTruncated].
  static String get truncationNotice =>
      'This list is longer than ${VikunjaApi.maxPages * 50} rows, so only the '
      'first part is shown.';

  // ------------------------------------------------------------ appearance --

  String lightThemeId = TodoColors.defaultLight.id;
  String darkThemeId = TodoColors.defaultDark.id;
  ThemeMode themeMode = ThemeMode.system;

  TodoColors get lightTheme => TodoColors.byId(lightThemeId, Brightness.light);
  TodoColors get darkTheme => TodoColors.byId(darkThemeId, Brightness.dark);

  AppShell get _shellConfig => AppShell(
    lightThemeId: lightThemeId,
    darkThemeId: darkThemeId,
    themeMode: themeMode,
    restoring: restoring,
    signedIn: isSignedIn,
  );

  /// Fires only when what the app shell renders changes. [ValueNotifier] drops
  /// values equal to the current one, so the 50-odd data notifications a
  /// refresh produces cost one comparison here instead of a whole-app rebuild.
  late final ValueNotifier<AppShell> shell = ValueNotifier(_shellConfig);

  /// Bumped by the home widget's plus button. It counts rather than flags so a
  /// second tap while the bar is already focused still does something.
  final ValueNotifier<int> newTaskRequests = ValueNotifier(0);

  /// Set by [dispose]. A request that was in flight when the screen went away
  /// still completes, and notifying a disposed notifier throws.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    _openCache = null;
    _completedCache = null;
    _projectIndex = null;
    _taskIndex = null;
    shell.value = _shellConfig;
    super.notifyListeners();
  }

  Future<void> loadAppearance() async {
    try {
      // Four independent keys: read them together, not one await after another.
      final saved = await Future.wait([
        _storage.read(key: _kLightTheme),
        _storage.read(key: _kDarkTheme),
        _storage.read(key: _kThemeMode),
        _storage.read(key: _kAllowSelfSigned),
        _storage.read(key: _kSortMode),
      ]);
      lightThemeId = saved[0] ?? TodoColors.defaultLight.id;
      darkThemeId = saved[1] ?? TodoColors.defaultDark.id;
      themeMode = switch (saved[2]) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      // Remembered per server, so the login form can prefill the box.
      allowSelfSigned = saved[3] == 'true';
      sortMode = saved[4] == 'alphabetical'
          ? SortMode.alphabetical
          : SortMode.dueDate;
    } catch (_) {
      // Storage unavailable: fall back to the defaults above.
    }
    notifyListeners();
  }

  Future<void> setLightTheme(String id) async {
    lightThemeId = id;
    notifyListeners();
    await _storage.write(key: _kLightTheme, value: id);
    // The home screen widget is painted with these colours.
    unawaited(syncHomeWidget(this));
  }

  Future<void> setDarkTheme(String id) async {
    darkThemeId = id;
    notifyListeners();
    await _storage.write(key: _kDarkTheme, value: id);
    unawaited(syncHomeWidget(this));
  }

  Future<void> setSortMode(SortMode mode) async {
    if (mode == sortMode) return;
    sortMode = mode;
    notifyListeners();
    await _storage.write(
      key: _kSortMode,
      value: mode == SortMode.alphabetical ? 'alphabetical' : 'due_date',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _storage.write(
      key: _kThemeMode,
      value: switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
    unawaited(syncHomeWidget(this));
  }

  bool get isSignedIn => api != null && user != null;

  /// Test seam for the client [signIn] and [restore] build: a fake http client
  /// can then observe `close()`. Unset in production.
  @visibleForTesting
  VikunjaApi Function(String baseUrl, {bool allowSelfSigned})? clientFactory;

  VikunjaApi _newClient(String baseUrl, bool allowSelfSigned) =>
      clientFactory?.call(baseUrl, allowSelfSigned: allowSelfSigned) ??
      VikunjaApi(baseUrl: baseUrl, allowSelfSigned: allowSelfSigned);

  // ---------------------------------------------------------------- boot ----

  Future<void> restore() async {
    await loadAppearance();
    try {
      final saved = await Future.wait([
        _storage.read(key: _kBase),
        _storage.read(key: _kToken),
        _storage.read(key: _kAllowSelfSigned),
        _storage.read(key: _kRefresh),
      ]);
      final base = saved[0];
      final token = saved[1];
      final allowBadCert = saved[2] == 'true';
      final refreshCookie = saved[3] ?? '';
      // The server is remembered even with no token, so the login form can
      // prefill it after a logout.
      lastServer = base;
      if (base != null && token != null && token.isNotEmpty) {
        final client = _newClient(base, allowBadCert)
          ..token = token
          ..refreshToken = refreshCookie;
        baseUrl = base;
        _cache = OfflineCache(key: 'cache:$base', storage: _storage);

        // Paint from the snapshot immediately; it is the only thing that works
        // when the server is unreachable.
        final hadCache = await _loadCache();
        try {
          await _connect(client, persist: false);
          await refresh();
        } on VikunjaException catch (e) {
          if (e.isUnauthorized) {
            await _storage.delete(key: _kToken);
            await _storage.delete(key: _kRefresh);
            _dropClient(client);
            offline = false;
            error = sessionExpiredError;
          } else if (!hadCache) {
            error = e.message;
            _dropClient(client);
          } else {
            // Keep the cached view, read-only, and let the user read it.
            _adoptOffline(client);
          }
        } catch (e) {
          if (!hadCache) {
            error = 'Cannot reach $base. Check the server or your connection.';
            _dropClient(client);
          } else {
            _adoptOffline(client);
          }
        }
      }
    } catch (e) {
      error = e.toString();
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> signIn({
    required String server,
    required String username,
    required String password,
    bool allowBadCert = false,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    final client = _newClient(server, allowBadCert);
    try {
      await client.info(); // fail fast on a wrong URL
      await client.login(username, password);
      await _connect(client, persist: true);
      await refresh();
    } on VikunjaException catch (e) {
      _dropClient(client);
      error = e.message;
    } catch (e) {
      _dropClient(client);
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Adopts a client whose first request failed. [_connect] assigns [api] only
  /// after that request, so an unreachable server would otherwise leave the app
  /// with a cached snapshot and no session, which renders the login form and
  /// hides the very data the snapshot was kept for. The client stays unusable
  /// for writes: [offline] gates every mutation.
  void _adoptOffline(VikunjaApi client) {
    if (!identical(api, client)) api?.close();
    api = client;
    baseUrl = client.baseUrl;
    lastServer = client.baseUrl;
    _cache = OfflineCache(key: 'cache:${client.baseUrl}', storage: _storage);
    allowSelfSigned = client.allowSelfSigned;
    offline = true;
    error = null;
  }

  /// Drops a client whose connect failed. `_connect` assigns [api] only after
  /// its first await, so a throw before that leaves the client owned by nobody:
  /// without this its socket pool leaks on every failed login or restore.
  void _dropClient(VikunjaApi client) {
    if (!identical(api, client)) api?.close();
    api = null;
    user = null;
    client.close();
  }

  Future<void> _connect(VikunjaApi client, {required bool persist}) async {
    final me = await client.currentUser();
    // restore() hands the same client in; closing it here killed every later
    // request with "Client is already closed".
    if (!identical(api, client)) api?.close();
    api = client;
    user = me;
    baseUrl = client.baseUrl;
    lastServer = client.baseUrl;
    _cache = OfflineCache(key: 'cache:${client.baseUrl}', storage: _storage);
    allowSelfSigned = client.allowSelfSigned;
    // The avatar is one more round trip and only feeds a 32px circle: fetching
    // it serially held the first paint of the task list behind a 404.
    unawaited(_loadAvatar(client, me.username));
    if (persist) {
      // Three independent keys; write them together.
      await Future.wait([
        _storage.write(key: _kBase, value: client.baseUrl),
        _storage.write(key: _kToken, value: client.token),
        _storage.write(
          key: _kAllowSelfSigned,
          value: client.allowSelfSigned.toString(),
        ),
        _storage.write(key: _kRefresh, value: client.refreshToken),
      ]);
    }
  }

  Future<void> _loadAvatar(VikunjaApi client, String username) async {
    final bytes = await client.avatar(username);
    // A sign-out or another account in the meantime must not get this face.
    if (bytes == null || !identical(api, client)) return;
    avatar = bytes;
    notifyListeners();
  }

  Future<void> signOut() async {
    signOuts++;
    lastServer = api?.baseUrl ?? lastServer;
    api?.close();
    api = null;
    user = null;
    projects = const [];
    labels = const [];
    teams = const [];
    avatar = null;
    listTruncated = false;
    _allTasks = const [];
    _projectTasks = {};
    _shares.clear();
    _boardBuckets.clear();
    _fetchedTasks.clear();
    selection = const ListSelection.smart(SmartList.dueToday);
    // A snapshot still queued from the last refresh must not land after the
    // wipe, and the dedupe key belongs to the account that just left.
    _cacheFlush?.cancel();
    _cacheFlush = null;
    _pendingCache = null;
    _lastCachePayload = null;
    // The snapshot is the whole workspace, team member emails included: a
    // logged-out device must not keep it.
    await _cache?.clear();
    _cache = null;
    cachedAt = null;
    // Keep the theme and the per-server certificate trust: both are device
    // preferences, and re-logging into a private-CA server should not require
    // ticking the box again.
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kRefresh);
    notifyListeners();
  }

  /// Ends the session at most once, however many screens were talking to the
  /// server with the same dead token: the first 401 wins, the rest find no
  /// session left to end.
  Future<void> _endSession() async {
    if (api == null) return;
    await signOut();
    error = sessionExpiredError;
    notifyListeners();
  }

  /// The one place a failed state-level call becomes a message. A 401 signs the
  /// app out instead of leaving the stale token in use and failing again on the
  /// next screen; anything else is passed through as the server said it.
  Future<String> _failure(VikunjaException e) async {
    if (!e.isUnauthorized) return e.message;
    await _endSession();
    return sessionExpiredError;
  }

  // ---------------------------------------------------------------- data ----

  /// The refresh that is already running, if any. The poller, a
  /// pull-to-refresh and a screen retry all land here, and two of them reading
  /// the same endpoints at once only doubles the traffic and the chance of one
  /// answer landing on top of the other.
  Future<void>? _refreshInFlight;

  Future<void> refresh() {
    final pending = _refreshInFlight;
    if (pending != null) return pending;
    late final Future<void> run;
    run = _refresh().whenComplete(() {
      if (identical(_refreshInFlight, run)) _refreshInFlight = null;
    });
    _refreshInFlight = run;
    return run;
  }

  Future<void> _refresh() async {
    final client = api;
    if (client == null) return;
    loading = true;
    error = null;
    notifyListeners();
    // Local edits that land from here on are newer than this read.
    final editMark = _localEdits.length;
    // Any of the reads below may hit the row ceiling; the flag is read back
    // once they have all landed.
    client.truncated = false;
    try {
      final results = await Future.wait([
        client.projects(),
        client.allTasks(sortBy: 'due_date', orderBy: 'asc'),
        client.labels(),
        client.teams(),
        // Unread count for the drawer; a missing notification endpoint on an
        // old server must not fail the whole refresh.
        client.notifications().catchError((_) => <VikunjaNotification>[]),
      ]);
      // Read the locally held copies before the fresh lists replace them: the
      // answer below was fetched before those edits landed.
      final localEdits = _localEditsSince(editMark);
      projects = results[0] as List<VikunjaProject>;
      _allTasks = results[1] as List<VikunjaTask>;
      if (localEdits.isNotEmpty) {
        _allTasks = [for (final t in _allTasks) localEdits[t.id] ?? t];
      }
      _localEdits.clear();
      for (final task in _allTasks) {
        _fetchedTasks.remove(task.id);
      }
      labels = results[2] as List<VikunjaLabel>;
      teams = results[3] as List<VikunjaTeam>;
      notifications = results[4] as List<VikunjaNotification>;
      listTruncated = client.truncated;
      _projectTasks = {};
      final project = selection.project;
      if (project != null) {
        // The all-tasks fetch above already carries this project's rows; asking
        // the view endpoint again fetched the same tasks a second time.
        _projectTasks[project.id] = _tasksInProject(project.id);
      }
      offline = false;
      error = null;
      await _saveCache();
      unawaited(syncHomeWidget(this));
    } on VikunjaException catch (e) {
      if (e.isUnauthorized) {
        error = await _failure(e);
      } else if (await _loadCache()) {
        // No server: keep whatever the cache gave us.
        offline = true;
        error = null;
      } else {
        offline = false;
        error = e.message;
      }
    } catch (e) {
      if (!await _loadCache()) error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// The tasks [projectId] owns, from the full task list.
  List<VikunjaTask> _tasksInProject(int projectId) => [
    for (final t in _allTasks)
      if (t.projectId == projectId) t,
  ];

  Future<void> _loadProjectTasks() async {
    final client = api;
    final project = selection.project;
    if (client == null || project == null) return;
    final viewId = project.listViewId;
    if (viewId == null) {
      _projectTasks[project.id] = const [];
      return;
    }
    _projectTasks[project.id] = await client.projectTasks(project.id, viewId);
  }

  Future<void> select(ListSelection next) async {
    selection = next;
    notifyListeners();
    if (next.project != null && !_projectTasks.containsKey(next.project!.id)) {
      loading = true;
      notifyListeners();
      try {
        await _loadProjectTasks();
      } on VikunjaException catch (e) {
        error = await _failure(e);
      } finally {
        loading = false;
        notifyListeners();
      }
    }
  }

  // ------------------------------------------------------- derived views ----

  /// Clock seam: the tests pin "today" instead of depending on the wall clock.
  DateTime Function() clock = DateTime.now;

  // Derived views are rebuilt on the first read after a notification, so a
  // rebuild does not rescan every task.
  List<VikunjaTask>? _openCache;
  List<VikunjaTask>? _completedCache;
  Map<int, VikunjaProject>? _projectIndex;
  Map<int, VikunjaTask>? _taskIndex;

  /// Every task the app holds, for the home screen widget.
  List<VikunjaTask> get allTasksForWidget => _allTasks;

  List<VikunjaTask> get _source => selection.project != null
      ? (_projectTasks[selection.project!.id] ?? const [])
      : _allTasks;

  /// Whether a task belongs to the current list, ignoring its done state.
  /// [today] is midnight and [tomorrow] the exclusive cut-off, hoisted by the
  /// caller so a pass over 500 tasks reads the clock once.
  bool _matchesList(VikunjaTask t, DateTime today, DateTime tomorrow) {
    final tag = selection.tag;
    if (tag != null) return t.labels.any((l) => l.id == tag.id);
    switch (selection.smart) {
      case SmartList.dueToday:
        return t.isDueBy(tomorrow);
      case SmartList.favorites:
        return t.isFavorite;
      case SmartList.upcoming:
        // Vikunja's Upcoming view is a seven-day window from today.
        final due = t.dueDate;
        if (due == null) return false;
        final diff = daysBetween(due, today);
        return diff >= 0 && diff < 7;
      case SmartList.assigned:
        final me = user?.id;
        return me != null && t.assignees.any((a) => a.id == me);
      case SmartList.allTasks:
      case null:
        return true;
    }
  }

  List<VikunjaTask> get openTasks => _openCache ??= _computeOpen();

  List<VikunjaTask> _computeOpen() {
    final today = startOfDay(clock());
    final tomorrow = endOfToday(clock());
    final list = _source
        .where((t) => !t.done && _matchesList(t, today, tomorrow))
        .toList();
    list.sort(_taskCompare);
    return list;
  }

  List<VikunjaTask> get completedTasks =>
      _completedCache ??= _computeCompleted();

  List<VikunjaTask> _computeCompleted() {
    final today = startOfDay(clock());
    final tomorrow = endOfToday(clock());
    // Smart lists show recent completions only; project and tag views show all.
    final cutoff = switch (selection.smart) {
      SmartList.dueToday => today,
      null => null,
      _ => today.subtract(const Duration(days: 7)),
    };
    final list = _source.where((t) {
      if (!t.done || !_matchesList(t, today, tomorrow)) return false;
      if (cutoff == null) return true;
      final at = t.doneAt;
      return at != null && !at.isBefore(cutoff);
    }).toList();
    list.sort(
      (a, b) =>
          (b.doneAt ?? DateTime(2000)).compareTo(a.doneAt ?? DateTime(2000)),
    );
    return list;
  }

  /// Open-task count per smart list; one hoisted clock for the whole pass.
  int countFor(SmartList smart) {
    final today = startOfDay(clock());
    final tomorrow = endOfToday(clock());
    return _allTasks.where((t) {
      if (t.done) return false;
      switch (smart) {
        case SmartList.dueToday:
          return t.isDueBy(tomorrow);
        case SmartList.favorites:
          return t.isFavorite;
        case SmartList.upcoming:
          final due = t.dueDate;
          if (due == null) return false;
          final diff = daysBetween(due, today);
          return diff >= 0 && diff < 7;
        case SmartList.assigned:
          final me = user?.id;
          return me != null && t.assignees.any((a) => a.id == me);
        case SmartList.allTasks:
          return true;
      }
    }).length;
  }

  /// Real projects. Vikunja serves saved filters as pseudo-projects with
  /// negative ids; they are read-only views, not task containers.
  List<VikunjaProject> get writableProjects =>
      projects.where((p) => p.id > 0).toList();

  List<VikunjaProject> get savedFilters =>
      projects.where((p) => p.id < 0).toList();

  /// Vikunja pins favorite projects above the rest; the rest sort A→Z by
  /// title (natural order, so Johnny.Decimal prefixes like 1.2 < 1.10).
  List<VikunjaProject> get sortedProjects {
    final list = [...writableProjects];
    list.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return compareNatural(a.title, b.title);
    });
    return list;
  }

  int countForProject(VikunjaProject project) =>
      _allTasks.where((t) => !t.done && t.projectId == project.id).length;

  int countForTag(VikunjaLabel tag) => _allTasks
      .where((t) => !t.done && t.labels.any((l) => l.id == tag.id))
      .length;

  /// Inside a list, tasks sort A→Z when the user picks it, otherwise by
  /// due date.
  Comparator<VikunjaTask> get _taskCompare =>
      sortMode == SortMode.alphabetical ? _byTitle : _compare;

  static int _compare(VikunjaTask a, VikunjaTask b) {
    if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    return b.id.compareTo(a.id);
  }

  static int _byTitle(VikunjaTask a, VikunjaTask b) {
    if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
    return compareNatural(a.title, b.title);
  }

  /// Projects by id. `projectOf` runs once per task tile, so it reads this
  /// index instead of rescanning [projects]; the index is rebuilt on the first
  /// read after a notification.
  Map<int, VikunjaProject> get projectIndex =>
      _projectIndex ??= {for (final p in projects) p.id: p};

  VikunjaProject? projectOf(VikunjaTask task) => projectIndex[task.projectId];

  // ------------------------------------------------------------- mutation --

  /// Applies [change] to a copy, swaps that copy into the caches, then
  /// persists. A rejected edit is rolled back to the instance the caches held:
  /// `refresh()` cannot be the rollback, it swallows its own errors and leaves
  /// the optimistic edit on screen.
  Future<void> mutate(
    VikunjaTask task,
    void Function(VikunjaTask) change,
  ) async {
    final client = api;
    if (client == null) return;
    if (offline) {
      error = offlineEditError;
      notifyListeners();
      return;
    }
    final original = task;
    final edited = task.copyWith();
    change(edited);
    _replace(edited);
    // One notification for the local edit. The round trip only reports back
    // when the server actually changed something.
    notifyListeners();
    try {
      final saved = await client.updateTask(edited);
      error = null;
      _replace(saved);
      if (saved != edited) notifyListeners();
    } on VikunjaException catch (e) {
      _replace(original);
      error = await _failure(e);
      notifyListeners();
    } finally {
      unawaited(syncHomeWidget(this));
    }
  }

  /// Task by id, from whatever list the app currently holds. The index is built
  /// on the first read after a change, so the per-tile lookups in the list view
  /// do not scan every task each.
  VikunjaTask? taskById(int id) => (_taskIndex ??= {
    ..._fetchedTasks,
    for (final t in _allTasks) t.id: t,
    for (final list in _projectTasks.values)
      for (final t in list) t.id: t,
  })[id];

  /// Tasks fetched one at a time that no visible list holds yet: a detail
  /// screen opened from a notification, or a cold start before the first
  /// refresh. They are the same single source of truth as the lists, just not
  /// part of one; a refreshed list takes over the id when it arrives.
  final Map<int, VikunjaTask> _fetchedTasks = {};

  /// The cached list for [projectId]. Exposed so a test can prove a later
  /// update copies the list instead of editing one already handed out.
  @visibleForTesting
  List<VikunjaTask>? projectTasksForTest(int projectId) =>
      _projectTasks[projectId];

  /// Ids of tasks this app changed locally, oldest first. A refresh that was
  /// already in flight read the server before those changes, so its answer must
  /// not put the old values back on screen.
  final List<int> _localEdits = [];

  /// The locally held version of every task edited after [editMark].
  Map<int, VikunjaTask> _localEditsSince(int editMark) {
    if (editMark >= _localEdits.length) return const {};
    final kept = <int, VikunjaTask>{};
    for (final id in _localEdits.skip(editMark)) {
      final task = taskById(id);
      if (task != null) kept[id] = task;
    }
    return kept;
  }

  void _replace(VikunjaTask fresh) {
    // A change the app holds locally is newer than any read already in flight.
    _localEdits.add(fresh.id);
    if (_localEdits.length > 1000) {
      _localEdits.removeRange(0, _localEdits.length - 500);
    }
    final i = _allTasks.indexWhere((t) => t.id == fresh.id);
    if (i >= 0) {
      _allTasks = List.of(_allTasks)..[i] = fresh;
    }
    final projectList = _projectTasks[fresh.projectId];
    final j = projectList?.indexWhere((t) => t.id == fresh.id) ?? -1;
    // Copy-on-write: a view may still be painting the list it was handed.
    if (j >= 0) {
      _projectTasks[fresh.projectId] = List.of(projectList!)..[j] = fresh;
    }
    if (i < 0 && j < 0) _fetchedTasks[fresh.id] = fresh;
    _taskIndex?[fresh.id] = fresh;
  }

  Future<VikunjaTask?> addTask(String title, {VikunjaProject? project}) async {
    final client = api;
    if (client == null) return null;
    if (offline) {
      error = offlineEditError;
      notifyListeners();
      return null;
    }
    final writable = writableProjects;
    final target =
        project ??
        (selection.project != null && selection.project!.id > 0
            ? selection.project
            : (writable.isNotEmpty ? writable.first : null));
    if (target == null) {
      error = 'Create a list first';
      notifyListeners();
      return null;
    }
    try {
      final tag = selection.tag;
      final created = await client.createTask(target.id, {
        'title': title.trim(),
        'project_id': target.id,
        // Adding while viewing a tag pre-applies it.
        if (tag != null && selection.project == null)
          'labels': [
            {'id': tag.id, 'title': tag.title, 'hex_color': tag.hexColor},
          ],
      });
      _allTasks = [created, ..._allTasks];
      _projectTasks[target.id] = [
        created,
        ...(_projectTasks[target.id] ?? const []),
      ];
      notifyListeners();
      return created;
    } on VikunjaException catch (e) {
      error = await _failure(e);
      notifyListeners();
      return null;
    }
  }

  /// Loads one task with its comments/relations merged into the caches.
  Future<VikunjaTask?> loadTask(int id) async {
    final client = api;
    if (client == null) return null;
    try {
      final fresh = await client.task(id);
      _replace(fresh);
      notifyListeners();
      return fresh;
    } on VikunjaException catch (e) {
      error = await _failure(e);
      notifyListeners();
      return null;
    }
  }

  Future<List<VikunjaTask>> searchTasks(String query) {
    final client = api;
    if (client == null || query.trim().isEmpty) return Future.value(const []);
    return client.allTasks(
      search: query.trim(),
      sortBy: 'done',
      orderBy: 'asc',
    );
  }

  /// Returns the failure message, or null when the task is gone. It does not go
  /// through [error]: that field is shared with the poller.
  Future<String?> deleteTask(VikunjaTask task) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    _allTasks = _allTasks.where((t) => t.id != task.id).toList();
    final projectList = _projectTasks[task.projectId];
    if (projectList != null) {
      _projectTasks[task.projectId] = List.of(projectList)
        ..removeWhere((t) => t.id == task.id);
    }
    notifyListeners();
    try {
      await client.deleteTask(task.id);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      final message = await _failure(e);
      // The row was removed optimistically; put the truth back.
      await refresh();
      notifyListeners();
      return message;
    }
  }

  Future<void> toggleDone(VikunjaTask task) => mutate(task, (t) {
    t.done = !t.done;
    t.doneAt = t.done ? DateTime.now() : null;
    t.percentDone = t.done ? 1 : 0;
  });

  Future<void> toggleImportant(VikunjaTask task) =>
      mutate(task, (t) => t.isFavorite = !t.isFavorite);
  // ------------------------------------------------------- teams & shares --

  Future<String?> createTeam(String name, {String? description}) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final team = await client.createTeam(name, description: description);
      teams = [...teams, team];
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  VikunjaUserSettings get userSettings =>
      user?.settings ?? const VikunjaUserSettings();

  // ------------------------------------------------------------- cache -----

  /// Snapshot writes: encoding the whole workspace on the UI isolate after
  /// every refresh was the most expensive thing a poll did. Identical data is
  /// skipped outright, and a burst of changes coalesces into one write of the
  /// latest payload. The first write still lands immediately — the logout path
  /// and [refresh]'s caller expect the snapshot on disk when it returns.
  static const _cacheWriteWindow = Duration(milliseconds: 200);
  String? _lastCachePayload;
  Map<String, dynamic>? _pendingCache;
  Timer? _cacheFlush;
  DateTime? _lastCacheWriteAt;

  /// How many times the snapshot actually reached the disk.
  @visibleForTesting
  int cacheWrites = 0;

  @override
  void dispose() {
    _disposed = true;
    // Nothing may be left waiting on a restore that will not finish.
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    _cacheFlush?.cancel();
    newTaskRequests.dispose();
    super.dispose();
  }

  Future<void> _saveCache() async {
    if (_cache == null) return;
    final snapshot = <String, dynamic>{
      'user': user?.toJson(),
      'projects': [for (final p in projects) p.toJson()],
      'labels': [for (final l in labels) l.toJson()],
      'teams': [for (final t in teams) t.toJson()],
      'tasks': [for (final t in _allTasks) t.toJson()],
    };
    // `savedAt` is the write's own stamp, so it is not part of the comparison.
    final encoded = jsonEncode(snapshot);
    if (encoded == _lastCachePayload) return;
    _lastCachePayload = encoded;
    snapshot['savedAt'] = DateTime.now().toIso8601String();
    _pendingCache = snapshot;
    final last = _lastCacheWriteAt;
    final since = last == null ? null : DateTime.now().difference(last);
    if (since != null && since < _cacheWriteWindow) {
      _cacheFlush?.cancel();
      _cacheFlush = Timer(
        _cacheWriteWindow - since,
        () => unawaited(_flushCache()),
      );
      return;
    }
    await _flushCache();
  }

  Future<void> _flushCache() async {
    _cacheFlush?.cancel();
    _cacheFlush = null;
    final snapshot = _pendingCache;
    _pendingCache = null;
    if (snapshot == null) return;
    cacheWrites++;
    _lastCacheWriteAt = DateTime.now();
    await _cache?.save(snapshot);
  }

  /// Returns true when a snapshot was applied.
  Future<bool> _loadCache() async {
    final snapshot = await _cache?.load();
    if (snapshot == null) return false;
    try {
      final cachedUser = snapshot['user'];
      if (cachedUser is Map<String, dynamic>) {
        user = user ?? VikunjaUser.fromJson(cachedUser);
      }
      projects = (snapshot['projects'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VikunjaProject.fromJson)
          .toList();
      labels = (snapshot['labels'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VikunjaLabel.fromJson)
          .toList();
      teams = (snapshot['teams'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VikunjaTeam.fromJson)
          .toList();
      _allTasks = (snapshot['tasks'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VikunjaTask.fromJson)
          .toList();
      _projectTasks = {};
      cachedAt = DateTime.tryParse(snapshot['savedAt'] as String? ?? '');
      offline = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------- comments / assignees --

  Future<List<VikunjaComment>> commentsOf(int taskId) async {
    try {
      return await api?.comments(taskId) ?? const [];
    } on VikunjaException catch (e) {
      if (e.isUnauthorized) await _endSession();
      rethrow;
    }
  }

  // ------------------------------------------------------ notifications -----

  List<VikunjaNotification> notifications = const [];

  int get unreadNotifications => notifications.where((n) => !n.isRead).length;

  Future<String?> loadNotifications() async {
    final client = api;
    if (client == null) return null;
    try {
      final fresh = await client.notifications();
      // The 10-minute poll asks whether anything arrived; only a real change is
      // worth a rebuild of the whole task list behind the badge.
      if (!listEquals(fresh, notifications)) {
        notifications = fresh;
        notifyListeners();
      }
      return null;
    } on VikunjaException catch (e) {
      if (e.isUnauthorized) await _endSession();
      return _failure(e);
    }
  }

  Future<String?> markNotificationRead(int id) async {
    if (offline) return offlineEditError;
    try {
      await api?.markNotificationRead(id);
      notifications = [
        for (final n in notifications)
          if (n.id == id)
            VikunjaNotification(
              id: n.id,
              name: n.name,
              created: n.created,
              readAt: DateTime.now(),
              doer: n.doer,
              taskId: n.taskId,
              taskTitle: n.taskTitle,
              projectTitle: n.projectTitle,
              commentText: n.commentText,
              teamTitle: n.teamTitle,
            )
          else
            n,
      ];
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  // ------------------------------------------------------------- kanban ----

  /// Kanban columns by view id, as last loaded or optimistically moved.
  final Map<int, List<VikunjaBucket>> _boardBuckets = {};

  /// Kanban columns as last loaded, or null when the project has no kanban
  /// view. AppState owns them: the board screen renders this, it does not keep
  /// a copy of the server's data in its own State.
  List<VikunjaBucket>? bucketsFor(VikunjaProject project) {
    final viewId = project.kanbanViewId;
    return viewId == null ? null : _boardBuckets[viewId];
  }

  /// Loads the board into the state. Null on success, else a message.
  Future<String?> loadBoard(VikunjaProject project) async {
    final viewId = project.kanbanViewId;
    if (viewId == null) return null;
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      _boardBuckets[viewId] = await client.board(project.id, viewId);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> moveToBucket(
    VikunjaProject project,
    int taskId,
    int bucketId,
  ) async {
    if (offline) return offlineEditError;
    final viewId = project.kanbanViewId;
    if (viewId == null) return 'This project has no kanban view.';
    final before = _boardBuckets[viewId];
    final optimistic = before == null
        ? null
        : _moveInBuckets(before, taskId, bucketId);
    if (optimistic != null) {
      _boardBuckets[viewId] = optimistic;
      notifyListeners();
    }
    try {
      await api?.moveToBucket(project.id, viewId, bucketId, taskId);
      return null;
    } on VikunjaException catch (e) {
      // The card goes back to the column it came from.
      if (before != null) {
        _boardBuckets[viewId] = before;
        notifyListeners();
      }
      return _failure(e);
    }
  }

  /// [buckets] with [taskId] moved to [bucketId], or null when that changes
  /// nothing (unknown bucket, or the task is not on the board).
  static List<VikunjaBucket>? _moveInBuckets(
    List<VikunjaBucket> buckets,
    int taskId,
    int bucketId,
  ) {
    if (!buckets.any((b) => b.id == bucketId)) return null;
    VikunjaTask? moved;
    final stripped = <VikunjaBucket>[];
    for (final bucket in buckets) {
      final keeps = <VikunjaTask>[];
      for (final task in bucket.tasks) {
        if (task.id == taskId) {
          moved = task;
        } else {
          keeps.add(task);
        }
      }
      stripped.add(
        VikunjaBucket(id: bucket.id, title: bucket.title, tasks: keeps),
      );
    }
    final task = moved;
    if (task == null) return null;
    return [
      for (final bucket in stripped)
        if (bucket.id == bucketId)
          VikunjaBucket(
            id: bucket.id,
            title: bucket.title,
            tasks: [...bucket.tasks, task],
          )
        else
          bucket,
    ];
  }

  Future<String?> addComment(int taskId, String text) async {
    if (offline) return offlineEditError;
    try {
      await api?.addComment(taskId, text);
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> deleteComment(int taskId, int commentId) async {
    if (offline) return offlineEditError;
    try {
      await api?.deleteComment(taskId, commentId);
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> assign(VikunjaTask task, VikunjaUser user) async {
    if (offline) return offlineEditError;
    try {
      await api?.addAssignee(task.id, user.id);
      final fresh = await api?.task(task.id);
      if (fresh != null) _replace(fresh);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> unassign(VikunjaTask task, VikunjaUser user) async {
    if (offline) return offlineEditError;
    try {
      await api?.removeAssignee(task.id, user.id);
      final fresh = await api?.task(task.id);
      if (fresh != null) _replace(fresh);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  // ------------------------------------------------------- attachments -----

  Future<List<VikunjaAttachment>> attachmentsOf(int taskId) async {
    try {
      return await api?.attachments(taskId) ?? const [];
    } on VikunjaException catch (e) {
      if (e.isUnauthorized) await _endSession();
      rethrow;
    }
  }

  Future<String?> uploadAttachment(
    int taskId,
    String name,
    List<int> bytes,
  ) async {
    if (offline) return offlineEditError;
    try {
      await api?.uploadAttachment(taskId, name, bytes);
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> deleteAttachment(int taskId, int attachmentId) async {
    if (offline) return offlineEditError;
    try {
      await api?.deleteAttachment(taskId, attachmentId);
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<Uint8List?> downloadAttachment(int taskId, int attachmentId) async {
    try {
      return await api?.downloadAttachment(taskId, attachmentId);
    } on VikunjaException catch (e) {
      error = await _failure(e);
      notifyListeners();
      return null;
    }
  }

  // ---------------------------------------------------------- relations ----

  Future<String?> addRelation(int taskId, int otherTaskId, String kind) async {
    if (offline) return offlineEditError;
    try {
      await api?.addRelation(taskId, otherTaskId, kind);
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> removeRelation(
    int taskId,
    String kind,
    int otherTaskId,
  ) async {
    if (offline) return offlineEditError;
    try {
      await api?.removeRelation(taskId, kind, otherTaskId);
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> createLabel(
    String title, {
    String hexColor = '',
    String description = '',
  }) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final created = await client.createLabel(
        title,
        hexColor: hexColor,
        description: description,
      );
      labels = [...labels, created];
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> updateLabel(
    VikunjaLabel label, {
    required String title,
    String? hexColor,
    String? description,
  }) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final saved = await client.updateLabel(
        label,
        title: title,
        hexColor: hexColor,
        description: description,
      );
      labels = labels.map((l) => l.id == saved.id ? saved : l).toList();
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> deleteLabel(VikunjaLabel label) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      await client.deleteLabel(label.id);
      labels = labels.where((l) => l.id != label.id).toList();
      for (var i = 0; i < _allTasks.length; i++) {
        final t = _allTasks[i];
        if (t.labels.any((l) => l.id == label.id)) {
          _allTasks[i] = t.copyWith(
            labels: t.labels.where((l) => l.id != label.id).toList(),
          );
        }
      }
      if (selection.tag?.id == label.id) {
        selection = const ListSelection.smart(SmartList.allTasks);
      }
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> setTaskLabels(
    VikunjaTask task,
    List<VikunjaLabel> labels,
  ) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      await client.setTaskLabels(task.id, labels);
      final updated = task.copyWith(labels: labels);
      _replace(updated);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> saveUserSettings(VikunjaUserSettings settings) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final refreshed = await client.saveUserSettings(settings);
      // The settings call refreshes the login JWT, which rotates the refresh
      // cookie; persist the rotated value or the next save loses it.
      await _storage.write(key: _kRefresh, value: client.refreshToken);
      user = refreshed;
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> saveTeam(
    VikunjaTeam team, {
    required String name,
    String? description,
  }) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final saved = await client.updateTeam(
        team.id,
        name: name,
        description: description,
      );
      teams = teams.map((t) => t.id == saved.id ? saved : t).toList();
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> deleteTeam(VikunjaTeam team) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      await client.deleteTeam(team.id);
      teams = teams.where((t) => t.id != team.id).toList();
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<void> reloadTeams() async {
    final client = api;
    if (client == null) return;
    try {
      teams = await client.teams();
    } on VikunjaException catch (e) {
      error = await _failure(e);
    }
    notifyListeners();
  }

  Future<List<VikunjaTeamMember>> membersOf(int teamId) async {
    try {
      return await api?.teamMembers(teamId) ?? const [];
    } on VikunjaException catch (e) {
      if (e.isUnauthorized) await _endSession();
      rethrow;
    }
  }

  Future<String?> addTeamMember(int teamId, String username) async {
    if (offline) return offlineEditError;
    try {
      await api?.addTeamMember(teamId, username);
      await reloadTeams();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> removeTeamMember(int teamId, String username) async {
    if (offline) return offlineEditError;
    try {
      await api?.removeTeamMember(teamId, username);
      await reloadTeams();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> toggleTeamMemberAdmin(int teamId, String username) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final members = await client.teamMembers(teamId);
      final admins = members.where((m) => m.admin).length;
      var targetIsAdmin = false;
      for (final member in members) {
        if (member.username == username) targetIsAdmin = member.admin;
      }
      // Demoting the last admin would lock everyone out of team management, so
      // it is refused here, where the member list is, and not in a screen.
      if (targetIsAdmin && admins <= 1) return lastAdminError;
      await client.toggleTeamMemberAdmin(teamId, username);
      await reloadTeams();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<List<VikunjaUser>> searchUsers(String query) async {
    try {
      return await api?.users(query) ?? const [];
    } on VikunjaException catch (e) {
      if (e.isUnauthorized) await _endSession();
      rethrow;
    }
  }

  /// Returns the failure message, or null when the project was saved. It does
  /// not go through [error]: that field belongs to the background poller too,
  /// so a read-back made a successful save look like a failure and a real one
  /// look like a success.
  Future<String?> saveProject(
    VikunjaProject project, {
    String? title,
    String? description,
    String? hexColor,
    String? identifier,
    bool? isFavorite,
    bool? isArchived,
  }) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final saved = await client.updateProject(
        project,
        title: title,
        description: description,
        hexColor: hexColor,
        identifier: identifier,
        isFavorite: isFavorite,
        isArchived: isArchived,
      );
      projects = projects.map((p) => p.id == saved.id ? saved : p).toList();
      if (selection.project?.id == saved.id) {
        selection = ListSelection.project(saved);
      }
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> deleteProject(VikunjaProject project) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      await client.deleteProject(project.id);
      projects = projects.where((p) => p.id != project.id).toList();
      _allTasks = _allTasks.where((t) => t.projectId != project.id).toList();
      if (selection.project?.id == project.id) {
        selection = const ListSelection.smart(SmartList.allTasks);
      }
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<void> refreshShares() async => notifyListeners();

  /// Shares loaded so far, by project id. The screens render this instead of
  /// keeping their own copy of what the server said.
  final Map<int, ProjectShares> _shares = {};

  /// Who [projectId] is shared with, as the state last loaded it.
  ProjectShares sharesOf(int projectId) =>
      _shares[projectId] ?? ProjectShares.empty;

  /// Reads a project's shares into the state. Null on success, else a message.
  Future<String?> projectShares(int projectId) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final results = await Future.wait<Object?>([
        client.projectUsers(projectId),
        client.projectTeams(projectId),
        client.linkShares(projectId),
        client.frontendUrl(),
      ]);
      _shares[projectId] = ProjectShares(
        users: results[0] as List<VikunjaProjectShare>,
        teams: results[1] as List<VikunjaProjectShare>,
        links: results[2] as List<VikunjaLinkShare>,
        frontendUrl: results[3] as String?,
      );
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> addUserShare(
    int projectId,
    String username,
    int permission,
  ) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      await client.addProjectUser(projectId, username, permission);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> addTeamShare(
    int projectId,
    int teamId,
    int permission,
  ) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      await client.addProjectTeam(projectId, teamId, permission);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  /// Removes a user or a team share, whichever is given.
  Future<String?> removeShare(
    int projectId, {
    String? username,
    int? teamId,
  }) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    if (username == null && teamId == null) return 'No share to remove.';
    try {
      if (username != null) {
        await client.removeProjectUser(projectId, username);
      }
      if (teamId != null) await client.removeProjectTeam(projectId, teamId);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> deleteLinkShare(int projectId, int shareId) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      await client.deleteLinkShare(projectId, shareId);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  /// Creates a project and adds it to the state. Null on success, else a
  /// message — a sign-in that ended mid-dialog must not throw at the caller.
  Future<String?> createProject(String title, {String? hexColor}) async {
    if (offline) return offlineEditError;
    final client = api;
    if (client == null) return 'Not signed in';
    try {
      final created = await client.createProject(title, hexColor: hexColor);
      projects = [...projects, created];
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> shareWithTeam(int projectId, int teamId, int permission) =>
      addTeamShare(projectId, teamId, permission);

  Future<String?> createLinkShare(
    int projectId,
    String name,
    int permission, {
    String? password,
  }) async {
    if (offline) return offlineEditError;
    try {
      await api?.createLinkShare(
        projectId,
        name: name,
        permission: permission,
        password: password,
      );
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> setTeamShare(
    int projectId,
    int teamId,
    int permission,
  ) async {
    if (offline) return offlineEditError;
    try {
      await api?.updateProjectTeam(projectId, teamId, permission);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> unshareTeam(int projectId, int teamId) =>
      removeShare(projectId, teamId: teamId);

  Future<String?> shareWithUser(
    int projectId,
    String username,
    int permission,
  ) => addUserShare(projectId, username, permission);

  Future<String?> setUserShare(
    int projectId,
    String username,
    int permission,
  ) async {
    if (offline) return offlineEditError;
    try {
      await api?.updateProjectUser(projectId, username, permission);
      notifyListeners();
      return null;
    } on VikunjaException catch (e) {
      return _failure(e);
    }
  }

  Future<String?> unshareUser(int projectId, String username) =>
      removeShare(projectId, username: username);
}

/// Who one project is shared with: user shares, team shares, link shares and
/// the server's public link base. AppState owns the loaded copy so every widget
/// reads the same data instead of the screen keeping its own snapshot.
@immutable
class ProjectShares {
  const ProjectShares({
    this.users = const [],
    this.teams = const [],
    this.links = const [],
    this.frontendUrl,
  });

  final List<VikunjaProjectShare> users;
  final List<VikunjaProjectShare> teams;
  final List<VikunjaLinkShare> links;
  final String? frontendUrl;

  static const empty = ProjectShares();
}

/// Inherited access to the single [AppState] instance.
///
/// One notifier carries tasks, theme, session and offline flags on purpose:
/// splitting it per concern would touch 39 call sites and every screen, and the
/// app shell already avoids the worst of it via [AppState.shell]. Use [read]
/// anywhere the value is not painted (callbacks, one-shot lookups) so those
/// widgets stop rebuilding on every notification.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  /// Listens: the calling widget rebuilds on every notification.
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }

  /// Does not listen: for `onTap` handlers, `initState` and one-shot reads.
  static AppState read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    assert(element != null, 'AppScope is missing above this widget');
    return (element!.widget as AppScope).notifier!;
  }
}
