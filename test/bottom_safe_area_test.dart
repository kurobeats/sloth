import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/account_settings_screen.dart';
import 'package:sloth/screens/board_screen.dart';
import 'package:sloth/screens/notifications_screen.dart';
import 'package:sloth/screens/search_screen.dart';
import 'package:sloth/screens/settings_screen.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/screens/team_detail_screen.dart';
import 'package:sloth/screens/teams_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

Widget host(AppState state, Widget screen) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: screen,
  ),
);

/// A 48dp gesture bar under a 600x800 viewport.
void gestureBarView(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 800);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(bottom: 48);
  addTearDown(tester.view.reset);
}

void main() {
  final screens = <({String name, Widget screen, Finder content})>[
    (
      name: 'account settings',
      screen: const AccountSettingsScreen(),
      content: find.byType(ListView),
    ),
    (
      name: 'board',
      screen: const BoardScreen(project: VikunjaProject(id: 1, title: 'Inbox')),
      content: find.byType(Column).first,
    ),
    (
      name: 'notifications',
      screen: const NotificationsScreen(),
      content: find.byType(RefreshIndicator),
    ),
    (
      name: 'search',
      screen: const SearchScreen(),
      content: find.byType(Center).first,
    ),
    (
      name: 'settings',
      screen: const SettingsScreen(),
      content: find.byType(ListView),
    ),
    (
      name: 'team detail',
      screen: const TeamDetailScreen(teamId: 1),
      content: find.byType(ListView),
    ),
    (
      name: 'teams',
      screen: const TeamsScreen(),
      content: find.byType(RefreshIndicator),
    ),
  ];

  for (final entry in screens) {
    testWidgets('${entry.name} keeps its content above the gesture bar', (
      tester,
    ) async {
      gestureBarView(tester);
      final state = AppState()
        ..teams = const [VikunjaTeam(id: 1, name: 'Household')];
      await tester.pumpWidget(host(state, entry.screen));
      await tester.pump();
      await tester.pump();

      expect(
        MediaQuery.paddingOf(tester.element(find.byType(Scaffold))).bottom,
        48,
        reason: 'the test viewport has a gesture bar',
      );
      expect(
        MediaQuery.paddingOf(tester.element(entry.content)).bottom,
        0,
        reason: 'the body must consume the bottom inset itself',
      );
    });
  }

  // The comment box is the last thing on this screen. Without a bottom inset it
  // renders under the gesture bar, where neither the field nor its send button
  // can be tapped — the task detail screen has no project list of its own, so it
  // was missed when the others got their inset.
  testWidgets('task detail keeps its comment box above the gesture bar', (
    tester,
  ) async {
    gestureBarView(tester);
    final state = AppState();
    state.api = VikunjaApi(
      baseUrl: 'https://tasks.example.com',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/user')) {
          return http.Response('{"id":1,"username":"me"}', 200);
        }
        if (path.endsWith('/tasks/1')) {
          return http.Response(
            jsonEncode({'id': 1, 'project_id': 1, 'title': 'Fix bike'}),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    await tester.pumpWidget(host(state, const TaskDetailScreen(taskId: 1)));
    await tester.pumpAndSettle();

    final list = find.byType(ListView);
    expect(list, findsWidgets, reason: 'the detail body is on screen');
    expect(
      MediaQuery.paddingOf(tester.element(list.first)).bottom,
      0,
      reason: 'the body must consume the bottom inset itself',
    );
  });
}
