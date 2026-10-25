import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/board_screen.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/screens/login_screen.dart';
import 'package:sloth/screens/project_settings_screen.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/screens/team_detail_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

const _server = 'https://tasks.example.com';

Widget host(AppState state, Widget child) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: child,
  ),
);

void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// One fake server for every screen here: it records what the widgets asked
/// for, so a call that should have been stopped by the offline guard shows up.
class ScreenServer {
  final List<String> requests = [];
  int bucketStatus = 200;
  List<Map<String, dynamic>> tasks = [
    {
      'id': 1,
      'project_id': 1,
      'title': 'Original title',
      'description': 'Note',
    },
  ];

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    final method = request.method;
    requests.add('$method $path');
    if (path.endsWith('/info')) return http.Response('{}', 200);
    if (path.endsWith('/user')) {
      return http.Response('{"id":1,"username":"me"}', 200);
    }
    if (path.contains('/avatar/')) return http.Response('', 404);
    if (path.contains('/views/4/tasks')) {
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'title': 'To-Do',
            'tasks': [
              {'id': 1, 'title': 'Fix bike', 'project_id': 1},
              {'id': 2, 'title': 'Buy milk', 'project_id': 1},
            ],
          },
          {'id': 2, 'title': 'Doing', 'tasks': []},
        ]),
        200,
      );
    }
    if (path.contains('/buckets/')) {
      return http.Response(
        bucketStatus == 200 ? '{}' : '{"message":"Move failed"}',
        bucketStatus,
      );
    }
    if (path.endsWith('/tasks')) {
      return http.Response(jsonEncode(tasks), 200);
    }
    if (path.endsWith('/tasks/1')) {
      if (method == 'POST') return http.Response(request.body, 200);
      return http.Response(jsonEncode(tasks.single), 200);
    }
    if (path.endsWith('/projects/1/users')) {
      return http.Response('[]', 200);
    }
    if (path.endsWith('/projects/1/teams')) return http.Response('[]', 200);
    if (path.endsWith('/projects/1/shares')) {
      return http.Response(
        jsonEncode([
          {'id': 5, 'hash': 'abc', 'name': 'Public link', 'permission': 0},
        ]),
        200,
      );
    }
    if (path.contains('/projects/1/shares/')) return http.Response('{}', 200);
    if (method == 'PUT' && path.endsWith('/projects')) {
      return http.Response('{"id": 9, "title": "New list"}', 200);
    }
    if (path.endsWith('/teams/1')) {
      return http.Response(
        jsonEncode({
          'id': 1,
          'name': 'Household',
          'members': [
            {'id': 1, 'username': 'me', 'admin': true},
          ],
        }),
        200,
      );
    }
    return http.Response('[]', 200);
  });

  AppState state({bool offline = false}) => AppState()
    ..api = VikunjaApi(baseUrl: _server, client: client())
    ..user = const VikunjaUser(id: 1, username: 'me')
    ..offline = offline;
}

const _kanban = VikunjaProject(
  id: 1,
  title: 'Inbox',
  views: [VikunjaView(id: 4, title: 'Kanban', viewKind: 'kanban')],
);

