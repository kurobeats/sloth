import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_format.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/task_tile.dart';

/// A [VikunjaApi] that serves [tasks] over the endpoints `refresh()` reads.
VikunjaApi fakeApi(List<Map<String, dynamic>> tasks) {
  return VikunjaApi(
    baseUrl: 'https://tasks.example.com',
    client: MockClient((request) async {
      final path = request.url.path;
      final page =
          int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      const perPage = 50;
      if (path.endsWith('/tasks')) {
        final start = (page - 1) * perPage;
        if (start >= tasks.length) return http.Response('[]', 200);
        return http.Response(
          jsonEncode(tasks.skip(start).take(perPage).toList()),
          200,
        );
      }
      return http.Response('[]', 200);
    }),
  );
}

Map<String, dynamic> taskJson(
  int id, {
  String? title,
  DateTime? due,
  DateTime? doneAt,
}) => {
  'id': id,
  'project_id': 1,
  'title': title ?? 'Task $id',
  if (due != null) 'due_date': due.toUtc().toIso8601String(),
  if (doneAt != null) ...{
    'done': true,
    'done_at': doneAt.toUtc().toIso8601String(),
  },
};

/// An [AppState] signed in and holding [tasks], as after a refresh.
Future<AppState> stateWith(List<Map<String, dynamic>> tasks) async {
  final state = AppState();
  state.api = fakeApi(tasks);
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const HomeScreen(),
  ),
);

/// How many [TaskTile] *widgets* the list built up front. A plain
/// `ListView(children: …)` constructs one per task eagerly; a builder
/// constructs none of them until the row is about to be painted.
int eagerlyBuiltTiles(ListView list) {
  final delegate = list.childrenDelegate;
  if (delegate is! SliverChildListDelegate) return 0;
  return delegate.children.whereType<TaskTile>().length;
}

void main() {
  testWidgets('a long task list only builds the rows on screen', (
    tester,
  ) async {
    final now = DateTime.now();
    final state = await stateWith([
      for (var i = 1; i <= 200; i++) taskJson(i, due: now),
    ]);
    await tester.pumpWidget(host(state));
    await tester.pump();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      eagerlyBuiltTiles(list),
      lessThan(30),
      reason: 'every tile is constructed up front instead of on demand',
    );
    expect(find.byType(TaskTile).evaluate().length, lessThanOrEqualTo(30));
    expect(
      find.text('Task 200'),
      findsOneWidget,
      reason: 'the visible row renders (newest id first)',
    );
  });

  testWidgets('day headers still group the upcoming list', (tester) async {
    final now = DateTime.now();
    final day3 = now.add(const Duration(days: 3));
    final day4 = now.add(const Duration(days: 4));
    final state = await stateWith([
      taskJson(1, title: 'First job', due: day3),
      taskJson(2, title: 'Second job', due: day4),
    ]);
    // Upcoming is the one list grouped by day.
    await state.select(const ListSelection.smart(SmartList.upcoming));
    await tester.pumpWidget(host(state));
    await tester.pump();

    expect(find.text(TodoFormat.groupHeader(day3)), findsOneWidget);
    expect(find.text(TodoFormat.groupHeader(day4)), findsOneWidget);
    expect(find.text('First job'), findsOneWidget);
    expect(find.text('Second job'), findsOneWidget);
  });

  testWidgets('the Done row still reveals completed tasks when tapped', (
    tester,
  ) async {
    final now = DateTime.now();
    final state = await stateWith([
      taskJson(1, title: 'Open job', due: now),
      taskJson(
        2,
        title: 'Finished job',
        due: now,
        doneAt: now.subtract(const Duration(hours: 2)),
      ),
    ]);
    await tester.pumpWidget(host(state));
    await tester.pump();

    expect(find.text('Finished job'), findsNothing, reason: 'collapsed');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Finished job'), findsOneWidget);
  });
}
