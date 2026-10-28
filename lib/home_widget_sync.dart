import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'models.dart';
import 'state.dart';
import 'todo_theme.dart';

/// Name of the Android provider, see `SlothWidgetProvider.kt`.
const homeWidgetProvider = 'SlothWidgetProvider';

/// One row of the home screen widget.
@immutable
class HomeWidgetRow {
  const HomeWidgetRow({
    required this.id,
    required this.title,
    required this.due,
    required this.tags,
  });

  final int id;
  final String title;

  /// When the task is due. The provider works out "Today", "Yesterday" and
  /// whether the row is overdue when it paints: a snapshot labelled today is
  /// wrong tomorrow, and the app may not be opened for days.
  final DateTime due;

  /// The task's labels, comma separated (Vikunja calls them labels).
  final String tags;
}

/// Longest title a row carries. The widget text sits on the lock screen, which
/// anyone holding the phone can read without unlocking: a task title is shown
/// but capped, notes and descriptions are never pushed at all (the provider
/// only reads id/title/meta/tags/overdue, so nothing else is sent).
const widgetTitleMaxLength = 40;

String _capped(String text) => text.length <= widgetTitleMaxLength
    ? text
    : '${text.substring(0, widgetTitleMaxLength)}…';

/// How many days of deadlines the snapshot carries. The widget paints the tasks
/// due by the end of *its* today, and Android redraws it from this snapshot on
/// its own 30-minute tick, so the payload has to reach past today: this is how
/// long the widget stays right when the app is never opened.
const widgetHorizonDays = 7;

/// Rows pushed for that window. The widget paints five; the surplus keeps a
/// week-old snapshot correct as the earliest tasks get completed elsewhere.
const widgetRowLimit = 20;

/// The open tasks due inside [widgetHorizonDays], soonest first. Membership is
/// deliberately wider than the widget's own five rows: what is "due today"
/// depends on the day the widget paints, not on the day this ran.
List<HomeWidgetRow> homeWidgetRows(List<VikunjaTask> tasks, {DateTime? now}) {
  final today = now ?? DateTime.now();
  // Calendar arithmetic, not a Duration: a DST day is not 24 hours long.
  final horizon = DateTime(
    today.year,
    today.month,
    today.day + widgetHorizonDays + 1,
  );
  return [
    for (final task in dueBefore(tasks, horizon).take(widgetRowLimit))
      HomeWidgetRow(
        id: task.id,
        title: _capped(task.title),
        due: task.dueDate!,
        tags: _capped(task.labels.map((l) => l.title).join(', ')),
      ),
  ];
}

String encodeHomeWidgetRows(List<HomeWidgetRow> rows) => jsonEncode([
  for (final row in rows)
    {
      'id': row.id,
      'title': row.title,
      // Epoch millis: the provider compares and formats it in local time.
      'due': row.due.millisecondsSinceEpoch,
      'tags': row.tags,
    },
]);

/// Colours the native widget paints with: body, header bar, text, muted text,
/// accent. Everything derives from the scheme the app is showing.
Map<String, int> homeWidgetColours(TodoColors scheme) => {
  'bg': scheme.primaryBackground.toARGB32(),
  // Android picks a rounded accent header drawable from the scheme id; only the
  // text on it travels as a colour.
  'headerText': scheme.onAccent.toARGB32(),
  'text': scheme.primaryText.toARGB32(),
  'muted': scheme.secondaryText.toARGB32(),
  'accent': scheme.accent.toARGB32(),
};

/// The payload last pushed to the widget, so a refresh that changed nothing
/// visible does not rewrite nine preferences and redraw the lock screen.
String? _lastPushed;

/// Pushes the current list and the active scheme's colours to the widget.
/// Safe to call from anywhere: failures are swallowed, the widget is optional.
Future<void> syncHomeWidget(AppState state) async {
  try {
    final scheme = activeScheme(state);
    final rows = homeWidgetRows(state.allTasksForWidget);
    final encoded = encodeHomeWidgetRows(rows);
    final colours = homeWidgetColours(scheme);
    final signature = '$encoded|${scheme.id}|$colours';
    if (signature == _lastPushed) return;
    // One round trip per preference is a platform call each; they are
    // independent, so they go out together.
    await Future.wait([
      // Android picks its rounded card and header drawables from the scheme id.
      HomeWidget.saveWidgetData<String>('scheme', scheme.id),
      HomeWidget.saveWidgetData<String>('rows', encoded),
      for (final entry in colours.entries)
        HomeWidget.saveWidgetData<int>(entry.key, entry.value),
    ]);
    await HomeWidget.updateWidget(androidName: homeWidgetProvider);
    _lastPushed = signature;
  } catch (_) {
    // No widget host, no plugin (tests, desktop) — nothing to do.
  }
}

/// The scheme the app is painting with right now.
TodoColors activeScheme(AppState state) {
  final dark = switch (state.themeMode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
  };
  return dark ? state.darkTheme : state.lightTheme;
}
