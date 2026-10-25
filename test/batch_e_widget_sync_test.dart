import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/home_widget_sync.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The widget push is nine preference writes plus a redraw, and it runs after
/// every mutation and theme change. Identical payloads must not touch the
/// platform again; what travels is capped, because the lock screen is public.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel('home_widget'), (call) async {
          calls.add(call);
          return true;
        });
  });

  List<MethodCall> saves() =>
      calls.where((c) => c.method == 'saveWidgetData').toList();
  List<MethodCall> updates() =>
      calls.where((c) => c.method == 'updateWidget').toList();
  Object? saved(String key) => saves()
      .where((c) => (c.arguments as Map)['id'] == key)
      .map((c) => (c.arguments as Map)['data'])
      .lastOrNull as Object?;

  final due = DateTime(2026, 10, 25, 9);

  test('an unchanged sync performs no platform writes', () async {
    final source = SeededState([
      VikunjaTask(id: 1, projectId: 1, title: 'Fix bike', dueDate: due),
    ], due);

    await syncHomeWidget(source);
    expect(saves(), isNotEmpty, reason: 'the first push seeds the widget');
    expect(updates(), hasLength(1));
    calls.clear();

    await syncHomeWidget(source);
    await syncHomeWidget(source);

    expect(saves(), isEmpty, reason: 'identical rows and scheme: no writes');
    expect(updates(), isEmpty, reason: 'and no redraw either');
  });

  test('a changed row still pushes', () async {
    final source = SeededState([
      VikunjaTask(id: 1, projectId: 1, title: 'Fix bike', dueDate: due),
    ], due);
    await syncHomeWidget(source);
    calls.clear();

    source.seed([
      VikunjaTask(id: 1, projectId: 1, title: 'Fix the bike', dueDate: due),
    ]);
    await syncHomeWidget(source);

    expect(saves(), isNotEmpty);
    expect(updates(), hasLength(1));
    expect(saved('rows'), contains('Fix the bike'));
  });

  test('a theme change pushes the new colours', () async {
    final source = SeededState([
      VikunjaTask(id: 1, projectId: 1, title: 'Fix bike', dueDate: due),
    ], due);
    await syncHomeWidget(source);
    calls.clear();

    source.lightThemeId = TodoColors.patinaLight.id;
    await syncHomeWidget(source);

    expect(saved('scheme'), TodoColors.patinaLight.id);
    expect(saved('text'), TodoColors.patinaLight.primaryText.toARGB32());
    expect(updates(), hasLength(1));
  });

  group('F-044 cap', () {
    test('long titles are capped, the payload keeps its keys', () {
      final rows = homeWidgetRows([
        VikunjaTask(id: 42, projectId: 1, title: 'A' * 120, dueDate: due),
      ], now: due);

      expect(rows.single.title, startsWith('A' * 40));
      expect(rows.single.title.length, lessThanOrEqualTo(41));

      final decoded = jsonDecode(encodeHomeWidgetRows(rows)) as List;
      expect(decoded.single.keys.toSet(), {
        'id',
        'title',
        'meta',
        'tags',
        'overdue',
      });
      expect(decoded.single['id'], 42);
    });

    test('notes and descriptions never reach the widget', () async {
      final source = SeededState([
        VikunjaTask(
          id: 7,
          projectId: 1,
          title: 'Fix bike',
          description: 'Private note: the lock screen must not show this',
          dueDate: due,
        ),
      ], due);
      await syncHomeWidget(source);

      expect(saved('rows'), contains('"id":7'));
      final pushed = [for (final call in saves()) '${call.arguments}'];
      expect(
        pushed.where((a) => a.contains('Private note')),
        isEmpty,
        reason: 'the row carries id/title/meta/tags/overdue only',
      );
    });
  });
}

/// An [AppState] whose task list a test can seed, so the sync sees real rows
/// without going through the network.
class SeededState extends AppState {
  SeededState(List<VikunjaTask> tasks, DateTime now) {
    seed(tasks);
    clock = () => now;
    user = const VikunjaUser(id: 1, username: 'me');
  }

  final List<VikunjaTask> _tasks = [];

  void seed(List<VikunjaTask> tasks) => _tasks
    ..clear()
    ..addAll(tasks);

  @override
  List<VikunjaTask> get allTasksForWidget => _tasks;
}
