import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const HomeScreen(),
  ),
);

/// A signed-in state holding one task due today, over the endpoints
/// `refresh()` reads.
Future<AppState> signedInWithTask([AppState? state]) async {
  final appState = state ?? AppState();
  appState.api = VikunjaApi(
    baseUrl: 'https://tasks.example.com',
    client: MockClient((request) async {
      if (request.url.path.endsWith('/tasks')) {
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'project_id': 1,
              'title': 'Fix bike',
              'due_date': DateTime.now().toUtc().toIso8601String(),
            },
          ]),
          200,
        );
      }
      return http.Response('[]', 200);
    }),
  );
  appState.user = const VikunjaUser(id: 1, username: 'me');
  await appState.refresh();
  return appState;
}

/// A state whose delete reports a failure through `error`, like `AppState`.
class DeletingState extends AppState {
  int deletes = 0;

  @override
  Future<String?> deleteTask(VikunjaTask task) async {
    deletes++;
    return 'Could not delete the task';
  }
}

Future<void> openTaskMenuDelete(WidgetTester tester) async {
  await tester.longPress(find.text('Fix bike'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Delete'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Delete'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// A signed-in state holding two open tasks across two projects, one label.
Future<AppState> stateWithDrawerData() async {
  final state = AppState();
  state.api = VikunjaApi(
    baseUrl: 'https://tasks.example.com',
    client: MockClient((request) async {
      final path = request.url.path;
      final now = DateTime.now();
      if (path.endsWith('/projects')) {
        return http.Response(
          jsonEncode([
            {'id': 1, 'title': 'Inbox'},
            {'id': 2, 'title': 'Work'},
          ]),
          200,
        );
      }
      if (path.endsWith('/labels')) {
        return http.Response(
          jsonEncode([
            {'id': 5, 'title': 'errand', 'hex_color': '#1174E4'},
          ]),
          200,
        );
      }
      if (path.endsWith('/tasks')) {
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'project_id': 1,
              'title': 'Fix bike',
              'due_date': now.toUtc().toIso8601String(),
              'labels': [
                {'id': 5, 'title': 'errand', 'hex_color': '#1174E4'},
              ],
            },
            {
              'id': 2,
              'project_id': 2,
              'title': 'Write report',
              'due_date': now.add(const Duration(days: 3)).toUtc().toIso8601String(),
            },
          ]),
          200,
        );
      }
      return http.Response('[]', 200);
    }),
  );
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

Finder inDrawer(Finder finder) =>
    find.descendant(of: find.byType(Drawer), matching: finder);

Finder rowTrailing(String label, String count) => find.descendant(
  of: find
      .ancestor(of: inDrawer(find.text(label)), matching: find.byType(InkWell))
      .first,
  matching: find.text(count),
);

void main() {
  testWidgets('a failed task delete is surfaced instead of vanishing', (
    tester,
  ) async {
    final state = await signedInWithTask(DeletingState());
    await tester.pumpWidget(host(state));
    await tester.pump();
    expect(find.text('Fix bike'), findsOneWidget);

    await openTaskMenuDelete(tester);

    expect((state as DeletingState).deletes, 1);
    expect(find.text('Could not delete the task'), findsOneWidget);
  });

  testWidgets('the drawer counts every list, project and label', (
    tester,
  ) async {
    final state = await stateWithDrawerData();
    await tester.pumpWidget(host(state));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(inDrawer(find.text('Inbox')), findsOneWidget);
    expect(inDrawer(find.text('Work')), findsOneWidget);
    expect(inDrawer(find.text('errand')), findsOneWidget);
    expect(rowTrailing('All Tasks', '2'), findsOneWidget);
    expect(rowTrailing('Due Today', '1'), findsOneWidget);
    expect(rowTrailing('Inbox', '1'), findsOneWidget);
    expect(rowTrailing('Work', '1'), findsOneWidget);
    expect(rowTrailing('errand', '1'), findsOneWidget);
  });
}
