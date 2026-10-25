import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';

/// A login JWT dies after 10 minutes and must never be presented as a durable
/// session; and the old session tokens may only be dropped once the new one
/// exists.
void main() {
  String jwt() {
    String b64(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp =
        DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000;
    return '${b64({'alg': 'HS256'})}.${b64({'exp': exp})}.sig';
  }

  /// Serves /login, /routes, /tokens and /info; records the order of the token
  /// calls and the last Authorization header.
  Future<({String base, List<String> events, List<String> auths})> serve({
    int tokenStatus = 200,
    List<int> existing = const [],
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final events = <String>[];
    final auths = <String>[];
    final token = jwt();
    unawaited(() async {
      await for (final req in server) {
        await utf8.decodeStream(req);
        final auth = req.headers.value('authorization');
        if (auth != null) auths.add(auth);
        req.response.headers.contentType = ContentType.json;
        switch (req.uri.path) {
          case '/api/v1/login':
            req.response.write(jsonEncode({'token': token}));
          case '/api/v1/routes':
            req.response.write(
              jsonEncode({
                'tasks': {
                  'read_all': {'path': '/tasks', 'method': 'GET'},
                },
                'other': {
                  'user': {'path': '/user', 'method': 'GET'},
                },
              }),
            );
          case '/api/v1/tokens' when req.method == 'GET':
            req.response.write(
              jsonEncode([
                for (final id in existing)
                  {'id': id, 'title': VikunjaApi.sessionTokenTitle},
              ]),
            );
          case final path
              when path.startsWith('/api/v1/tokens/') && req.method == 'DELETE':
            events.add('delete ${req.uri.pathSegments.last}');
            req.response.write('{}');
          case '/api/v1/tokens':
            events.add('create');
            req.response.statusCode = tokenStatus;
            req.response.write(
              tokenStatus >= 400
                  ? '{"message":"not allowed"}'
                  : jsonEncode({'token': 'tk-durable'}),
            );
          default:
            req.response.write('{}');
        }
        await req.response.close();
      }
    }());
    return (
      base: 'http://127.0.0.1:${server.port}',
      events: events,
      auths: auths,
    );
  }

  test('a minted API token is the durable session', () async {
    final s = await serve();
    final api = VikunjaApi(baseUrl: s.base);
    final token = await api.login('joe', 'secret');
    api.close();

    expect(token, 'tk-durable');
    expect(api.sessionTokenIsDurable, isTrue);
    expect(api.tokenExpiresAt, isNotNull);
    expect(
      api.tokenExpiresAt!.difference(DateTime.now()).inDays,
      closeTo(VikunjaApi.sessionTokenLifetime.inDays, 1),
    );
  });

  test('a refused mint keeps the JWT, flagged as not durable', () async {
    final s = await serve(tokenStatus: 403);
    final api = VikunjaApi(baseUrl: s.base);
    final token = await api.login('joe', 'secret');

    expect(api.sessionTokenIsDurable, isFalse);
    // Minutes, not months: AppState can warn the user before it dies.
    final left = api.tokenExpiresAt!.difference(DateTime.now());
    expect(left.inMinutes, inInclusiveRange(8, 11));

    // Still usable for the session that just started.
    await api.info();
    api.close();
    expect(s.auths.last, 'Bearer $token');
  });

  test('the new token exists before the old ones are dropped', () async {
    final s = await serve(existing: [3, 7]);
    final api = VikunjaApi(baseUrl: s.base);
    final token = await api.login('joe', 'secret');
    api.close();

    expect(token, 'tk-durable');
    expect(s.events, ['create', 'delete 3', 'delete 7']);
  });

  test('a failed create leaves the existing tokens alone', () async {
    final s = await serve(existing: [3, 7], tokenStatus: 403);
    final api = VikunjaApi(baseUrl: s.base);
    await api.login('joe', 'secret');
    api.close();

    expect(s.events, ['create']);
  });
}
