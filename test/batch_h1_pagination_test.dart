import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';

/// Ten sequential round trips at 500 rows is ten latencies queued one behind
/// the other. The next page is requested while the current one is parsed, so
/// the walk costs one latency plus the parse work instead of one latency per
/// page — but the pages must still arrive in order and the walk must stop on
/// the last page without asking for one more.
void main() {
  late HttpServer server;
  late List<int> arrivals;
  late List<List<Map<String, dynamic>>> pages;

  setUp(() async {
    arrivals = [];
    pages = [
      [
        {'id': 1},
        {'id': 2},
      ],
      [
        {'id': 3},
        {'id': 4},
      ],
      [
        {'id': 5},
      ],
    ];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in server) {
        final page = int.parse(req.uri.queryParameters['page'] ?? '1');
        arrivals.add(page);
        final rows = page <= pages.length ? pages[page - 1] : const [];
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(rows));
        await req.response.close();
      }
    }());
  });

  tearDown(() => server.close(force: true));

  /// The real request, recorded in dispatch order before the socket work.
  Future<dynamic> fetch(int page, List<int> dispatched) async {
    dispatched.add(page);
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/api/v1/tasks'
          '?page=$page&per_page=2',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  test('the next page is requested before the current one is parsed', () async {
    final dispatched = <int>[];
    // What each parsed row saw of the request log at the moment it was parsed.
    final parsedAt = <int, List<int>>{};

    final items = await VikunjaApi.paginate<int>(
      path: '/tasks',
      perPage: 2,
      fetch: (page) => fetch(page, dispatched),
      parse: (row) {
        final id = row['id'] as int;
        parsedAt[id] = List.of(dispatched);
        return id;
      },
    );

    expect(items, [1, 2, 3, 4, 5], reason: 'page order is preserved');
    expect(arrivals, [
      1,
      2,
      3,
    ], reason: 'the short last page ends the walk: no page 4 is requested');
    expect(parsedAt[1], [
      1,
      2,
    ], reason: 'page 2 was already in flight while page 1 was parsed');
    expect(parsedAt[3], [
      1,
      2,
      3,
    ], reason: 'page 3 was already in flight while page 2 was parsed');
    expect(parsedAt[5], [
      1,
      2,
      3,
    ], reason: 'the last page asks for nothing more');
  });

  test('a full-page run stops at the 40-page ceiling', () async {
    pages = [
      for (var page = 1; page <= 60; page++)
        [
          {'id': page * 2 - 1},
          {'id': page * 2},
        ],
    ];
    final dispatched = <int>[];

    final items = await VikunjaApi.paginate<int>(
      path: '/tasks',
      perPage: 2,
      fetch: (page) => fetch(page, dispatched),
      parse: (row) => row['id'] as int,
    );

    expect(arrivals.length, 40, reason: 'the ceiling still caps the walk');
    expect(arrivals.last, 40);
    expect(items.length, 80);
  });
}