void main() {
  group('F-054 share screens', () {
    testWidgets('deleting a link share offline never reaches the api', (
      tester,
    ) async {
      tallView(tester);
      final server = ScreenServer();
      final state = server.state();
      await tester.pumpWidget(
        host(
          state,
          const ProjectSettingsScreen(
            project: VikunjaProject(id: 1, title: 'Inbox'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Public link'), findsOneWidget);

      state.offline = true;
      await tester.tap(find.byTooltip('Delete link share'));
      await tester.pumpAndSettle();

      expect(
        server.requests.where((r) => r.startsWith('DELETE')),
        isEmpty,
        reason: 'the screen bypassed the offline guard and called api directly',
      );
      expect(find.text(AppState.offlineEditError), findsOneWidget);
    });

    testWidgets('creating a project offline never reaches the api', (
      tester,
    ) async {
      tallView(tester);
      final server = ScreenServer();
      final state = server.state(offline: true);
      await tester.pumpWidget(host(state, const HomeScreen()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New project'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'New list',
      );
      await tester.tap(find.text('Create project'));
      await tester.pumpAndSettle();

      expect(
        server.requests.where((r) => r.startsWith('PUT /api/v1/projects')),
        isEmpty,
      );
      expect(find.text(AppState.offlineEditError), findsOneWidget);
    });
  });

  group('F-055 team admin', () {
    testWidgets('the screen renders what the state decided', (tester) async {
      tallView(tester);
      final server = ScreenServer();
      final state = RefusingState(server.state())
        ..teams = const [VikunjaTeam(id: 1, name: 'Household')];
      server.requests.clear();

      await tester.pumpWidget(host(state, const TeamDetailScreen(teamId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();

      expect(state.called, isTrue, reason: 'the screen asked the state');
      expect(find.text('State refused it'), findsOneWidget);
    });
  });

  group('F-056 task detail', () {
    testWidgets('a task changed in the state shows without a reload', (
      tester,
    ) async {
      tallView(tester);
      final server = ScreenServer();
      final state = server.state();
      await state.refresh();
      await tester.pumpWidget(host(state, const TaskDetailScreen(taskId: 1)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_border), findsOneWidget);

      await state.toggleImportant(state.taskById(1)!);
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.star),
        findsOneWidget,
        reason: 'the screen kept its own copy of the task',
      );
      expect(find.byIcon(Icons.star_border), findsNothing);
    });

    testWidgets('a title edit still posts the rest of the task', (
      tester,
    ) async {
      tallView(tester);
      final server = ScreenServer();
      final state = server.state();
      await state.refresh();
      await tester.pumpWidget(host(state, const TaskDetailScreen(taskId: 1)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Buy oat milk');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      final posted = server.requests.where((r) => r == 'POST /api/v1/tasks/1');
      expect(posted, hasLength(1));
      expect(state.taskById(1)!.title, 'Buy oat milk');
      expect(
        state.taskById(1)!.description,
        'Note',
        reason: 'the update carries every field, as before',
      );
    });
  });

  group('F-057 board', () {
    testWidgets('a drop re-renders from the state buckets', (tester) async {
      tallView(tester);
      final server = ScreenServer();
      final state = server.state();
      await tester.pumpWidget(host(state, const BoardScreen(project: _kanban)));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget, reason: 'To-Do holds two cards');
      expect(find.text('0'), findsOneWidget, reason: 'Doing is empty');

      // Drop the first card on the second column.
      final target = tester.widget<DragTarget<int>>(
        find.byType(DragTarget<int>).at(1),
      );
      target.onAcceptWithDetails!(
        DragTargetDetails<int>(data: 1, offset: Offset.zero),
      );
      await tester.pumpAndSettle();

      expect(state.bucketsFor(_kanban)![1].tasks.map((t) => t.id), [1]);
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNWidgets(2), reason: 'one card each');
    });

    testWidgets('a failed move puts the card back', (tester) async {
      tallView(tester);
      final server = ScreenServer()..bucketStatus = 500;
      final state = server.state();
      await tester.pumpWidget(host(state, const BoardScreen(project: _kanban)));
      await tester.pumpAndSettle();

      final target = tester.widget<DragTarget<int>>(
        find.byType(DragTarget<int>).at(1),
      );
      target.onAcceptWithDetails!(
        DragTargetDetails<int>(data: 1, offset: Offset.zero),
      );
      await tester.pumpAndSettle();

      expect(find.text('Move failed'), findsOneWidget);
      expect(state.bucketsFor(_kanban)![1].tasks, isEmpty);
      expect(find.text('2'), findsOneWidget, reason: 'To-Do still holds both');
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('F-058 login prefill', () {
    testWidgets('the first build prefills the remembered server', (
      tester,
    ) async {
      final state = AppState()..lastServer = 'https://tasks.example.com';
      await tester.pumpWidget(host(state, const LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('https://tasks.example.com'), findsOneWidget);
    });

    testWidgets('a remembered server arriving later keeps what was typed', (
      tester,
    ) async {
      final state = AppState();
      await tester.pumpWidget(host(state, const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'https://typed.example.com',
      );
      await tester.pump();

      // The session restore finishes after the first frame.
      state.lastServer = 'https://tasks.example.com';
      state.notifyListeners();
      await tester.pumpAndSettle();

      expect(
        find.text('https://typed.example.com'),
        findsOneWidget,
        reason: 'build() prefilled and overwrote the typed server',
      );
      expect(
        find.text('https://tasks.example.com'),
        findsNothing,
        reason: 'the remember-and-prefill must not run twice',
      );
    });
  });
}

/// An [AppState] that decides the team rule itself, so the screen can be shown
/// to render its answer instead of computing one.
class RefusingState extends AppState {
  RefusingState(AppState source) {
    api = source.api;
    user = source.user;
  }

  bool called = false;

  @override
  Future<String?> toggleTeamMemberAdmin(int teamId, String username) async {
    called = true;
    return 'State refused it';
  }
}
