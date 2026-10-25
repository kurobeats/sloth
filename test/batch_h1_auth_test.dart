import 'dart:async';
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

/// A server that can start answering 401, and can hold a request open so two
/// screens can be caught with a dead token at the same moment.
class Server {
  int status = 200;
  Completer<void>? gate;
  final List<String> requests = [];

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    final held = gate;
    if (held != null) await held.future;
    if (status != 200) {
      return http.Response(
        jsonEncode({'message': 'Unauthorized', 'code': status}),
        status,
      );
    }
    if (path.endsWith('/info')) return http.Response('{}', 200);
    if (path.endsWith('/login')) {
      return http.Response('{"token":"not-a-jwt"}', 200);
    }
    if (path.endsWith('/routes')) return http.Response('{}', 404);
    if (path.endsWith('/user')) {
      return http.Response('{"id":1,"username":"me"}', 200);
    }
    if (path.contains('/avatar/')) return http.Response('', 404);
    if (path.endsWith('/tasks')) {
      return http.Response(
        '[{"id":1,"project_id":1,"title":"Secret task"}]',
        200,
      );
    }
    return http.Response('[]', 200);
  });

  AppState state() => AppState()
    ..clientFactory = (String base, {bool allowSelfSigned = false}) =>
        VikunjaApi(
          baseUrl: base,
          allowSelfSigned: allowSelfSigned,
          client: client(),
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppState> signedIn(Server server) async {
    final state = server.state();
    await state.signIn(server: _server, username: 'me', password: 'pw');
    expect(state.isSignedIn, isTrue, reason: 'the fixture signed in');
    return state;
  }

  test('a 401 from a write path ends the session once', () async {
    final server = Server();
    final state = await signedIn(server);
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'vikunja_token'), isNotNull);
    expect(await OfflineCache(key: 'cache:$_server').load(), isNotNull);

    server.status = 401;
    final error = await state.addComment(1, 'hello');

    expect(error, AppState.sessionExpiredError);
    expect(state.error, AppState.sessionExpiredError);
    expect(state.isSignedIn, isFalse, reason: 'the stale token is not reused');
    expect(await secure.read(key: 'vikunja_token'), isNull);
    expect(
      await OfflineCache(key: 'cache:$_server').load(),
      isNull,
      reason: 'the snapshot of the dead session must go too',
    );
    expect(state.signOuts, 1);
  });

  test('two screens failing at once sign out once, not twice', () async {
    final server = Server();
    final state = await signedIn(server);
    server.status = 401;
    server.gate = Completer<void>();

    // Both requests leave before either answer comes back.
    final comment = state.addComment(1, 'hello');
    final upload = state.uploadAttachment(1, 'note.txt', const [1, 2, 3]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    server.gate!.complete();
    await Future.wait([comment, upload]);

    expect(state.signOuts, 1, reason: 'one session, one sign-out');
    expect(state.isSignedIn, isFalse);
    expect(
      server.requests.where((r) => r.contains('/user')).length,
      1,
      reason: 'only the sign-in itself reads the user',
    );
  });

  test('a later call reuses the ended session instead of retrying', () async {
    final server = Server();
    final state = await signedIn(server);
    server.status = 401;
    await state.addComment(1, 'hello');
    final before = server.requests.length;

    await state.addComment(1, 'again');

    expect(server.requests.length, before, reason: 'no HTTP with no token');
    expect(state.signOuts, 1);
  });

  test('a 500 keeps the session and reports the server message', () async {
    final server = Server();
    final state = await signedIn(server);
    server.status = 500;

    final error = await state.addComment(1, 'hello');

    expect(error, 'Unauthorized');
    expect(state.isSignedIn, isTrue);
    expect(state.signOuts, 0);
    expect(await FlutterSecureStorage().read(key: 'vikunja_token'), isNotNull);
  });
}
