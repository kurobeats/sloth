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

  test('every open task due in the next week travels, soonest first', () {
    final rows = homeWidgetRows([
      task(1, 'Overdue chain', due: DateTime(2026, 10, 24)),
      task(2, 'Filter', due: DateTime(2026, 10, 25, 18)),
      task(3, 'Tomorrow', due: DateTime(2026, 10, 26)),
      task(4, 'Next week', due: DateTime(2026, 11, 1, 9)),
      task(5, 'Too far out', due: DateTime(2026, 11, 2)),
      task(6, 'Already done', due: DateTime(2026, 10, 25), done: true),
      task(7, 'No due date'),
    ], now: now);

    expect(rows.map((r) => r.title), [
      'Overdue chain',
      'Filter',
      'Tomorrow',
      'Next week',
    ]);
    expect(
      rows.first.due,
      DateTime(2026, 10, 24),
      reason: 'the raw deadline travels, not a label that goes stale',
    );
  });

  test('the payload is JSON with the fields the provider reads', () {
    final due = DateTime(2026, 10, 25, 18);
    final payload = encodeHomeWidgetRows(
      homeWidgetRows([task(7, 'Fix bike', due: due)], now: now),
    );
    final decoded = jsonDecode(payload) as List;
    expect(decoded.single, {
      'id': 7,
      'title': 'Fix bike',
      'due': due.millisecondsSinceEpoch,
      'tags': '',
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

  test('the snapshot is capped, so a busy week does not bloat it', () {
    final rows = homeWidgetRows([
      for (var i = 0; i < 40; i++)
        task(i, 'Task $i', due: DateTime(2026, 10, 25, 1).add(Duration(hours: i))),
    ], now: now);
    expect(rows, hasLength(widgetRowLimit));
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
}
