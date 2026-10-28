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

/// Closing the detail screen while a title edit is still inside the 700ms
/// debounce must save it — and must not touch the inherited scope from
/// `dispose()`, which runs on a deactivated element.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TaskDetailScreen(taskId: 1)),
        ),
        child: const Text('open task'),
      ),
    ),
  );
}

void main() {
  late int saves;
  late String? savedTitle;
  late Map<String, dynamic>? savedBody;

  Future<AppState> state() async {
    saves = 0;
    savedTitle = null;
    savedBody = null;
    final task = {'id': 1, 'project_id': 1, 'title': 'Original title'};
    final state = AppState();
    state.api = VikunjaApi(
      baseUrl: 'https://tasks.example.com',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/tasks/1') && request.method == 'POST') {
          saves++;
          savedBody = jsonDecode(request.body) as Map<String, dynamic>;
          savedTitle = savedBody!['title'] as String?;
          return http.Response(request.body, 200);
        }
        if (path.endsWith('/tasks/1')) {
          return http.Response(jsonEncode(task), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    state.user = const VikunjaUser(id: 1, username: 'me');
    return state;
  }

  testWidgets('a pending title is saved when the screen is popped', (
    tester,
  ) async {
    final appState = await state();
    await tester.pumpWidget(
      AppScope(
        state: appState,
        child: MaterialApp(
          theme: buildTodoTheme(TodoColors.gruvboxLight),
          home: const _Host(),
        ),
      ),
    );

    await tester.tap(find.text('open task'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Buy oat milk');
    await tester.pump(); // the edit is in, the 700ms debounce is still pending

    Navigator.of(tester.element(find.byType(TaskDetailScreen))).pop();
    // Pump the exit transition by hand: pumpAndSettle keeps pumping for the
    // text cursor, which would let the 700ms debounce fire and hide the bug.
    for (var i = 0; i < 8 && find.byType(TaskDetailScreen).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(TaskDetailScreen), findsNothing);
    await tester.pump(const Duration(seconds: 1)); // nothing may fire twice

    expect(
      tester.takeException(),
      isNull,
      reason: 'dispose() looked up the inherited scope on a dead element',
    );
    expect(saves, 1, reason: 'the pending title is flushed exactly once');
    expect(
      savedTitle,
      'Buy oat milk',
      reason: 'the pending edit is what gets sent',
    );
  });

  testWidgets('ticking the check leaves the screen, the way back does', (
    tester,
  ) async {
    final appState = await state();
    await tester.pumpWidget(
      AppScope(
        state: appState,
        child: MaterialApp(
          theme: buildTodoTheme(TodoColors.gruvboxLight),
          home: const _Host(),
        ),
      ),
    );

    await tester.tap(find.text('open task'));
    await tester.pumpAndSettle();

    // A title is still inside the debounce: it must not be dropped on the way
    // out, and it must not raise the discard dialog either.
    await tester.enterText(find.byType(TextField).first, 'Buy oat milk');
    await tester.pump();

    await tester.tap(find.byType(AnimatedContainer).first);
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailScreen), findsNothing);
    expect(find.text('open task'), findsOneWidget, reason: 'back where we came from');
    expect(savedBody?['done'], isTrue, reason: 'the task is completed');
    expect(savedTitle, 'Buy oat milk', reason: 'the typed title went with it');
  });
}
