import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/home_widget_sync.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

/// The task list is rebuilt on every notification: the derived lists have to
/// be computed once per change, not once per build.
Map<String, dynamic> taskJson(
  int id, {
  String? title,
  int projectId = 1,
  DateTime? due,
  DateTime? doneAt,
}) => {
  'id': id,
  'project_id': projectId,
  'title': title ?? 'Task $id',
  if (due != null) 'due_date': due.toUtc().toIso8601String(),
  if (doneAt != null) ...{
    'done': true,
    'done_at': doneAt.toUtc().toIso8601String(),
  },
};

VikunjaApi derivedApi(
  List<Map<String, dynamic>> tasks, {
  List<Map<String, dynamic>> projects = const [],
}) => VikunjaApi(
  baseUrl: 'https://tasks.example.com',
  client: MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/tasks')) {
      return http.Response(jsonEncode(tasks), 200);
    }
    if (request.method == 'GET' && path.endsWith('/projects')) {
      return http.Response(jsonEncode(projects), 200);
    }
    if (request.method == 'PUT' && path.endsWith('/tasks')) {
      return http.Response(request.body, 200);
    }
    if (request.method == 'POST' && path.contains('/tasks/')) {
      return http.Response(request.body, 200);
    }
    return http.Response('[]', 200);
  }),
);

Future<AppState> stateWith(
  List<Map<String, dynamic>> tasks, {
  List<Map<String, dynamic>> projects = const [],
}) async {
  final state = AppState();
  state.api = derivedApi(tasks, projects: projects);
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

void main() {
  test('the derived lists are cached until the data changes', () async {
    final now = DateTime.now();
    final state = await stateWith([
      taskJson(1, title: 'Open', due: now),
      taskJson(2, title: 'Done', due: now, doneAt: now),
    ]);
    await state.select(const ListSelection.smart(SmartList.allTasks));

    final open = state.openTasks;
    final done = state.completedTasks;
    expect(identical(open, state.openTasks), isTrue, reason: 'same data');
    expect(identical(done, state.completedTasks), isTrue);

    final created = await state.addTask(
      'New one',
      project: const VikunjaProject(id: 1, title: 'Home'),
    );
    expect(created, isNotNull);

    final after = state.openTasks;
    expect(identical(after, open), isFalse, reason: 'the data changed');
    expect(after.map((t) => t.title), contains('New one'));
    expect(identical(state.completedTasks, done), isFalse);

    await state.select(const ListSelection.smart(SmartList.upcoming));
    expect(
      identical(state.openTasks, after),
      isFalse,
      reason: 'a different selection is a different list',
    );
  });

  test('one definition of "due today or earlier" for list and widget', () async {
    final now = DateTime(2026, 10, 25, 9);
    final state = await stateWith([
      taskJson(1, title: 'Overdue', due: DateTime(2026, 10, 24)),
      taskJson(2, title: 'Today', due: DateTime(2026, 10, 25, 18)),
      taskJson(3, title: 'Tomorrow', due: DateTime(2026, 10, 26)),
      taskJson(4, title: 'No date'),
      taskJson(5, title: 'Finished', due: DateTime(2026, 10, 25), doneAt: now),
    ]);
    state.clock = () => now;

    final smart = state.openTasks.map((t) => t.id).toList();
    final rows = homeWidgetRows(state.allTasksForWidget, now: now)
        .map((r) => r.id)
        .toList();

    expect(smart, [1, 2]);
    expect(rows, smart, reason: 'same fixture, same membership');
  });

  test('the cut-off follows the injected clock', () async {
    final state = await stateWith([
      taskJson(1, title: 'Overdue', due: DateTime(2026, 10, 24)),
      taskJson(2, title: 'Today', due: DateTime(2026, 10, 25, 18)),
    ]);

    state.clock = () => DateTime(2026, 10, 25, 9);
    expect(state.openTasks.map((t) => t.id), [1, 2]);

    state.clock = () => DateTime(2026, 10, 24, 9);
    // The list is cached per data change; a moved clock is not a data change,
    // so the next build is what asks for it again.
    state.notifyListeners();
    expect(
      state.openTasks.map((t) => t.id),
      [1],
      reason: 'a task due tomorrow is not due today — no hidden clock',
    );
  });

  test('the project index agrees with the linear scan', () async {
    final projects = <Map<String, dynamic>>[
      {'id': 1, 'title': 'Home'},
      {'id': 2, 'title': 'Work'},
    ];
    final state = await stateWith(
      [taskJson(1, title: 'Invoice', projectId: 2)],
      projects: projects,
    );

    final task = state.taskById(1)!;
    expect(state.projectOf(task), const VikunjaProject(id: 2, title: 'Work'));
    expect(
      identical(state.projectIndex[2], state.projectOf(task)),
      isTrue,
      reason: 'projectOf must read the index, not rescan the list',
    );
  });

  test('the project index follows a rename after refresh', () async {
    final projects = <Map<String, dynamic>>[
      {'id': 1, 'title': 'Home'},
      {'id': 2, 'title': 'Work'},
    ];
    final state = await stateWith(
      [taskJson(1, title: 'Invoice', projectId: 2)],
      projects: projects,
    );
    expect(state.projectOf(state.taskById(1)!)!.title, 'Work');

    projects[1] = {'id': 2, 'title': 'Work renamed'};
    await state.refresh();

    expect(state.projectOf(state.taskById(1)!)!.title, 'Work renamed');
    expect(state.projectIndex[2]!.title, 'Work renamed');
  });
}
