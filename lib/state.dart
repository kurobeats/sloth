import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'models.dart';
import 'todo_theme.dart';

enum SmartList {
  // Names follow Vikunja's vocabulary: Favorite tasks, Upcoming, Assignees.
  dueToday('Due Today'),
  favorites('Favorites'),
  upcoming('Upcoming'),
  allTasks('All Tasks'),
  assigned('Assigned to Me');

  const SmartList(this.label);

  final String label;
}

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

  String get key => tag != null
      ? 'tag:${tag!.id}'
      : smart != null
          ? 'smart:${smart!.name}'
          : 'project:${project!.id}';

  @override
  bool operator ==(Object other) =>
      other is ListSelection && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class AppState extends ChangeNotifier {
  AppState({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kBase = 'vikunja_base';
  static const _kToken = 'vikunja_token';
  static const _kAllowSelfSigned = 'vikunja_allow_self_signed';
  static const _kLightTheme = 'theme_light';
  static const _kDarkTheme = 'theme_dark';
  static const _kThemeMode = 'theme_mode';

  final FlutterSecureStorage _storage;

  VikunjaApi? api;
  VikunjaUser? user;
  String? baseUrl;
  Uint8List? avatar;
  bool allowSelfSigned = false;

  List<VikunjaProject> projects = const [];
  List<VikunjaLabel> labels = const [];
  List<VikunjaTask> _allTasks = const [];
  Map<int, List<VikunjaTask>> _projectTasks = {};

  ListSelection selection = const ListSelection.smart(SmartList.dueToday);

  bool restoring = true;
  bool loading = false;
  String? error;

  // ------------------------------------------------------------ appearance --

  String lightThemeId = TodoColors.defaultLight.id;
  String darkThemeId = TodoColors.defaultDark.id;
  ThemeMode themeMode = ThemeMode.system;

  TodoColors get lightTheme => TodoColors.byId(lightThemeId, Brightness.light);
  TodoColors get darkTheme => TodoColors.byId(darkThemeId, Brightness.dark);

  Future<void> loadAppearance() async {
    try {
      lightThemeId =
          await _storage.read(key: _kLightTheme) ?? TodoColors.defaultLight.id;
      darkThemeId =
          await _storage.read(key: _kDarkTheme) ?? TodoColors.defaultDark.id;
      themeMode = switch (await _storage.read(key: _kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Storage unavailable: fall back to the defaults above.
    }
    notifyListeners();
  }

  Future<void> setLightTheme(String id) async {
    lightThemeId = id;
    notifyListeners();
    await _storage.write(key: _kLightTheme, value: id);
  }

  Future<void> setDarkTheme(String id) async {
    darkThemeId = id;
    notifyListeners();
    await _storage.write(key: _kDarkTheme, value: id);
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
  }

  bool get isSignedIn => api != null && user != null;

  // ---------------------------------------------------------------- boot ----

  Future<void> restore() async {
    await loadAppearance();
    try {
      final base = await _storage.read(key: _kBase);
      final token = await _storage.read(key: _kToken);
      final allowBadCert =
          (await _storage.read(key: _kAllowSelfSigned)) == 'true';
      if (base != null && token != null && token.isNotEmpty) {
        await _connect(
          VikunjaApi(baseUrl: base, allowSelfSigned: allowBadCert)..token = token,
          persist: false,
        );
        await refresh();
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
    final client = VikunjaApi(baseUrl: server, allowSelfSigned: allowBadCert);
    try {
      await client.info(); // fail fast on a wrong URL
      await client.login(username, password);
      await _connect(client, persist: true);
      await refresh();
    } on VikunjaException catch (e) {
      api = null;
      user = null;
      error = e.message;
    } catch (e) {
      api = null;
      user = null;
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _connect(VikunjaApi client, {required bool persist}) async {
    final me = await client.currentUser();
    api?.close();
    api = client;
    user = me;
    baseUrl = client.baseUrl;
    avatar = await client.avatar(me.username);
    allowSelfSigned = client.allowSelfSigned;
    if (persist) {
      await _storage.write(key: _kBase, value: client.baseUrl);
      await _storage.write(key: _kToken, value: client.token);
      await _storage.write(
        key: _kAllowSelfSigned,
        value: client.allowSelfSigned.toString(),
      );
    }
  }

  Future<void> signOut() async {
    api?.close();
    api = null;
    user = null;
    projects = const [];
    labels = const [];
    avatar = null;
    _allTasks = const [];
    _projectTasks = {};
    selection = const ListSelection.smart(SmartList.dueToday);
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kAllowSelfSigned);
    notifyListeners();
  }

  // ---------------------------------------------------------------- data ----

  Future<void> refresh() async {
    final client = api;
    if (client == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        client.projects(),
        client.allTasks(sortBy: 'due_date', orderBy: 'asc'),
        client.labels(),
      ]);
      projects = results[0] as List<VikunjaProject>;
      _allTasks = results[1] as List<VikunjaTask>;
      labels = results[2] as List<VikunjaLabel>;
      _projectTasks = {};
      if (selection.project != null) {
        await _loadProjectTasks();
      }
    } on VikunjaException catch (e) {
      error = e.message;
      if (e.isUnauthorized) await signOut();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

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
        error = e.message;
      } finally {
        loading = false;
        notifyListeners();
      }
    }
  }

  // ------------------------------------------------------- derived views ----

  List<VikunjaTask> get _source => selection.project != null
      ? (_projectTasks[selection.project!.id] ?? const [])
      : _allTasks;

  /// Whether a task belongs to the current list, ignoring its done state.
  bool _matchesList(VikunjaTask t) {
    final tag = selection.tag;
    if (tag != null) return t.labels.any((l) => l.id == tag.id);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (selection.smart) {
      case SmartList.dueToday:
        final due = t.dueDate;
        if (due == null) return false;
        return DateTime(due.year, due.month, due.day)
            .isBefore(today.add(const Duration(days: 1)));
      case SmartList.favorites:
        return t.isFavorite;
      case SmartList.upcoming:
        return t.dueDate != null;
      case SmartList.assigned:
        final me = user?.id;
        return me != null && t.assignees.any((a) => a.id == me);
      case SmartList.allTasks:
      case null:
        return true;
    }
  }

  List<VikunjaTask> get openTasks {
    final list = _source.where((t) => !t.done && _matchesList(t)).toList();
    list.sort(_compare);
    return list;
  }

  List<VikunjaTask> get completedTasks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Smart lists show recent completions only; project and tag views show all.
    final cutoff = switch (selection.smart) {
      SmartList.dueToday => today,
      null => null,
      _ => today.subtract(const Duration(days: 7)),
    };
    final list = _source.where((t) {
      if (!t.done || !_matchesList(t)) return false;
      if (cutoff == null) return true;
      final at = t.doneAt;
      return at != null && !at.isBefore(cutoff);
    }).toList();
    list.sort((a, b) => (b.doneAt ?? DateTime(2000)).compareTo(a.doneAt ?? DateTime(2000)));
    return list;
  }

  int countFor(SmartList smart) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _allTasks.where((t) {
      if (t.done) return false;
      switch (smart) {
        case SmartList.dueToday:
          final due = t.dueDate;
          if (due == null) return false;
          return DateTime(due.year, due.month, due.day)
              .isBefore(today.add(const Duration(days: 1)));
        case SmartList.favorites:
          return t.isFavorite;
        case SmartList.upcoming:
          return t.dueDate != null;
        case SmartList.assigned:
          final me = user?.id;
          return me != null && t.assignees.any((a) => a.id == me);
        case SmartList.allTasks:
          return true;
      }
    }).length;
  }

  int countForProject(VikunjaProject project) => _allTasks
      .where((t) => !t.done && t.projectId == project.id)
      .length;

  int countForTag(VikunjaLabel tag) => _allTasks
      .where((t) => !t.done && t.labels.any((l) => l.id == tag.id))
      .length;

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

  VikunjaProject? projectOf(VikunjaTask task) {
    for (final p in projects) {
      if (p.id == task.projectId) return p;
    }
    return null;
  }

  // ------------------------------------------------------------- mutation --

  /// Applies [change] locally, then persists. Rolls back on failure.
  Future<void> mutate(VikunjaTask task, void Function(VikunjaTask) change) async {
    final client = api;
    if (client == null) return;
    change(task);
    notifyListeners();
    try {
      final saved = await client.updateTask(task);
      _replace(saved);
      error = null;
    } on VikunjaException catch (e) {
      error = e.message;
      await refresh();
    } finally {
      notifyListeners();
    }
  }

  void _replace(VikunjaTask fresh) {
    final i = _allTasks.indexWhere((t) => t.id == fresh.id);
    if (i >= 0) {
      _allTasks = List.of(_allTasks)..[i] = fresh;
    }
    final projectList = _projectTasks[fresh.projectId];
    if (projectList != null) {
      final j = projectList.indexWhere((t) => t.id == fresh.id);
      if (j >= 0) projectList[j] = fresh;
    }
  }

  Future<VikunjaTask?> addTask(String title, {VikunjaProject? project}) async {
    final client = api;
    if (client == null) return null;
    final target = project ?? selection.project ??
        (projects.length == 1 ? projects.first : (projects.isNotEmpty ? projects.first : null));
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
      _projectTasks[target.id] = [created, ...(_projectTasks[target.id] ?? const [])];
      notifyListeners();
      return created;
    } on VikunjaException catch (e) {
      error = e.message;
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
      error = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<List<VikunjaTask>> searchTasks(String query) {
    final client = api;
    if (client == null || query.trim().isEmpty) return Future.value(const []);
    return client.allTasks(search: query.trim(), sortBy: 'done', orderBy: 'asc');
  }

  Future<void> deleteTask(VikunjaTask task) async {
    final client = api;
    if (client == null) return;
    _allTasks = _allTasks.where((t) => t.id != task.id).toList();
    _projectTasks[task.projectId]?.removeWhere((t) => t.id == task.id);
    notifyListeners();
    try {
      await client.deleteTask(task.id);
    } on VikunjaException catch (e) {
      error = e.message;
      await refresh();
    }
    notifyListeners();
  }

  Future<void> toggleDone(VikunjaTask task) => mutate(task, (t) {
    t.done = !t.done;
    t.doneAt = t.done ? DateTime.now() : null;
    t.percentDone = t.done ? 1 : 0;
  });

  Future<void> toggleImportant(VikunjaTask task) =>
      mutate(task, (t) => t.isFavorite = !t.isFavorite);
}

/// Inherited access to the single [AppState] instance.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }
}
