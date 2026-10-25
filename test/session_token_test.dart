import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';

/// Vikunja's login JWT is short-lived (10 minutes on a default self-hosted
/// server), which used to sign the user out mid-use. There is no refresh
/// endpoint, so the app trades the JWT for a long-lived API token right after
/// login and keeps that instead.
void main() {
  /// Serves /info, /login, /routes and /tokens; records what the app sent.
  Future<
    ({
      String base,
      Map<String, dynamic> sent,
      List<String> deleted,
      Future<void> done,
    })
  >
  serveSession({int tokenStatus = 200}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sent = <String, dynamic>{};
    final deleted = <String>[];
    final done = () async {
      await for (final req in server) {
        final body = await utf8.decodeStream(req);
        req.response.headers.contentType = ContentType.json;
        switch (req.uri.path) {
          case '/api/v1/login':
            req.response.write(jsonEncode({'token': 'jwt-10-minutes'}));
          case '/api/v1/routes':
            req.response.write(
              jsonEncode({
                'tasks': {
                  'read_all': {'path': '/tasks', 'method': 'GET'},
                  'update': {'path': '/tasks/:task', 'method': 'POST'},
                },
                'other': {
                  'user': {'path': '/user', 'method': 'GET'},
                },
                // Granted by the server but out of scope for a session token.
                'admin': {
                  'all': {'path': '/admin', 'method': 'ANY'},
                },
                'migration': {
                  'csv_migrate': {'path': '/migration/csv', 'method': 'POST'},
                },
              }),
            );
          case '/api/v1/tokens' when req.method == 'GET':
            // An older token from a previous login, to be replaced.
            req.response.write(jsonEncode([
              {'id': 7, 'title': VikunjaApi.sessionTokenTitle},
            ]));
          case final path when path.startsWith('/api/v1/tokens/'):
            deleted.add(req.uri.pathSegments.last);
            req.response.write('{}');
          case '/api/v1/tokens':
            sent.addAll(jsonDecode(body) as Map<String, dynamic>);
            req.response.statusCode = tokenStatus;
            req.response.write(
              tokenStatus >= 400
                  ? '{"message":"not allowed"}'
                  : jsonEncode({'token': 'tk-long-lived'}),
            );
          default:
            req.response.write('{}');
        }
        await req.response.close();
      }
    }();
    return (
      base: 'http://127.0.0.1:${server.port}',
      sent: sent,
      deleted: deleted,
      done: done,
    );
  }

  test('login keeps the long-lived API token, not the JWT', () async {
    final server = await serveSession();
    final api = VikunjaApi(baseUrl: server.base);
    final token = await api.login('joe', 'secret');
    api.close();

    expect(token, 'tk-long-lived');
    // Only the groups the app uses are granted: a long-lived credential stays
    // as narrow as the screens behind it.
    expect(server.sent['title'], VikunjaApi.sessionTokenTitle);
    final permissions = server.sent['permissions'] as Map<String, dynamic>;
    expect(permissions.keys, containsAll(['tasks', 'other']));
    expect(permissions['tasks'], containsAll(['read_all', 'update']));
    expect(permissions.keys, isNot(contains('admin')));
    expect(permissions.keys, isNot(contains('migration')));
    // Months out, not minutes, but still finite: a stolen token dies on its own.
    final expires = DateTime.parse(server.sent['expires_at'] as String);
    final days = expires.difference(DateTime.now()).inDays;
    expect(days, closeTo(VikunjaApi.sessionTokenLifetime.inDays, 1));
    // The token from the previous login is revoked, not left lying around.
    expect(server.deleted, ['7']);
  });

  test('a server that refuses API tokens keeps the JWT', () async {
    final server = await serveSession(tokenStatus: 403);
    final api = VikunjaApi(baseUrl: server.base);
    final token = await api.login('joe', 'secret');
    api.close();

    expect(token, 'jwt-10-minutes');
  });
}
