import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

/// `mutate()` paints the edit before the round trip. When the server rejects
/// it, the edit must come off the screen again — the same instance the caches
/// hold must never be edited in place.
VikunjaApi api(http.Client client) =>
    VikunjaApi(baseUrl: 'https://tasks.example.com', client: client);

VikunjaApi listApi(List<Map<String, dynamic>> tasks) => api(
  MockClient((request) async {
    if (request.url.path.endsWith('/tasks')) {
      return http.Response(jsonEncode(tasks), 200);
    }
    return http.Response('[]', 200);
  }),
);

VikunjaApi rejectingApi() => api(
  MockClient(
    (request) async =>
        http.Response('{"message":"Server said no","code":500}', 500),
  ),
);

VikunjaApi echoApi() => api(
  MockClient((request) async {
    if (request.method == 'POST' && request.url.path.contains('/tasks/')) {
      return http.Response(request.body, 200);
    }
    return http.Response('[]', 200);
  }),
);

Future<AppState> stateWith(List<Map<String, dynamic>> tasks) async {
  final state = AppState();
  state.api = listApi(tasks);
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

void main() {
  test('a rejected edit is rolled back, not left on screen', () async {
    final state = await stateWith([
      {'id': 1, 'project_id': 1, 'title': 'Buy milk'},
    ]);
    final task = state.taskById(1)!;

    state.api = rejectingApi();
    await state.mutate(task, (t) => t.title = 'Buy oat milk');

    expect(
      state.taskById(1)!.title,
      'Buy milk',
      reason: 'the optimistic edit must be reverted',
    );
    expect(
      task.title,
      'Buy milk',
      reason: 'the instance the caches hold is never mutated in place',
    );
    expect(state.error, 'Server said no');
  });

  test('a rejected toggle leaves the task exactly as the server had it',
      () async {
    final state = await stateWith([
      {'id': 1, 'project_id': 1, 'title': 'Buy milk'},
    ]);
    final task = state.taskById(1)!;

    state.api = rejectingApi();
    await state.toggleDone(task);

    final after = state.taskById(1)!;
    expect(after.done, isFalse);
    expect(after.doneAt, isNull);
    expect(after.percentDone, 0);
  });

  test('a successful edit lands on the cached task', () async {
    final state = await stateWith([
      {'id': 1, 'project_id': 1, 'title': 'Buy milk'},
    ]);
    final task = state.taskById(1)!;

    state.api = echoApi();
    await state.mutate(task, (t) => t.title = 'Buy oat milk');

    expect(state.taskById(1)!.title, 'Buy oat milk');
    expect(state.error, isNull);
  });
}
