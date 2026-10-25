import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

/// Vikunja 2.x registers the label update as POST; a PUT is answered 405
/// "Method Not Allowed" and the rename silently does nothing.
void main() {
  test('renaming a label uses the verb the server accepts', () async {
    final calls = <String>[];
    String? body;
    final api = VikunjaApi(
      baseUrl: 'https://tasks.example.com',
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'PUT') {
          return http.Response('{"message":"Method Not Allowed"}', 405);
        }
        body = request.body;
        return http.Response(
          jsonEncode({
            'id': 8,
            'title': 'QA Renamed',
            'hex_color': '2f626f',
            'description': 'kept',
          }),
          200,
        );
      }),
    );
    final state = AppState()
      ..api = api
      ..user = const VikunjaUser(id: 1, username: 'me')
      ..labels = const [VikunjaLabel(id: 8, title: 'QA', hexColor: '2f626f')];

    final error = await state.updateLabel(
      const VikunjaLabel(id: 8, title: 'QA', hexColor: '2f626f'),
      title: 'QA Renamed',
      description: 'kept',
    );

    expect(error, isNull, reason: 'the server accepted the rename');
    expect(calls, ['POST /api/v1/labels/8']);
    expect(jsonDecode(body!)['title'], 'QA Renamed');
    expect(state.labels.single.title, 'QA Renamed');
  });
}
