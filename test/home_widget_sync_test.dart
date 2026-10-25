import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/home_widget_sync.dart';
import 'package:sloth/models.dart';
import 'package:sloth/todo_theme.dart';

/// The widget payload is plain data so it can be checked without Android.
void main() {
  VikunjaTask task(
    int id,
    String title, {
    DateTime? due,
    bool done = false,
    List<VikunjaLabel> labels = const [],
  }) => VikunjaTask(
    id: id,
    projectId: 1,
    title: title,
    done: done,
    dueDate: due,
    labels: labels,
  );

  final now = DateTime(2026, 10, 25, 9);

  test('only open tasks due today or earlier are listed', () {
    final rows = homeWidgetRows([
      task(1, 'Overdue chain', due: DateTime(2026, 10, 24)),
      task(2, 'Filter', due: DateTime(2026, 10, 25, 18)),
      task(3, 'Tomorrow', due: DateTime(2026, 10, 26)),
      task(4, 'Already done', due: DateTime(2026, 10, 25), done: true),
      task(5, 'No due date'),
    ], now: now);

    expect(rows.map((r) => r.title), ['Overdue chain', 'Filter']);
    expect(rows.first.meta, 'Yesterday');
    expect(rows.last.meta, 'Today');
  });

  test('the payload is JSON with the fields the provider reads', () {
    final payload = encodeHomeWidgetRows(
      homeWidgetRows([
        task(7, 'Fix bike', due: DateTime(2026, 10, 25)),
      ], now: now),
    );
    final decoded = jsonDecode(payload) as List;
    expect(decoded.single, {
      'id': 7,
      'title': 'Fix bike',
      'meta': 'Today',
      'tags': '',
      'overdue': false,
    });
  });

  test('a task\'s labels travel with the row', () {
    final rows = homeWidgetRows([
      task(
        8,
        'Fix bike',
        due: DateTime(2026, 10, 25),
        labels: [
          VikunjaLabel(id: 1, title: 'Chores', hexColor: 'ff0000'),
          VikunjaLabel(id: 2, title: 'House', hexColor: '00ff00'),
        ],
      ),
      task(9, 'No labels', due: DateTime(2026, 10, 25)),
    ], now: now);
    expect(rows.first.tags, 'Chores, House');
    expect(rows.last.tags, '');
    final decoded = jsonDecode(encodeHomeWidgetRows(rows)) as List;
    expect(decoded.first['tags'], 'Chores, House');
    expect(decoded.last['tags'], '');
  });

  test('at most five rows, so the widget keeps its size', () {
    final rows = homeWidgetRows([
      for (var i = 0; i < 9; i++)
        task(i, 'Task $i', due: DateTime(2026, 10, 25)),
    ], now: now);
    expect(rows, hasLength(5));
  });

  test('the widget colours come from the active scheme', () {
    for (final scheme in [
      TodoColors.catppuccinMocha,
      TodoColors.gruvboxLight,
      TodoColors.patinaLight,
    ]) {
      final colours = homeWidgetColours(scheme);
      expect(
        colours['bg'],
        scheme.primaryBackground.toARGB32(),
        reason: scheme.id,
      );
      expect(colours['headerText'], scheme.onAccent.toARGB32());
      expect(colours['text'], scheme.primaryText.toARGB32());
      expect(colours['muted'], scheme.secondaryText.toARGB32());
      expect(colours['accent'], scheme.accent.toARGB32());
      expect(colours['header'], isNot(colours['bg']), reason: 'bar is visible');
    }
  });

  test('overdue rows are flagged so the widget can colour them', () {
    final rows = homeWidgetRows([
      task(1, 'Late', due: DateTime(2026, 10, 20)),
      task(2, 'Today', due: DateTime(2026, 10, 25)),
    ], now: now);
    expect(rows.first.overdue, isTrue);
    expect(rows.last.overdue, isFalse);
  });
}
