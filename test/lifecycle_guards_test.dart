import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/screens/notifications_screen.dart';
import 'package:sloth/screens/project_settings_screen.dart';
import 'package:sloth/screens/search_screen.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/notification_tile.dart';
import 'package:sloth/widgets/task_extras.dart';

Widget host(AppState state, Widget child) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: child,
  ),
);

VikunjaTask taskOne({List<VikunjaUser> assignees = const []}) => VikunjaTask(
  id: 1,
  projectId: 1,
  title: 'Fix bike',
  assignees: assignees,
);

/// A [Navigator] whose `push` future the test finishes by hand, so a screen can
/// be unmounted before the awaited route "returns".
class SpyNavigator extends Navigator {
  const SpyNavigator({super.key, required super.onGenerateRoute});

  @override
  NavigatorState createState() => SpyNavigatorState();
}

class SpyNavigatorState extends NavigatorState {
  bool intercept = false;
  Completer<Object?>? pending;

  @override
  Future<T?> push<T extends Object?>(Route<T> route) {
    if (!intercept) return super.push(route);
    final completer = Completer<Object?>();
    pending = completer;
    return completer.future.then((value) => value as T?);
  }
}

/// An [AppState] whose writes stay pending until the test completes them.
class FakeState extends AppState {
  VikunjaTask? task;
  final important = Completer<void>();
  final removed = Completer<String?>();
  final searches = <String, Completer<List<VikunjaTask>>>{};
  Object? searchError;

  @override
  Future<VikunjaTask?> loadTask(int id) async => task;

  /// The detail screen reads the task from the state, not from its own copy.
  @override
  VikunjaTask? taskById(int id) => task;

  @override
  Future<void> toggleImportant(VikunjaTask task) => important.future;

  @override
  Future<String?> unassign(VikunjaTask task, VikunjaUser user) => removed.future;

  @override
  Future<String?> unshareUser(int projectId, int userId) => removed.future;

  @override
  Future<String?> loadNotifications() async => null;

  @override
  Future<List<VikunjaTask>> searchTasks(String query) {
    final error = searchError;
    if (error != null) return Future.error(error);
    final completer = Completer<List<VikunjaTask>>();
    searches[query] = completer;
    return completer.future;
  }
}

