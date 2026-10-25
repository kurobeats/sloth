import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

const _server = 'https://tasks.example.com';

/// The task the detail screen opens, as a server would send it: a due date, one
/// relation and one comment, so every section has something to render.
final _task = {
  'id': 1,
  'project_id': 1,
  'title': 'Fix bike',
  'description': 'Note',
  'due_date': DateTime.now()
      .add(const Duration(days: 2))
      .toUtc()
      .toIso8601String(),
  'related_tasks': {
    'related': [
      {'id': 2, 'title': 'Sibling task', 'done': false},
    ],
  },
  'comment_count': 1,
};

/// One fake server for the detail screen: it records the request lines, so a
/// write that should have been debounced into one shows up as two.
class DetailServer {
  final requests = <String>[];
  final bodies = <String>[];

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    final method = request.method;
    requests.add('$method $path');
    if (path.endsWith('/tasks/1/comments')) {
      if (method != 'GET') return http.Response('{}', 200);
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'comment': 'Chain needs replacing',
            'author': {'id': 1, 'username': 'me'},
          },
        ]),
        200,
      );
    }
    if (path.endsWith('/tasks/1/attachments')) return http.Response('[]', 200);
    if (path.endsWith('/tasks/1')) {
      if (method == 'POST') {
        bodies.add(request.body);
        return http.Response(request.body, 200);
      }
      return http.Response(jsonEncode(_task), 200);
    }
    if (path.endsWith('/projects')) {
      return http.Response(
        jsonEncode([
          {'id': 1, 'title': 'Inbox'},
        ]),
        200,
      );
    }
    return http.Response('[]', 200);
  });

  Future<AppState> state() async {
    final state = AppState();
    state.api = VikunjaApi(baseUrl: _server, client: client());
    state.user = const VikunjaUser(id: 1, username: 'me');
    await state.refresh();
    return state;
  }

  Iterable<String> get posts => requests.where(
    (r) => r == 'POST /api/v1/tasks/1',
  );
}

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const TaskDetailScreen(taskId: 1),
  ),
);

void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('typing a title posts the edit once, after the debounce', (
    tester,
  ) async {
    tallView(tester);
    final server = DetailServer();
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(server.posts, isEmpty, reason: 'opening the screen writes nothing');

    await tester.enterText(find.byType(TextField).first, 'Buy oat milk');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      server.posts,
      isEmpty,
      reason: 'the save waits for the 700 ms debounce',
    );

    // Further typing inside the window must still collapse into one write.
    await tester.enterText(find.byType(TextField).first, 'Buy oat milk today');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(server.posts, hasLength(1));
    expect(state.taskById(1)!.title, 'Buy oat milk today');
    expect(
      (jsonDecode(server.bodies.single) as Map<String, dynamic>)['title'],
      'Buy oat milk today',
    );
  });

  testWidgets('clearing the due date sends the zero timestamp', (tester) async {
    tallView(tester);
    final server = DetailServer();
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(state.taskById(1)!.dueDate, isNotNull);

    // The only row with a value can be cleared.
    await tester.tap(find.byTooltip('Clear').first);
    await tester.pumpAndSettle();

    expect(server.posts, hasLength(1));
    final body = jsonDecode(server.bodies.single) as Map<String, dynamic>;
    expect(
      body['due_date'],
      startsWith('0001-01-01'),
      reason: 'Vikunja clears a date by storing the zero time',
    );
    expect(
      state.taskById(1)!.dueDate,
      isNull,
      reason: 'the zero time reads back as "no due date"',
    );
  });

  testWidgets('the relation and comment sections render what the server says', (
    tester,
  ) async {
    tallView(tester);
    final server = DetailServer();
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    expect(find.text('Related Tasks'), findsOneWidget);
    expect(find.text('Sibling task'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Chain needs replacing'), findsOneWidget);
    expect(find.text('Add your comment…'), findsOneWidget);
  });
}
