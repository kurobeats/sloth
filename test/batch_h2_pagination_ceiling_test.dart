import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';

/// The walk stops at [VikunjaApi.maxPages] whatever the server does. That is a
/// 2 000-row ceiling, and a caller that cannot tell a full answer from a cut
/// one silently loses rows.
void main() {
  test('a feed that never ends stops at the ceiling and reports it', () async {
    var requests = 0;
    final api = VikunjaApi(
      baseUrl: 'https://tasks.example.com',
      client: MockClient((request) async {
        requests++;
        // Every page is full: only the ceiling can end the walk.
        return http.Response(
          jsonEncode([
            for (var i = 0; i < 50; i++)
              {
                'id': i,
                'title': 'Project ${request.url.queryParameters['page']}-$i',
              },
          ]),
          200,
        );
      }),
    );

    expect(api.truncated, isFalse);
    final projects = await api.projects();

    expect(requests, VikunjaApi.maxPages);
    expect(projects, hasLength(VikunjaApi.maxPages * 50));
    expect(
      api.truncated,
      isTrue,
      reason: 'the ceiling cut the list, so the caller has to know',
    );
  });

  test('a list that ends by itself is not reported as truncated', () async {
    final api = VikunjaApi(
      baseUrl: 'https://tasks.example.com',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode([
            {'id': 1, 'title': 'Inbox'},
          ]),
          200,
        ),
      ),
    );

    expect(await api.projects(), hasLength(1));
    expect(api.truncated, isFalse);
  });
}
