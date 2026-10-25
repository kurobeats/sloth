import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/screens/labels_screen.dart';
import 'package:sloth/screens/project_settings_screen.dart';
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

void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens the dialog, types into it, then cancels: twice, so a controller that
/// outlives its dialog shows up as a stale text in the next open.
Future<void> openTypeCancelTwice(
  WidgetTester tester, {
  required Future<void> Function() open,
  required String typed,
  required String cancelLabel,
}) async {
  for (var i = 0; i < 2; i++) {
    await open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, typed);
    await tester.tap(find.text(cancelLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets('the label dialog opens and closes twice', (tester) async {
    tallView(tester);
    final state = AppState();
    await tester.pumpWidget(host(state, const LabelsScreen()));
    await tester.pump();

    await openTypeCancelTwice(
      tester,
      open: () async => tester.tap(find.byTooltip('New label')),
      typed: 'errand',
      cancelLabel: 'Cancel',
    );
  });

  testWidgets('the new team dialog opens and closes twice', (tester) async {
    tallView(tester);
    final state = AppState();
    await tester.pumpWidget(host(state, const TeamsScreen()));
    await tester.pump();

    await openTypeCancelTwice(
      tester,
      open: () async => tester.tap(find.byTooltip('New team')),
      typed: 'Household',
      cancelLabel: 'Cancel',
    );
  });

  testWidgets('the new project dialog opens and closes twice', (tester) async {
    tallView(tester);
    final state = AppState();
    await tester.pumpWidget(host(state, const HomeScreen()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await openTypeCancelTwice(
      tester,
      open: () async => tester.tap(find.byTooltip('New project')),
      typed: 'Inbox',
      cancelLabel: 'Cancel',
    );
  });

  testWidgets('the new link share dialog opens and closes twice', (
    tester,
  ) async {
    tallView(tester);
    // Offline has no api, so the share lists stay empty and no request is made.
    final state = AppState()..offline = true;
    await tester.pumpWidget(
      host(
        state,
        const ProjectSettingsScreen(project: VikunjaProject(id: 1, title: 'Inbox')),
      ),
    );
    await tester.pump();

    await openTypeCancelTwice(
      tester,
      open: () async =>
          tester.tap(find.widgetWithText(TextButton, 'Create link share')),
      typed: 'Shared link',
      cancelLabel: 'Cancel',
    );
  });
}
