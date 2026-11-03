import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

const _server = 'https://tasks.example.com';

/// Vikunja only expands `related_tasks` on GET /tasks/{id}; update and list
/// answers come back without the key. A relation must survive both kinds of
/// replacement, and an explicit empty map must clear it.
const _relations = '{"subtask":[{"id":2,"title":"Buy Oat Milk"}]}';

Future<AppState> stateWithRelations({
  bool listCarriesRelations = false,
  bool updateCarriesRelations = false,
}) async {
  dynamic relations = jsonDecode(_relations);
  final state = AppState()
    ..api = VikunjaApi(
      baseUrl: _server,
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/tasks/1')) {
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                ...jsonDecode(request.body),
                if (updateCarriesRelations) 'related_tasks': relations,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'id': 1,
              'project_id': 1,
              'title': 'Fix bike',
              'related_tasks': relations,
            }),
            200,
          );
        }
        if (path.endsWith('/tasks') && request.method == 'GET') {
          final body = [for (final e in [if (listCarriesRelations) 1])
            {
              'id': 1,
              'project_id': 1,
              'title': 'Fix bike',
              'related_tasks': relations,
            }];
          return http.Response(jsonEncode(body), 200);
        }
        return http.Response('[]', 200);
      }),
    )
    ..user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

void main() {
  test('relations survive an edit whose reply lacks related_tasks', () async {
    final state = await stateWithRelations();
    await state.loadTask(1);
    expect(state.taskById(1)!.relations, hasLength(1));

    await state.mutate(state.taskById(1)!, (t) => t.done = true);

    expect(
      state.taskById(1)!.relations,
      hasLength(1),
      reason: 'the update reply said nothing about relations: keep them',
    );
  });

  test('relations survive a refresh whose list lacks related_tasks', () async {
    final state = await stateWithRelations();
    await state.loadTask(1);
    expect(state.taskById(1)!.relations, hasLength(1));

    await state.refresh();

    expect(state.taskById(1)!.relations, hasLength(1));
  });

  test('an explicit empty related_tasks map clears the relations', () async {
    final state = await stateWithRelations();
    await state.loadTask(1);
    expect(state.taskById(1)!.relations, hasLength(1));

    // The next single-task fetch says the task has no relations: that is an
    // answer, not an omission.
    state.api = VikunjaApi(
      baseUrl: _server,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({'id': 1, 'project_id': 1, 'related_tasks': {}}),
          200,
        ),
      ),
    );
    await state.loadTask(1);

    expect(state.taskById(1)!.relations, isEmpty);
  });

  test('a saved filter resolves its view from the single-project fetch',
      () async {
    var listFetches = 0;
    final state = AppState()
      ..api = VikunjaApi(
        baseUrl: _server,
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/projects')) {
            // GET /projects leaves pseudo-projects without views.
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'title': 'Inbox',
                  'views': [
                    {'id': 1, 'title': 'List', 'view_kind': 'list'},
                  ],
                },
                {'id': -2, 'title': 'My Open Tasks', 'views': []},
              ]),
              200,
            );
          }
          if (path.endsWith('/projects/-2')) {
            return http.Response(
              jsonEncode({
                'id': -2,
                'title': 'My Open Tasks',
                'views': [
                  {
                    'id': 5,
                    'title': 'List',
                    'project_id': -2,
                    'view_kind': 'list',
                  },
                ],
              }),
              200,
            );
          }
          if (path.contains('/projects/-2/views/5/tasks')) {
            listFetches++;
            return http.Response(
              jsonEncode([
                {
                  'id': 10,
                  'title': 'True the front wheel',
                  'project_id': 4,
                  'assignees': [
                    {'id': 1, 'username': 'me'},
                  ],
                },
              ]),
              200,
            );
          }
          if (path.endsWith('/tasks') && request.method == 'GET') {
            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        }),
      )
      ..user = const VikunjaUser(id: 1, username: 'me');
    await state.refresh();

    final filter = state.savedFilters.single;
    await state.select(ListSelection.project(filter));

    expect(listFetches, 1, reason: 'the pseudo-project view was consulted');
    expect(state.openTasks.map((t) => t.title), ['True the front wheel']);
    // The drawer count reads the fetched view, not the flat list.
    expect(
      state.fetchedProjectTasks(-2)!.where((t) => !t.done).length,
      1,
    );

    // A refresh while the filter is open must not wipe the fetched rows.
    await state.refresh();
    expect(state.openTasks.map((t) => t.title), ['True the front wheel']);
  });
}