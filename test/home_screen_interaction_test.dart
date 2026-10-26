import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/account_settings_screen.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

const _server = 'https://tasks.example.com';

Map<String, dynamic> taskJson(int id, String title) => {
  'id': id,
  'project_id': 1,
  'title': title,
  // Due today, so the default smart list lists it.
  'due_date': DateTime.now().toUtc().toIso8601String(),
};

/// An [AppState] that records the interactions the list screen drives, on top
/// of the real write paths.
class HomeFake extends AppState {
  final toggled = <int>[];
  final added = <String>[];

  @override
  Future<void> toggleDone(VikunjaTask task) {
    toggled.add(task.id);
    return super.toggleDone(task);
  }

  @override
  Future<VikunjaTask?> addTask(String title, {VikunjaProject? project}) {
    added.add(title);
    return super.addTask(title, project: project);
  }
}

/// One fake server for the list, its entry bar and the detail route it opens.
class HomeServer {
  HomeServer({this.tasks = const []});

  final List<Map<String, dynamic>> tasks;
  final requests = <String>[];

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    final method = request.method;
    requests.add('$method $path');
    if (method == 'PUT' && path.endsWith('/projects/1/tasks')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'id': 9,
          'project_id': 1,
          'title': body['title'],
          'due_date': DateTime.now().toUtc().toIso8601String(),
        }),
        200,
      );
    }
    if (path.endsWith('/projects')) {
      return http.Response(
        jsonEncode([
          {'id': 1, 'title': 'Inbox'},
        ]),
        200,
      );
    }
    if (path.endsWith('/tasks/1')) {
      // A write replaces the task; the server answers with what it stored.
      if (method == 'POST') return http.Response(request.body, 200);
      return http.Response(jsonEncode(taskJson(1, 'Fix bike')), 200);
    }
    if (path.endsWith('/tasks')) return http.Response(jsonEncode(tasks), 200);
    return http.Response('[]', 200);
  });

  Future<HomeFake> state() async {
    final state = HomeFake();
    state.api = VikunjaApi(baseUrl: _server, client: client());
    state.user = const VikunjaUser(id: 1, username: 'me');
    await state.refresh();
    return state;
  }
}

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const HomeScreen(),
  ),
);

Finder checkTarget() => find.byType(InkResponse).first;

void main() {
  testWidgets('the list renders every open task the state holds', (
    tester,
  ) async {
    final server = HomeServer(
      tasks: [taskJson(1, 'Fix bike'), taskJson(2, 'Buy milk')],
    );
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pump();

    expect(find.text('Fix bike'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Nothing due today'), findsNothing);
  });

  testWidgets('tapping the circle marks the task done', (tester) async {
    final server = HomeServer(tasks: [taskJson(1, 'Fix bike')]);
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pump();

    await tester.tap(checkTarget());
    await tester.pump();
    await tester.pump();

    expect(state.toggled, [1], reason: 'the circle asks the state to toggle');
    expect(
      server.requests.where((r) => r == 'POST /api/v1/tasks/1'),
      hasLength(1),
      reason: 'the toggle is written to the server once',
    );
    expect(state.taskById(1)!.done, isTrue);
    expect(
      find.text('Fix bike'),
      findsNothing,
      reason: 'a done task leaves the open list',
    );
    expect(find.text('Done'), findsOneWidget, reason: 'it moved to Done');
  });

  testWidgets('the entry bar submits a task and it appears in the list', (
    tester,
  ) async {
    final server = HomeServer(tasks: [taskJson(1, 'Fix bike')]);
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    await tester.pump();

    expect(state.added, ['Buy milk']);
    expect(
      server.requests.where((r) => r == 'PUT /api/v1/projects/1/tasks'),
      hasLength(1),
    );
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('tapping a row opens the task detail screen', (tester) async {
    final server = HomeServer(tasks: [taskJson(1, 'Fix bike')]);
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pump();

    await tester.tap(find.text('Fix bike'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(
      find.text('Set Description'),
      findsOneWidget,
      reason: 'the detail screen is showing the task it was opened for',
    );
  });

  testWidgets('tapping the drawer name or avatar opens account settings', (
    tester,
  ) async {
    final server = HomeServer(tasks: [taskJson(1, 'Fix bike')]);
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pump();

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('me'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountSettingsScreen), findsOneWidget);
    expect(
      find.text('Account settings'),
      findsOneWidget,
      reason: 'the drawer closed and the account screen opened',
    );
  });

  testWidgets('system back from another list returns to Due Today', (
    tester,
  ) async {
    final server = HomeServer(tasks: [taskJson(1, 'Fix bike')]);
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pump();

    await state.select(const ListSelection.smart(SmartList.allTasks));
    await tester.pump();
    expect(find.text('All Tasks'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.text('Due Today'),
      findsOneWidget,
      reason: 'the list the session started on, instead of leaving the app',
    );
  });
}
