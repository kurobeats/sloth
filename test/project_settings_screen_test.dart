import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/project_settings_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const ProjectSettingsScreen(project: VikunjaProject(id: 1, title: 'Inbox')),
  ),
);

/// A state whose project-shares endpoints answer with [users] and [teams].
AppState sharedState({
  required List<Map<String, dynamic>> users,
  List<Map<String, dynamic>> teams = const [],
}) {
  final state = AppState();
  state.api = VikunjaApi(
    baseUrl: 'https://tasks.example.com',
    client: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/projects/1/users')) {
        return http.Response(jsonEncode(users), 200);
      }
      if (path.endsWith('/projects/1/teams')) {
        return http.Response(jsonEncode(teams), 200);
      }
      if (path.endsWith('/projects/1/shares')) return http.Response('[]', 200);
      return http.Response(
        jsonEncode({'frontend_url': 'https://tasks.example.com'}),
        200,
      );
    }),
  );
  return state;
}

void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a user share without a user id cannot crash removal', (
    tester,
  ) async {
    tallView(tester);
    // Vikunja answers with the display name but no `id` field.
    final state = sharedState(
      users: [
        {'name': 'Joe', 'permission': 1},
      ],
    );
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(find.text('Joe'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a team share without a team id cannot crash removal', (
    tester,
  ) async {
    tallView(tester);
    final state = sharedState(
      users: const [],
      teams: [
        {'name': 'Household', 'permission': 1},
      ],
    );
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(find.text('Household'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed save reports the error instead of "Project saved"', (
    tester,
  ) async {
    tallView(tester);
    // Offline: `saveProject` fails without touching the network.
    final state = AppState()..offline = true;
    await tester.pumpWidget(host(state));
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Project saved'), findsNothing);
    expect(find.text(AppState.offlineEditError), findsOneWidget);
  });
}
