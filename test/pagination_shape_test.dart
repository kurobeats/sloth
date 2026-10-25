import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';

/// A page that is not a list is a broken server, not the end of the data:
/// presenting page 1 as the whole result silently loses rows.
void main() {
  test('a malformed page throws instead of returning partial data', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in server) {
        req.response.headers.contentType = ContentType.json;
        final page = int.parse(req.uri.queryParameters['page'] ?? '1');
        req.response.write(
          page == 1
              ? jsonEncode([
                  for (var i = 0; i < 50; i++) {'id': i, 'title': 'l$i'},
                ])
              : '{}',
        );
        await req.response.close();
      }
    }());
    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'abc';

    await expectLater(() => api.labels(), throwsA(isA<VikunjaException>()));
    api.close();
    await server.close(force: true);
  });
}
