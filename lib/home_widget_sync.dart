import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'models.dart';
import 'state.dart';
import 'todo_format.dart';
import 'todo_theme.dart';

/// Name of the Android provider, see `SlothWidgetProvider.kt`.
const homeWidgetProvider = 'SlothWidgetProvider';

/// One row of the home screen widget.
@immutable
class HomeWidgetRow {
  const HomeWidgetRow({
    required this.id,
    required this.title,
    required this.meta,
    required this.tags,
    required this.overdue,
  });

  final int id;
  final String title;

  /// "Today", "Yesterday", "Tomorrow" — Vikunja's own wording.
  final String meta;

  /// The task's labels, comma separated (Vikunja calls them labels).
  final String tags;
  final bool overdue;
}

/// Longest title a row carries. The widget text sits on the lock screen, which
/// anyone holding the phone can read without unlocking: a task title is shown
/// but capped, notes and descriptions are never pushed at all (the provider
/// only reads id/title/meta/tags/overdue, so nothing else is sent).
const widgetTitleMaxLength = 40;

String _capped(String text) => text.length <= widgetTitleMaxLength
    ? text
    : '${text.substring(0, widgetTitleMaxLength)}…';

/// The open tasks due today or earlier, newest deadline last, capped at five.
List<HomeWidgetRow> homeWidgetRows(List<VikunjaTask> tasks, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final due = dueBefore(tasks, endOfToday(today));
  return [
    for (final task in due.take(5))
      HomeWidgetRow(
        id: task.id,
        title: _capped(task.title),
        meta: TodoFormat.dueLabel(task.dueDate!, now: today),
        tags: _capped(task.labels.map((l) => l.title).join(', ')),
        overdue: task.dueDate!.isBefore(startOfDay(today)),
      ),
  ];
}

String encodeHomeWidgetRows(List<HomeWidgetRow> rows) => jsonEncode([
  for (final row in rows)
    {
      'id': row.id,
      'title': row.title,
      'meta': row.meta,
      'tags': row.tags,
      'overdue': row.overdue,
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
    final overdue = rows.where((r) => r.overdue).length;
    // One round trip per preference is a platform call each; they are
    // independent, so they go out together.
    await Future.wait([
      // Android picks its rounded card and header drawables from the scheme id.
      HomeWidget.saveWidgetData<String>('scheme', scheme.id),
      HomeWidget.saveWidgetData<String>('rows', encoded),
      HomeWidget.saveWidgetData<int>('count', rows.length),
      HomeWidget.saveWidgetData<int>('overdue', overdue),
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
