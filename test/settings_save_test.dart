import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';

/// Vikunja never exposes user_* route groups to API tokens, so saving account
/// settings with the durable session token always 401s — which the app reads
/// as a dead session and signs the user out. The fix: exchange the login's
/// refresh-token cookie at /user/token/refresh for a fresh JWT and save with
/// that. These tests pin the exchange and the error shape.
void main() {
  test('saveUserSettings refreshes the JWT and sends it as bearer', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <({String path, String? auth, String? cookie})>[];
    final done = () async {
      await for (final req in server) {
        utf8.decodeStream(req); // drain the body
        // Vikunja rotates the cookie on every refresh; each response sets a
        // new one so the client must keep the latest value.
        final rotate =
            req.uri.path.endsWith('/refresh') ||
            req.uri.path.endsWith('/login');
        if (rotate) {
          req.response.headers
            ..add('set-cookie', 'vikunja_refresh_token=cccc; Path=/refresh')
            ..add('set-cookie', 'vikunja_refresh_token=cccc; Path=/refresh');
        }
        req.response.headers.contentType = ContentType.json;
        calls.add((
          path: req.uri.path,
          auth: req.headers.value('authorization'),
          cookie: req.headers.value('cookie'),
        ));
        switch (req.uri.path) {
          case '/api/v1/login':
            req.response.write(jsonEncode({'token': 'jwt-10-min'}));
          case '/api/v1/routes':
            req.response.write(jsonEncode({
              'tasks': {
                'read_all': {'path': '/tasks', 'method': 'GET'},
              },
              'other': {
                'user': {'path': '/user', 'method': 'GET'},
              },
            }));
          case '/api/v1/tokens' when req.method == 'GET':
            req.response.write(jsonEncode(<Map<String, dynamic>>[]));
          case '/api/v1/tokens':
            req.response.write(jsonEncode({'token': 'tk-long-lived'}));
          case '/api/v1/user/token/refresh':
            req.response.write(jsonEncode({'token': 'fresh-jwt'}));
          case '/api/v1/user/settings/general':
            // The save only succeeds with the freshly minted JWT: a real
            // server rejects the durable token on user_* routes with 401.
            if (req.headers.value('authorization') != 'Bearer fresh-jwt') {
              req.response.statusCode = 401;
              req.response.write(
                jsonEncode({
                  'message': 'missing, malformed, expired or otherwise '
                      'invalid token provided',
                }),
              );
            } else {
              req.response.write('{}');
            }
          case '/api/v1/user':
            req.response.write(
              jsonEncode({
                'id': 1,
                'username': 'joe',
                'settings': {'timezone': 'GMT'},
              }),
            );
          default:
            req.response.write('{}');
        }
        await req.response.close();
      }
    }();

    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}');
    await api.login('joe', 'secret');
    // The login response carries the refresh cookie; the client kept it.
    expect(api.refreshToken, 'cccc');
    final user = await api.saveUserSettings(
      const VikunjaUserSettings(timezone: 'GMT'),
    );
    api.close();
    await server.close();
    await done;

    final refresh = calls.firstWhere(
      (c) => c.path == '/api/v1/user/token/refresh',
    );
    expect(refresh.cookie, contains('vikunja_refresh_token=cccc'));
    final save = calls.firstWhere(
      (c) => c.path == '/api/v1/user/settings/general',
    );
    expect(save.auth, 'Bearer fresh-jwt');
    expect(user.username, 'joe');
    // The rotated cookie is captured for the next save.
    expect(api.refreshToken, 'cccc');
  });

  test('an expired refresh cookie fails as a message, not a sign-out',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final done = () async {
      await for (final req in server) {
        req.response.headers.contentType = ContentType.json;
        switch (req.uri.path) {
          case '/api/v1/login':
            req.response.write(jsonEncode({'token': 'jwt-10-min'}));
          case '/api/v1/routes':
            req.response.write(jsonEncode({
              'other': {
                'user': {'path': '/user', 'method': 'GET'},
              },
            }));
          case '/api/v1/tokens' when req.method == 'GET':
            req.response.write(jsonEncode(<Map<String, dynamic>>[]));
          case '/api/v1/tokens':
            req.response.write(jsonEncode({'token': 'tk-long-lived'}));
          case '/api/v1/user/token/refresh':
            // Vikunja's expired-cookie fault (code 16002) is a 401, but the
            // durable token still works everywhere else: the app must not
            // treat this as a dead session.
            req.response.statusCode = 401;
            req.response.write(
              jsonEncode({
                'message': 'Invalid or expired refresh token.',
              }),
            );
          default:
            req.response.write('{}');
        }
        await req.response.close();
      }
    }();

    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}');
    await api.login('joe', 'secret');
    await expectLater(
      api.saveUserSettings(const VikunjaUserSettings()),
      throwsA(
        isA<VikunjaException>()
            .having((e) => e.statusCode, 'statusCode', 0)
            .having(
              (e) => e.message,
              'message',
              contains('Sign in again'),
            ),
      ),
    );
    api.close();
    await server.close();
    await done;
  });
}