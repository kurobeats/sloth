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
    required this.overdue,
  });

  final int id;
  final String title;

  /// "Today", "Yesterday", "Tomorrow" — Vikunja's own wording.
  final String meta;
  final bool overdue;
}

/// The open tasks due today or earlier, newest deadline last, capped at five.
List<HomeWidgetRow> homeWidgetRows(List<VikunjaTask> tasks, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final tomorrow = DateTime(
    today.year,
    today.month,
    today.day,
  ).add(const Duration(days: 1));
  final due = tasks.where((t) {
    final due = t.dueDate;
    return !t.done && due != null && due.isBefore(tomorrow);
  }).toList()..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  return [
    for (final task in due.take(5))
      HomeWidgetRow(
        id: task.id,
        title: task.title,
        meta: TodoFormat.dueLabel(task.dueDate!, now: today),
        overdue: task.dueDate!.isBefore(
          DateTime(today.year, today.month, today.day),
        ),
      ),
  ];
}

String encodeHomeWidgetRows(List<HomeWidgetRow> rows) => jsonEncode([
  for (final row in rows)
    {
      'id': row.id,
      'title': row.title,
      'meta': row.meta,
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

/// Pushes the current list and the active scheme's colours to the widget.
/// Safe to call from anywhere: failures are swallowed, the widget is optional.
Future<void> syncHomeWidget(AppState state) async {
  try {
    final scheme = activeScheme(state);
    final rows = homeWidgetRows(state.allTasksForWidget);
    // Android picks its rounded card and header drawables from the scheme id.
    await HomeWidget.saveWidgetData<String>('scheme', scheme.id);
    await HomeWidget.saveWidgetData<String>('rows', encodeHomeWidgetRows(rows));
    await HomeWidget.saveWidgetData<int>('count', rows.length);
    await HomeWidget.saveWidgetData<int>(
      'overdue',
      rows.where((r) => r.overdue).length,
    );
    for (final entry in homeWidgetColours(scheme).entries) {
      await HomeWidget.saveWidgetData<int>(entry.key, entry.value);
    }
    await HomeWidget.updateWidget(androidName: homeWidgetProvider);
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
