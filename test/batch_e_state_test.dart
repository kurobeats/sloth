import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/offline_cache.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

const _server = 'https://tasks.example.com';

/// Records reads/writes and how many were in flight at once: the boot path and
/// the connection both ran their storage work one call after another.
class RecordingStorage extends FlutterSecureStorage {
  RecordingStorage([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;
  int readsInFlight = 0;
  int maxReadsInFlight = 0;
  int writesInFlight = 0;
  int maxWritesInFlight = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readsInFlight++;
    if (readsInFlight > maxReadsInFlight) maxReadsInFlight = readsInFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return values[key];
    } finally {
      readsInFlight--;
    }
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writesInFlight++;
    if (writesInFlight > maxWritesInFlight) maxWritesInFlight = writesInFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
    } finally {
      writesInFlight--;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

Map<String, dynamic> taskJson(
  int id, {
  int projectId = 1,
  String? title,
  DateTime? due,
}) => {
  'id': id,
  'project_id': projectId,
  'title': title ?? 'Task $id',
  if (due != null) 'due_date': due.toUtc().toIso8601String(),
};

/// Counts the requests the state makes, so a duplicated fetch is visible.
class CountingApi {
  CountingApi(this.tasks, {this.projects = const []});

  List<Map<String, dynamic>> tasks;
  List<Map<String, dynamic>> projects;
  List<Map<String, dynamic>> notifications = const [];
  final List<String> requests = [];

  int get viewRequests =>
      requests.where((r) => r.contains('/views/')).length;

  VikunjaApi get api => VikunjaApi(
    baseUrl: _server,
    client: MockClient((request) async {
      final path = request.url.path;
      requests.add('${request.method} $path');
      if (path.endsWith('/info')) return http.Response('{}', 200);
      if (path.endsWith('/login')) {
        return http.Response('{"token":"not-a-jwt"}', 200);
      }
      if (path.endsWith('/user')) {
        return http.Response('{"id":1,"username":"me"}', 200);
      }
      if (path.endsWith('/notifications')) {
        return http.Response(jsonEncode(notifications), 200);
      }
      if (path.contains('/avatar/')) return http.Response('', 404);
      if (path.contains('/views/')) {
        final projectId = int.parse(path.split('/projects/')[1].split('/')[0]);
        return http.Response(
          jsonEncode(tasks.where((t) => t['project_id'] == projectId).toList()),
          200,
        );
      }
      if (request.method == 'GET' && path.endsWith('/tasks')) {
        return http.Response(jsonEncode(tasks), 200);
      }
      if (request.method == 'GET' && path.endsWith('/projects')) {
        return http.Response(jsonEncode(projects), 200);
      }
      if (request.method == 'PUT' && path.endsWith('/tasks')) {
        return http.Response(request.body, 200);
      }
      if (request.method == 'POST' && path.contains('/tasks/')) {
        return http.Response(request.body, 200);
      }
      return http.Response('[]', 200);
    }),
  );
}

Future<AppState> stateWith(CountingApi source) async {
  final state = AppState();
  state.api = source.api;
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

final _home = <String, dynamic>{
  'id': 1,
  'title': 'Home',
  'views': [
    {'id': 10, 'title': 'List', 'view_kind': 'list'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('F-047 storage options', () {
    test('the session keychain item stays on this device', () {
      final options = AppState.storageOptions;
      expect(
        options.iOptions.accessibility,
        KeychainAccessibility.first_unlock_this_device,
        reason: 'a default item migrates to a new device via a backup',
      );
      // v11 has no `encryptedSharedPreferences` flag: the Android side always
      // uses Keystore-wrapped AES-GCM, so the options are explicit but equal.
      expect(options.aOptions, isA<AndroidOptions>());
    });
  });

  group('F-027 boot reads', () {
    test('the appearance reads overlap', () async {
      final storage = RecordingStorage({
        'theme_light': TodoColors.patinaLight.id,
        'theme_dark': TodoColors.catppuccinMocha.id,
        'theme_mode': 'dark',
        'vikunja_allow_self_signed': 'true',
      });
      final state = AppState(storage: storage);

      await state.loadAppearance();

      expect(
        storage.maxReadsInFlight,
        greaterThan(1),
        reason: 'four independent keys must not queue',
      );
      expect(state.lightThemeId, TodoColors.patinaLight.id);
      expect(state.darkThemeId, TodoColors.catppuccinMocha.id);
      expect(state.themeMode, ThemeMode.dark);
      expect(state.allowSelfSigned, isTrue);
    });

    test('the restore reads overlap too', () async {
      final storage = RecordingStorage({'vikunja_base': _server});
      final state = AppState(storage: storage);

      await state.restore();

      expect(storage.maxReadsInFlight, greaterThan(1));
      expect(state.lastServer, _server);
      expect(state.restoring, isFalse);
    });
  });

  group('F-028 connect', () {
    test('a slow avatar does not hold up the session', () async {
      final release = Completer<void>();
      final storage = RecordingStorage();
      var avatarRequested = false;
      final state = AppState(storage: storage)
        ..clientFactory = (String base, {bool allowSelfSigned = false}) =>
            VikunjaApi(
              baseUrl: base,
              allowSelfSigned: allowSelfSigned,
              client: MockClient((request) async {
                final path = request.url.path;
                if (path.endsWith('/info')) return http.Response('{}', 200);
                if (path.endsWith('/login')) {
                  return http.Response('{"token":"not-a-jwt"}', 200);
                }
                if (path.endsWith('/user')) {
                  return http.Response('{"id":1,"username":"me"}', 200);
                }
                if (path.contains('/avatar/')) {
                  avatarRequested = true;
                  await release.future;
                  return http.Response.bytes(const [1, 2, 3], 200);
                }
                return http.Response('[]', 200);
              }),
            );

      await state
          .signIn(server: _server, username: 'me', password: 'pw')
          .timeout(const Duration(seconds: 5));

      expect(avatarRequested, isTrue, reason: 'the fetch still happens');
      expect(
        state.avatar,
        isNull,
        reason: 'first paint must not wait for the avatar',
      );
      expect(state.isSignedIn, isTrue);
      expect(
        storage.maxWritesInFlight,
        greaterThan(1),
        reason: 'the three session writes are independent',
      );

      release.complete();
      for (var i = 0; i < 100 && state.avatar == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(state.avatar, isNotNull, reason: 'the avatar still lands');
    });
  });

  group('F-026 project tasks', () {
    test('a refresh with a selection does not refetch the view', () async {
      final source = CountingApi([
        taskJson(1, projectId: 1, title: 'Home task', due: DateTime(2026, 10, 26)),
        taskJson(2, projectId: 2, title: 'Work task', due: DateTime(2026, 10, 24)),
        taskJson(3, projectId: 1, title: 'Home later', due: DateTime(2026, 10, 27)),
      ], projects: [
        _home,
        {'id': 2, 'title': 'Work'},
      ]);
      final state = await stateWith(source);
      const project = VikunjaProject(
        id: 1,
        title: 'Home',
        views: [VikunjaView(id: 10, title: 'List', viewKind: 'list')],
      );
      await state.select(const ListSelection.project(project));
      final selected = state.openTasks.map((t) => t.id).toList();
      expect(selected, [1, 3]);

      source.requests.clear();
      await state.refresh();

      expect(
        source.viewRequests,
        0,
        reason: 'the project tasks are already in _allTasks',
      );
      expect(
        state.openTasks.map((t) => t.id),
        selected,
        reason: 'the derived list is the one the view returned',
      );
    });
  });

  group('F-031 mutate', () {
    test('a successful mutation notifies once', () async {
      final source = CountingApi([taskJson(1, title: 'Buy milk')]);
      final state = await stateWith(source);
      var events = 0;
      state.addListener(() => events++);

      await state.mutate(state.taskById(1)!, (t) => t.title = 'Buy oat milk');

      expect(state.taskById(1)!.title, 'Buy oat milk');
      expect(events, 1, reason: 'optimistic paint only; the echo matches');
    });
  });

  group('F-065 taskById', () {
    test('the index follows add, update and remove', () async {
      final source = CountingApi([taskJson(1, title: 'Buy milk')]);
      final state = await stateWith(source);
      const project = VikunjaProject(id: 1, title: 'Home');

      final task = state.taskById(1);
      expect(task, isNotNull);
      expect(
        identical(task, state.taskById(1)),
        isTrue,
        reason: 'lookup returns the cached instance',
      );

      await state.mutate(task!, (t) => t.title = 'Buy oat milk');
      expect(state.taskById(1)!.title, 'Buy oat milk');

      final created = await state.addTask('New one', project: project);
      expect(created, isNotNull);
      expect(identical(state.taskById(created!.id), created), isTrue);

      await state.deleteTask(state.taskById(1)!);
      expect(state.taskById(1), isNull);
      expect(state.taskById(created.id), isNotNull);
    });
  });

  group('F-066 poll notifications', () {
    test('an unchanged poll does not notify', () async {
      final source = CountingApi([taskJson(1)]);
      final state = await stateWith(source);
      var events = 0;
      state.addListener(() => events++);

      source.notifications = [
        {'id': 1, 'name': 'task.assigned', 'notification': {'task': {}}},
      ];
      expect(await state.loadNotifications(), isNull);
      expect(events, 1, reason: 'the first fetch is a change');

      await state.loadNotifications();
      await state.loadNotifications();
      expect(
        events,
        1,
        reason: 'the ten-minute poll runs whether or not anything arrived',
      );

      source.notifications = [
        ...source.notifications,
        {'id': 2, 'name': 'task.comment', 'notification': {'task': {}}},
      ];
      await state.loadNotifications();
      expect(events, 2, reason: 'a real change still reaches the UI');
    });
  });

  group('F-029 cache writes', () {
    Future<CacheState> signedIn() async {
      final source = CountingApi([taskJson(1, title: 'first')]);
      final client = source.api;
      final state = CacheState()
        ..source = source
        ..clientFactory = (String base, {bool allowSelfSigned = false}) =>
            client;
      await state.signIn(server: _server, username: 'me', password: 'pw');
      return state;
    }

    Future<Object?> savedTitle() async {
      final snapshot = await OfflineCache(key: 'cache:$_server').load();
      return (snapshot?['tasks'] as List?)?.single['title'];
    }

    test('an unchanged refresh does not rewrite the snapshot', () async {
      final state = await signedIn();
      final writes = state.cacheWrites;
      expect(writes, greaterThan(0), reason: 'the fixture has a snapshot');
      expect(await savedTitle(), 'first');

      await Future<void>.delayed(const Duration(milliseconds: 250));
      await state.refresh();

      expect(
        state.cacheWrites,
        writes,
        reason: 'the same workspace: encoding it again buys nothing',
      );
      expect(await savedTitle(), 'first');
    });

    test('a change is written again', () async {
      final state = await signedIn();
      final writes = state.cacheWrites;

      state.source!.tasks = [taskJson(1, title: 'second')];
      await state.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(state.cacheWrites, greaterThan(writes));
      expect(await savedTitle(), 'second');
    });

    test('a burst of changes ends with the last payload persisted', () async {
      final state = await signedIn();
      final writes = state.cacheWrites;

      for (final title in ['one', 'two', 'three']) {
        state.source!.tasks = [taskJson(1, title: title)];
        await state.refresh();
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(await savedTitle(), 'three', reason: 'the last state wins');
      expect(
        state.cacheWrites - writes,
        lessThanOrEqualTo(3),
        reason: 'a burst coalesces instead of writing once per refresh',
      );
    });
  });

  group('F-087 handed-out task lists', () {
    test('a later update does not edit a list already handed out', () async {
      final source = CountingApi([
        taskJson(1, projectId: 1, title: 'Home task'),
      ], projects: [
        _home,
      ]);
      final state = await stateWith(source);
      const project = VikunjaProject(
        id: 1,
        title: 'Home',
        views: [VikunjaView(id: 10, title: 'List', viewKind: 'list')],
      );
      await state.select(const ListSelection.project(project));

      final handedOut = state.projectTasksForTest(1);
      expect(handedOut, isNotNull);
      expect(handedOut!.single.title, 'Home task');

      await state.mutate(state.taskById(1)!, (t) => t.title = 'Changed');

      expect(
        handedOut.single.title,
        'Home task',
        reason: 'the list the view holds is copy-on-write',
      );
      expect(state.projectTasksForTest(1)!.single.title, 'Changed');
    });

    test('a project left with an empty cached list is refetched', () async {
      final source = CountingApi([
        taskJson(1, projectId: 1, title: 'Home task'),
      ], projects: [_home]);
      final state = await stateWith(source);
      const project = VikunjaProject(
        id: 1,
        title: 'Home',
        views: [VikunjaView(id: 10, title: 'List', viewKind: 'list')],
      );
      await state.select(const ListSelection.project(project));
      // A move can empty a bucket between two visits; the project must then be
      // asked again instead of showing an empty list the server does not have.
      await state.mutate(state.taskById(1)!, (t) => t.projectId = 2);
      expect(state.projectTasksForTest(1), isEmpty);
      final before = source.viewRequests;

      await state.select(const ListSelection.project(project));

      expect(source.viewRequests, before + 1);
      expect(state.projectTasksForTest(1), hasLength(1));
    });

    test('a moved task leaves the list of the project it came from', () async {
      final source = CountingApi([
        taskJson(1, projectId: 1, title: 'Home task'),
      ], projects: [
        _home,
        {
          'id': 2,
          'title': 'Work',
          'views': [
            {'id': 20, 'title': 'List', 'view_kind': 'list'},
          ],
        },
      ]);
      final state = await stateWith(source);
      const project = VikunjaProject(
        id: 1,
        title: 'Home',
        views: [VikunjaView(id: 10, title: 'List', viewKind: 'list')],
      );
      await state.select(const ListSelection.project(project));
      expect(state.projectTasksForTest(1), hasLength(1));

      await state.mutate(state.taskById(1)!, (t) => t.projectId = 2);

      expect(state.taskById(1)!.projectId, 2);
      expect(
        state.projectTasksForTest(1),
        isEmpty,
        reason: 'the old project must not keep showing a task that left it',
      );
    });
  });

  group('offline restore', () {
    test('keeps the cached workspace readable with no network', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = RecordingStorage();
      final online = CacheState(storage: storage)
        ..source = CountingApi([taskJson(1, title: 'cached task')]);
      final client = online.source!.api;
      online.clientFactory = (String base, {bool allowSelfSigned = false}) =>
          client;
      await online.signIn(server: _server, username: 'me', password: 'pw');
      expect(online.isSignedIn, isTrue, reason: 'the fixture signs in');

      final offline = CacheState(storage: storage)
        ..clientFactory = (String base, {bool allowSelfSigned = false}) =>
            VikunjaApi(
              baseUrl: base,
              client: MockClient(
                (request) async => throw http.ClientException(
                  'Connection refused',
                  request.url,
                ),
              ),
            );
      await offline.restore();

      expect(offline.offline, isTrue, reason: 'the network is down');
      expect(
        offline.isSignedIn,
        isTrue,
        reason: 'the snapshot is the session while offline',
      );
      expect(
        offline.allTasksForWidget.map((t) => t.title),
        contains('cached task'),
        reason: 'the cached list is what the user sees',
      );
    });
  });
}

/// An [AppState] that keeps the fake server around for the next refresh.
class CacheState extends AppState {
  CacheState({super.storage});

  CountingApi? source;
}
