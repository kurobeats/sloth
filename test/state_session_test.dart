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

/// A server that answers everything `signIn` + `refresh` read.
http.Client workingServer() => MockClient((request) async {
  final path = request.url.path;
  if (path.endsWith('/info')) return http.Response('{}', 200);
  if (path.endsWith('/login')) {
    return http.Response('{"token":"not-a-jwt"}', 200);
  }
  if (path.endsWith('/routes')) {
    return http.Response('{"message":"not found"}', 404);
  }
  if (path.endsWith('/user')) {
    return http.Response('{"id":1,"username":"me"}', 200);
  }
  if (path.contains('/avatar/')) return http.Response('', 404);
  if (path.endsWith('/projects')) {
    return http.Response('[{"id":1,"title":"Home"}]', 200);
  }
  if (path.endsWith('/tasks')) {
    return http.Response(
      '[{"id":1,"project_id":1,"title":"Secret task"}]',
      200,
    );
  }
  return http.Response('[]', 200);
});

http.Client failingServer(int status) => MockClient(
  (request) async =>
      http.Response('{"message":"Wrong password","code":$status}', status),
);

/// Records `close()`: the http client `signIn`/`restore` build must not leak
/// when the connect fails.
class RecordingClient extends http.BaseClient {
  RecordingClient(this.status);

  final int status;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(
          utf8.encode('{"message":"Wrong password","code":$status}'),
        ),
        status,
      );

  @override
  void close() => closed = true;
}

AppState stateFor(http.Client client) =>
    AppState()
      ..clientFactory = (String base, {bool allowSelfSigned = false}) =>
          VikunjaApi(
            baseUrl: base,
            allowSelfSigned: allowSelfSigned,
            client: client,
          );

Future<AppState> signedIn() async {
  final state = stateFor(workingServer());
  await state.signIn(server: _server, username: 'me', password: 'pw');
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('signing out wipes the offline snapshot on disk', () async {
    final state = await signedIn();
    final cache = OfflineCache(key: _cacheKey);
    final snapshot = await cache.load();
    expect(snapshot, isNotNull, reason: 'the fixture wrote a snapshot');
    expect(
      (snapshot!['tasks'] as List).single['title'],
      'Secret task',
      reason: 'the workspace is on disk before the logout',
    );

    await state.signOut();

    expect(await cache.load(), isNull, reason: 'the snapshot must be gone');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where(
        (key) => (prefs.getString(key) ?? '').contains('Secret task'),
      ),
      isEmpty,
      reason: 'no task title may survive a logout',
    );
  });

  test('a 401 during refresh signs out and wipes the snapshot', () async {
    final state = await signedIn();
    final cache = OfflineCache(key: _cacheKey);
    expect(await cache.load(), isNotNull);

    state.api = VikunjaApi(
      baseUrl: _server,
      client: failingServer(401),
    );
    await state.refresh();

    expect(state.isSignedIn, isFalse, reason: 'the session ended');
    expect(await cache.load(), isNull);
  });

  test('a failed sign-in closes the client it built', () async {
    final recorder = RecordingClient(401);
    final state = stateFor(recorder);

    await state.signIn(
      server: _server,
      username: 'me',
      password: 'nope',
    );

    expect(state.error, 'Wrong password');
    expect(recorder.closed, isTrue, reason: 'the client leaked');
  });

  test('a failed restore closes the client it built', () async {
    FlutterSecureStorage.setMockInitialValues({
      'vikunja_base': _server,
      'vikunja_token': 'stale',
    });
    final recorder = RecordingClient(500);
    final state = stateFor(recorder);

    await state.restore();

    expect(state.isSignedIn, isFalse);
    expect(recorder.closed, isTrue, reason: 'the client leaked');
  });
}
