import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/board_screen.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

const _server = 'https://tasks.example.com';

const _kanban = VikunjaProject(
  id: 1,
  title: 'Inbox',
  views: [VikunjaView(id: 4, title: 'Kanban', viewKind: 'kanban')],
);

/// One fake server for the board: the same two columns a live Vikunja returns,
/// plus a record of every request so a move can be counted.
class BoardServer {
  final requests = <String>[];
  final moves = <Map<String, dynamic>>[];
  int bucketStatus = 200;

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    final method = request.method;
    requests.add('$method $path');
    if (path.contains('/views/4/buckets/')) {
      moves.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        bucketStatus == 200 ? '{}' : '{"message":"Move failed"}',
        bucketStatus,
      );
    }
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
    final single = RegExp(r'/tasks/(\d+)$').firstMatch(path);
    if (single != null) {
      final id = int.parse(single.group(1)!);
      return http.Response(
        jsonEncode({
          'id': id,
          'title': id == 2 ? 'Buy milk' : 'Fix bike',
          'project_id': 1,
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
    return http.Response('[]', 200);
  });

  Future<AppState> state() async {
    final state = AppState();
    state.api = VikunjaApi(baseUrl: _server, client: client());
    state.user = const VikunjaUser(id: 1, username: 'me');
    return state;
  }

  Iterable<String> get bucketPosts =>
      requests.where((r) => r.contains('/buckets/'));
}

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const BoardScreen(project: _kanban),
  ),
);

void wideView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the columns render their titles and bucket counts', (
    tester,
  ) async {
    wideView(tester);
    final server = BoardServer();
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    expect(find.text('To-Do'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'To-Do holds two cards');
    expect(find.text('0'), findsOneWidget, reason: 'Doing holds none');
    expect(find.text('Fix bike'), findsOneWidget);
  });

  testWidgets('an empty column says it is empty', (tester) async {
    wideView(tester);
    final server = BoardServer();
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    expect(find.text('No tasks'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('No tasks'),
          matching: find.byType(DragTarget<int>),
        ),
        matching: find.text('Doing'),
      ),
      findsOneWidget,
      reason: 'the notice belongs to the empty column, not the filled one',
    );
  });

  testWidgets('dragging a card to another column moves it exactly once', (
    tester,
  ) async {
    wideView(tester);
    final server = BoardServer();
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    // A real drag, not a callback poke: the card leaves the To-Do column and
    // lands over Doing.
    final card = tester.getCenter(find.text('Fix bike'));
    final target = tester.getCenter(find.text('Doing'));
    final gesture = await tester.startGesture(card);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(Offset(target.dx, card.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(server.bucketPosts, hasLength(1), reason: 'one move, not two');
    expect(server.moves.single['task_id'], 1);
    expect(server.moves.single['bucket_id'], 2);
    expect(state.bucketsFor(_kanban)![1].tasks.map((t) => t.id), [1]);
  });

  testWidgets('tapping a card opens that task', (tester) async {
    wideView(tester);
    final server = BoardServer();
    final state = await server.state();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(
      server.requests.where((r) => r == 'GET /api/v1/tasks/2'),
      hasLength(1),
      reason: 'the card opened its own task',
    );
    expect(find.byType(BoardScreen), findsNothing, reason: 'the route covered it');
  });
}
