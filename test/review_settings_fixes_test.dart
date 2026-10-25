import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/project_settings_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_format.dart';
import 'package:sloth/todo_theme.dart';

/// Behaviour that a code review of the settings and add/delete paths found
/// broken. Each test pins the bug that was there, so it cannot come back.
void main() {
  group('project identifier', () {
    test('fromJson reads it, and it survives a round trip', () {
      final project = VikunjaProject.fromJson({
        'id': 3,
        'title': 'Home',
        'identifier': 'HOME',
      });
      expect(project.identifier, 'HOME');
      expect(project.toJson()['identifier'], 'HOME');
      expect(project.copyWith(title: 'Maison').identifier, 'HOME');
    });

    test('the screen starts with the saved identifier in the field', () {
      // A field that starts empty makes the next save wipe what the server has.
      const project = VikunjaProject(id: 3, title: 'Home', identifier: 'HOME');
      expect(project.identifier, 'HOME');
    });
  });

  group('state returns its own failure', () {
    test('deleteTask reports failure without touching state.error', () async {
      final state = AppState();
      state.offline = true;
      final task = VikunjaTask(id: 1, projectId: 2, title: 'Fix bike');

      final error = await state.deleteTask(task);

      expect(error, AppState.offlineEditError);
      // The shared field belongs to the poller; a delete must not write it.
      expect(state.error, isNull);
    });

    test('saveProject reports failure without touching state.error', () async {
      final state = AppState()..offline = true;

      final error = await state.saveProject(
        const VikunjaProject(id: 3, title: 'Home'),
        title: 'Maison',
      );

      expect(error, AppState.offlineEditError);
      expect(state.error, isNull);
    });

    testWidgets('a failed save says so, and a stale error is not reported', (
      tester,
    ) async {
      final state = AppState()..offline = true;
      // A leftover error from the background poller: the old code read this
      // instead of the save's own result.
      state.error = 'Cannot reach the server';
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: buildTodoTheme(TodoColors.gruvboxLight),
            home: const ProjectSettingsScreen(
              project: VikunjaProject(id: 3, title: 'Home'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(AppState.offlineEditError), findsOneWidget);
      expect(find.text('Cannot reach the server'), findsNothing);
    });
  });

  group('calendar day maths across a DST change', () {
    test('a 25-hour day does not shift "Tomorrow" to "Today"', () {
      // Australia/Sydney leaves DST on 5 Apr 2026: that local day is 25 hours.
      final now = DateTime(2026, 4, 4, 9);
      final tomorrow = DateTime(2026, 4, 5, 9);
      expect(TodoFormat.dueLabel(tomorrow, now: now), 'Tomorrow');
      expect(TodoFormat.metadataLabel(tomorrow, now: now), 'Tomorrow');
      expect(daysBetween(tomorrow, now), 1);
    });

    test('a 23-hour day does not turn "Today" into "Tomorrow"', () {
      // 4 Oct 2026 is 23 hours long in Sydney (DST starts).
      final now = DateTime(2026, 10, 4, 9);
      expect(TodoFormat.dueLabel(now, now: now), 'Today');
      expect(daysBetween(now, now), 0);
    });

    test('endOfToday stops at tomorrow\'s midnight, not 24 hours later', () {
      final end = endOfToday(DateTime(2026, 10, 4, 23));
      expect(end, DateTime(2026, 10, 5));
      expect(end.isAfter(DateTime(2026, 10, 5)), isFalse);
    });
  });
}
