import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/todo_format.dart';

void main() {
  final now = DateTime(2026, 10, 24, 9, 30);

  test('due labels resolve relative days', () {
    expect(TodoFormat.dueLabel(DateTime(2026, 10, 24, 17), now: now), 'Today');
    expect(TodoFormat.dueLabel(DateTime(2026, 10, 25), now: now), 'Tomorrow');
    expect(TodoFormat.dueLabel(DateTime(2026, 10, 23), now: now), 'Yesterday');
    expect(TodoFormat.dueLabel(DateTime(2026, 10, 28), now: now), 'Wednesday');
    expect(TodoFormat.dueLabel(DateTime(2026, 12, 1), now: now), 'Tue 1 Dec');
    expect(
      TodoFormat.dueLabel(DateTime(2027, 1, 5), now: now),
      'Tue 5 Jan 2027',
    );
  });

  test('repeat durations use Vikunja wording', () {
    expect(TodoFormat.repeat(0), '');
    expect(TodoFormat.repeat(86400), 'Every Day');
    expect(TodoFormat.repeat(604800), 'Every Week');
    expect(TodoFormat.repeat(30 * 86400), 'Every 30 Days');
    expect(TodoFormat.repeat(3 * 86400), 'Every 3 Days');
    expect(TodoFormat.repeat(2 * 604800), 'Every 2 Weeks');
    expect(TodoFormat.repeat(3600), 'Every 1 Hours');
  });

  test('priority labels match Vikunja', () {
    expect(TodoFormat.priority(0), 'Unset');
    expect(TodoFormat.priority(1), 'Low');
    expect(TodoFormat.priority(2), 'Medium');
    expect(TodoFormat.priority(3), 'High');
    expect(TodoFormat.priority(4), 'Urgent');
    expect(TodoFormat.priority(5), 'DO NOW');
  });

  test('groupByDay orders days and puts undated tasks last', () {
    final tasks = <({DateTime? due, String name})>[
      (due: DateTime(2026, 10, 25), name: 'b'),
      (due: null, name: 'x'),
      (due: DateTime(2026, 10, 24, 15), name: 'a'),
      (due: DateTime(2026, 10, 24, 8), name: 'a2'),
    ];
    final groups = TodoFormat.groupByDay(tasks, (t) => t.due);
    expect(groups.length, 3);
    expect(groups[0].day, DateTime(2026, 10, 24));
    expect(groups[0].tasks.map((t) => t.name), ['a', 'a2']);
    expect(groups[1].day, DateTime(2026, 10, 25));
    expect(groups[2].day, isNull);
    expect(groups[2].tasks.single.name, 'x');
  });
}
