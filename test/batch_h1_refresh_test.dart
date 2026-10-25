import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

const _server = 'https://tasks.example.com';

/// A fake server whose `GET /tasks` answers can be held open, so a refresh can
/// be caught mid-flight while a mutation runs.
class GatedServer {
  bool slow = false;
  Completer<void>? gate;
  final List<String> requests = [];

  int get taskFetches => requests.where((r) => r == 'GET /api/v1/tasks').length;

  AppState state() {
    final state = AppState();
    state.api = VikunjaApi(
      baseUrl: _server,
      client: MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (request.method == 'POST' && path.contains('/tasks/')) {
          // The server echoes the update, like a real Vikunja.
          return http.Response(request.body, 200);
        }
        if (request.method == 'GET' && path.endsWith('/tasks')) {
          final held = slow ? gate : null;
          if (held != null) await held.future;
          return http.Response(
            jsonEncode([
              {'id': 1, 'project_id': 1, 'title': 'Buy milk'},
            ]),
            200,
          );
        }
        if (path.endsWith('/user')) {
          return http.Response('{"id":1,"username":"me"}', 200);
        }
        return http.Response('[]', 200);
      }),
    );
    state.user = const VikunjaUser(id: 1, username: 'me');
    return state;
  }
}

void main() {
  test('a mutation survives a refresh that started before it', () async {
    final server = GatedServer();
    final state = server.state();
    await state.refresh();
    expect(state.taskById(1)!.title, 'Buy milk');
    server.requests.clear();

    // The poller (or a pull-to-refresh) starts reading before the edit.
    server.slow = true;
    server.gate = Completer<void>();
    final slowRefresh = state.refresh();

    await state.mutate(state.taskById(1)!, (t) => t.title = 'Buy oat milk');
    expect(state.taskById(1)!.title, 'Buy oat milk');

    // The refresh answers with the data it read before the edit landed.
    server.gate!.complete();
    await slowRefresh;

    expect(
      state.taskById(1)!.title,
      'Buy oat milk',
      reason: 'an in-flight refresh must not put the stale title back',
    );
    expect(state.error, isNull, reason: 'the edit was saved, not lost');
  });

  test('a second refresh while one is running reuses it', () async {
    final server = GatedServer();
    final state = server.state();
    await state.refresh();
    server.requests.clear();

    server.slow = true;
    server.gate = Completer<void>();
    final first = state.refresh();
    final second = state.refresh();
    server.gate!.complete();
    await Future.wait([first, second]);

    expect(
      server.taskFetches,
      1,
      reason: 'two overlapping refreshes must not double the traffic',
    );
  });

  test('a later refresh still applies what the server says', () async {
    final server = GatedServer();
    final state = server.state();
    await state.refresh();
    await state.mutate(state.taskById(1)!, (t) => t.title = 'Buy oat milk');

    // Nothing is in flight now, so the server is authoritative again.
    await state.refresh();

    expect(
      state.taskById(1)!.title,
      'Buy milk',
      reason: 'the local-edit guard only covers the window of one refresh',
    );
  });
}
