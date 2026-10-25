import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/project_settings_screen.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/entry_bar.dart';

/// The hardware back button used to drop whatever was typed on the way out.
/// A screen with unsaved text asks first; a screen with nothing to lose leaves
/// immediately, as before.
void main() {
  late int exitCalls;

  setUp(() {
    exitCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exitCalls++;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> back(WidgetTester tester) async {
    // What the platform sends for the hardware back button / back gesture.
    await tester.binding.handlePopRoute();
    await tester.pump();
  }

  group('entry bar draft', () {
    Future<void> pumpBar(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTodoTheme(TodoColors.gruvboxLight),
          home: Scaffold(body: EntryBar(onSubmit: (title) async {})),
        ),
      );
    }

    testWidgets('back asks before dropping a typed task', (tester) async {
      await pumpBar(tester);
      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.pump();

      await back(tester);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(EntryBar), findsOneWidget);
      expect(exitCalls, 0, reason: 'the first press only asks');

      await tester.tap(find.text('Keep editing'));
      await tester.pump();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Buy milk'), findsOneWidget, reason: 'the draft stays');

      // The second press is the confirmation.
      await back(tester);
      expect(exitCalls, 1, reason: 'confirmed, the app goes away');
    });

    testWidgets('back with an empty bar leaves at once', (tester) async {
      await pumpBar(tester);

      await back(tester);

      expect(find.text('Discard changes?'), findsNothing);
      expect(exitCalls, 1, reason: 'nothing to lose, no dialog');
    });
  });

  group('task detail', () {
    late int saves;

    Future<AppState> state() async {
      saves = 0;
      final state = AppState();
      state.api = VikunjaApi(
        baseUrl: 'https://tasks.example.com',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/tasks/1') &&
              request.method == 'POST') {
            saves++;
            return http.Response(request.body, 200);
          }
          if (request.url.path.endsWith('/tasks/1')) {
            return http.Response(
              jsonEncode({'id': 1, 'project_id': 1, 'title': 'Fix bike'}),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      state.user = const VikunjaUser(id: 1, username: 'me');
      return state;
    }

    Future<void> openDetail(WidgetTester tester, AppState appState) async {
      await tester.pumpWidget(
        AppScope(
          state: appState,
          child: MaterialApp(
            theme: buildTodoTheme(TodoColors.gruvboxLight),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TaskDetailScreen(taskId: 1),
                      ),
                    ),
                    child: const Text('open task'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open task'));
      // The detail screen keeps a progress indicator while it loads, so the
      // route transition is pumped by hand instead of with pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('back asks before a pending title edit and can drop it', (
      tester,
    ) async {
      final appState = await state();
      await openDetail(tester, appState);

      await tester.enterText(find.byType(TextField).first, 'Buy oat milk');
      await tester.pump();

      await back(tester);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(TaskDetailScreen), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailScreen), findsNothing);
      expect(saves, 0, reason: 'a discarded edit is not saved on the way out');
    });

    testWidgets('an untouched detail screen leaves on the first press', (
      tester,
    ) async {
      final appState = await state();
      await openDetail(tester, appState);

      await back(tester);
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(TaskDetailScreen), findsNothing);
    });
  });

  group('project settings', () {
    testWidgets('back asks before an unsaved name', (tester) async {
      final state = AppState();
      state.api = VikunjaApi(
        baseUrl: 'https://tasks.example.com',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'frontend_url': 'https://tasks.example.com'}),
            200,
          ),
        ),
      );
      state.user = const VikunjaUser(id: 1, username: 'me');

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: buildTodoTheme(TodoColors.gruvboxLight),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProjectSettingsScreen(
                          project: VikunjaProject(id: 1, title: 'Inbox'),
                        ),
                      ),
                    ),
                    child: const Text('open project'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open project'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Errands');
      await tester.pump();

      await back(tester);
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(ProjectSettingsScreen), findsNothing);
    });
  });
}
