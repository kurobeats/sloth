import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sloth/api.dart';
import 'package:sloth/offline_cache.dart';
import 'package:sloth/state.dart';

const _server = 'https://tasks.example.com';
const _cacheKey = 'cache:$_server';
const _secretTitle = 'Buy the surprise gift';
const _secretEmail = 'priya@example.com';

/// The snapshot is the whole workspace: task text, project descriptions and
/// team members with their emails. Plain JSON in SharedPreferences put all of
/// it on disk in the clear, so it now lives in the platform's secure store
/// under the same per-server key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> snapshot() => {
    'user': {'id': 1, 'username': 'me'},
    'projects': [
      {'id': 1, 'title': 'Home', 'description': 'Gifts for the family'},
    ],
    'labels': const [],
    'teams': [
      {
        'id': 4,
        'name': 'Household',
        'members': [
          {'id': 2, 'username': 'priya', 'email': _secretEmail},
        ],
      },
    ],
    'tasks': [
      {'id': 7, 'project_id': 1, 'title': _secretTitle},
    ],
    'savedAt': '2026-10-26T10:00:00.000',
  };

  Future<List<String>> plaintextPrefValues() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      for (final key in prefs.getKeys())
        ...?prefs.get(key) == null ? null : ['${prefs.get(key)}'],
    ];
  }

  test('the snapshot never reaches the plaintext preferences store', () async {
    await OfflineCache(key: _cacheKey).save(snapshot());

    final stored = await plaintextPrefValues();
    expect(
      stored.where(
        (value) => value.contains(_secretTitle) || value.contains(_secretEmail),
      ),
      isEmpty,
      reason:
          'a task title or an email left in SharedPreferences is readable '
          'by anyone with the backup file',
    );
    expect(
      stored.where((value) => value.contains('Gifts for the family')),
      isEmpty,
      reason: 'project descriptions are workspace data too',
    );
  });

  test('the snapshot lives in the secure store instead', () async {
    await OfflineCache(key: _cacheKey).save(snapshot());

    final secure = await const FlutterSecureStorage().read(key: _cacheKey);
    expect(secure, isNotNull, reason: 'the payload moved, it did not vanish');
    expect(secure, contains(_secretTitle));
    expect(secure, contains(_secretEmail));
  });

  test('load returns the same structured data', () async {
    await OfflineCache(key: _cacheKey).save(snapshot());

    final loaded = await OfflineCache(key: _cacheKey).load();

    expect(loaded, isNotNull);
    expect((loaded!['tasks'] as List).single['title'], _secretTitle);
    expect(
      (loaded['projects'] as List).single['description'],
      'Gifts for the family',
    );
    expect(
      ((loaded['teams'] as List).single['members'] as List).single['email'],
      _secretEmail,
    );
  });

  test('a cleared cache reads back as absent', () async {
    final cache = OfflineCache(key: _cacheKey);
    await cache.save(snapshot());
    expect(await cache.load(), isNotNull);

    await cache.clear();

    expect(await cache.load(), isNull);
    expect(await const FlutterSecureStorage().read(key: _cacheKey), isNull);
  });

  test(
    'a signed-in session writes its snapshot to the secure store only',
    () async {
      final state = AppState()
        ..clientFactory = (String base, {bool allowSelfSigned = false}) =>
            VikunjaApi(
              baseUrl: base,
              client: MockClient((request) async {
                final path = request.url.path;
                if (path.endsWith('/info')) return http.Response('{}', 200);
                if (path.endsWith('/login')) {
                  return http.Response('{"token":"not-a-jwt"}', 200);
                }
                if (path.endsWith('/routes')) return http.Response('{}', 404);
                if (path.endsWith('/user')) {
                  return http.Response('{"id":1,"username":"me"}', 200);
                }
                if (path.contains('/avatar/')) return http.Response('', 404);
                if (path.endsWith('/teams')) {
                  return http.Response(
                    jsonEncode([
                      {
                        'id': 4,
                        'name': 'Household',
                        'members': [
                          {'id': 2, 'username': 'priya', 'email': _secretEmail},
                        ],
                      },
                    ]),
                    200,
                  );
                }
                if (path.endsWith('/tasks')) {
                  return http.Response(
                    jsonEncode([
                      {'id': 7, 'project_id': 1, 'title': _secretTitle},
                    ]),
                    200,
                  );
                }
                return http.Response('[]', 200);
              }),
            );

      await state.signIn(server: _server, username: 'me', password: 'pw');

      final stored = await plaintextPrefValues();
      expect(
        stored.where(
          (v) => v.contains(_secretTitle) || v.contains(_secretEmail),
        ),
        isEmpty,
        reason: 'the refresh snapshot must not land in SharedPreferences',
      );
      final snapshot = await OfflineCache(key: 'cache:$_server').load();
      expect(
        (snapshot?['tasks'] as List?)?.single['title'],
        _secretTitle,
        reason: 'the cache still holds the workspace',
      );
    },
  );
}