/// A signed-in state holding one task, over the endpoints `refresh()` reads.
Future<AppState> signedInWithTask() async {
  final state = AppState();
  state.api = VikunjaApi(
    baseUrl: 'https://tasks.example.com',
    client: MockClient((request) async {
      if (request.url.path.endsWith('/tasks')) {
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'project_id': 1,
              'title': 'Fix bike',
              // Due today, so the default smart list lists it.
              'due_date': DateTime.now().toUtc().toIso8601String(),
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

void main() {
  group('F-006 task detail favorite', () {
    testWidgets('favoriting after the detail screen closes touches no state', (
      tester,
    ) async {
      final state = FakeState()..task = taskOne();
      await tester.pumpWidget(host(state, const TaskDetailScreen(taskId: 1)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pump();

      // The write lands after the screen is gone.
      await tester.pumpWidget(const SizedBox());
      state.important.complete();
      await tester.pump();
    });
  });

  group('F-007 home task menu', () {
    testWidgets('a menu action landing after the screen closes uses no context', (
      tester,
    ) async {
      final state = await signedInWithTask();
      final navKey = GlobalKey<SpyNavigatorState>();
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: buildTodoTheme(TodoColors.gruvboxLight),
            home: SpyNavigator(
              key: navKey,
              onGenerateRoute: (_) =>
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Fix bike'), findsOneWidget);

      final nav = navKey.currentState!..intercept = true;
      await tester.longPress(find.text('Fix bike'));
      await tester.pump();
      expect(nav.pending, isNotNull, reason: 'the task menu was asked for');

      await tester.pumpWidget(const SizedBox());
      nav.pending!.complete('delete');
      await tester.pump();
    });
  });

  group('F-008 notifications', () {
    testWidgets('returning from a task after the list is gone does not reload', (
      tester,
    ) async {
      final state = FakeState()
        ..notifications = [
          const VikunjaNotification(
            id: 1,
            name: 'task.assigned',
            taskId: 3,
            taskTitle: 'Fix bike',
          ),
        ];
      final navKey = GlobalKey<SpyNavigatorState>();
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: buildTodoTheme(TodoColors.gruvboxLight),
            home: SpyNavigator(
              key: navKey,
              onGenerateRoute: (_) =>
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotificationTile), findsOneWidget);

      final nav = navKey.currentState!..intercept = true;
      await tester.tap(find.byType(NotificationTile));
      await tester.pump();
      expect(nav.pending, isNotNull, reason: 'the task route was pushed');

      await tester.pumpWidget(const SizedBox());
      nav.pending!.complete(null);
      await tester.pump();
    });
  });

  group('F-009 project settings shares', () {
    testWidgets('a share removal landing after the screen closes does not reload', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = FakeState();
      state.api = VikunjaApi(
        baseUrl: 'https://tasks.example.com',
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/projects/1/users')) {
            return http.Response(
              jsonEncode([
                {'id': 7, 'username': 'joe', 'name': 'Joe', 'permission': 1},
              ]),
              200,
            );
          }
          if (path.endsWith('/projects/1/teams') ||
              path.endsWith('/projects/1/shares')) {
            return http.Response('[]', 200);
          }
          return http.Response(
            jsonEncode({'frontend_url': 'https://tasks.example.com'}),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        host(
          state,
          const ProjectSettingsScreen(
            project: VikunjaProject(id: 1, title: 'Inbox'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Joe'), findsOneWidget, reason: 'the share list loaded');

      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      state.removed.complete(null);
      await tester.pump();
    });
  });

  group('F-010 task extras callbacks', () {
    testWidgets('removing an assignee after the screen closes calls no back', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = FakeState()
        ..task = taskOne(
          assignees: [const VikunjaUser(id: 2, username: 'joe', name: 'Joe')],
        );
      await tester.pumpWidget(host(state, const TaskDetailScreen(taskId: 1)));
      await tester.pump();
      expect(find.byTooltip('Remove assignee'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove assignee'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      state.removed.complete(null);
      await tester.pump();
    });
  });

  group('F-011 search', () {
    testWidgets('a slow older query does not replace newer results', (
      tester,
    ) async {
      final state = FakeState();
      await tester.pumpWidget(host(state, const SearchScreen()));

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 350));
      expect(state.searches.keys, containsAll(<String>['a', 'ab']));

      state.searches['ab']!.complete([taskOne()]);
      await tester.pump();
      expect(find.text('Fix bike'), findsOneWidget);

      state.searches['a']!.complete([
        VikunjaTask(id: 9, projectId: 1, title: 'Stale result'),
      ]);
      await tester.pump();
      expect(
        find.text('Stale result'),
        findsNothing,
        reason: 'the answer to the older query must not win',
      );
      expect(find.text('Fix bike'), findsOneWidget);
    });

    testWidgets('a failed search clears the spinner and says so', (
      tester,
    ) async {
      final state = FakeState()
        ..searchError = VikunjaException(500, 'Server said no');
      await tester.pumpWidget(host(state, const SearchScreen()));

      await tester.enterText(find.byType(TextField), 'bike');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Server said no'), findsOneWidget);
    });
  });

  group('F-012 relation search sheet', () {
    testWidgets('a failed search leaves no permanent spinner', (tester) async {
      final state = FakeState()
        ..searchError = VikunjaException(500, 'Server said no');
      await tester.pumpWidget(
        host(
          state,
          RelationsSection(task: taskOne(), onChanged: () {}),
        ),
      );

      await tester.tap(find.text('Add relation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VikunjaRelation.label(VikunjaRelation.related)));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.enterText(find.byType(TextField), 'bike');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'the spinner must stop when the search fails',
      );
      expect(find.text('Server said no'), findsOneWidget);
    });
  });

  group('F-013 new project while signed out', () {
    testWidgets('a session that ends mid-dialog surfaces no null-check error', (
      tester,
    ) async {
      final state = await signedInWithTask();
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

      // The session expires while the dialog is still open.
      state.api = null;
      await tester.tap(find.text('Create project'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not create project'), findsNothing);
    });
  });
}
