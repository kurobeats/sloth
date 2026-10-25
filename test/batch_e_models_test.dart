import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';

/// Avatar initials and due-date predicates: both ran their work per call, so
/// the pattern is compiled once and "now" is injectable.
void main() {
  group('F-063 initials', () {
    test('the same results for a fixture set', () {
      const users = [
        VikunjaUser(id: 1, username: 'kurobeats'),
        VikunjaUser(id: 2, username: 'me', name: 'Ada Lovelace'),
        VikunjaUser(id: 3, username: 'x', name: ' Ada  Grace  Lovelace '),
        VikunjaUser(id: 4, username: 'blank', name: ''),
      ];
      // An empty name is not null, so VikunjaUser shows '?' (unchanged).
      expect(users.map((u) => u.initials), ['K', 'AL', 'AL', '?']);

      const members = [
        VikunjaTeamMember(id: 1, username: 'bob'),
        VikunjaTeamMember(id: 2, username: 'b', name: 'bob smith'),
        VikunjaTeamMember(id: 3, username: 'blank', name: ''),
      ];
      expect(members.map((m) => m.initials), ['B', 'BS', 'B']);
    });

    test('the split pattern is compiled once, not per avatar', () {
      expect(
        identical(
          VikunjaUser.initialsSeparator,
          VikunjaUser.initialsSeparator,
        ),
        isTrue,
      );
      const user = VikunjaUser(id: 1, username: 'me', name: 'Ada Lovelace');
      user.initials;
      expect(identical(VikunjaUser.initialsSeparator.pattern, r'\s+'), isTrue);
    });
  });

  group('F-064 due predicates take a clock', () {
    VikunjaTask due(DateTime at) =>
        VikunjaTask(id: 1, projectId: 1, title: 'Task', dueDate: at);

    test('isDueToday only looks at the calendar day', () {
      final task = due(DateTime(2026, 10, 25, 23, 59));
      expect(task.isDueTodayAt(DateTime(2026, 10, 25, 0, 0)), isTrue);
      expect(task.isDueTodayAt(DateTime(2026, 10, 25, 23, 59)), isTrue);
      expect(task.isDueTodayAt(DateTime(2026, 10, 26, 0, 0)), isFalse);
      expect(task.isDueTodayAt(DateTime(2026, 10, 24, 23, 59)), isFalse);
    });

    test('isOverdue is strict about the deadline', () {
      final task = due(DateTime(2026, 10, 25, 12));
      expect(task.isOverdueAt(DateTime(2026, 10, 25, 11, 59)), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 10, 25, 12)), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 10, 25, 12, 1)), isTrue);
    });

    test('a done task is never overdue', () {
      final task = VikunjaTask(
        id: 1,
        projectId: 1,
        title: 'Task',
        dueDate: DateTime(2026, 10, 25),
        done: true,
      );
      expect(task.isOverdueAt(DateTime(2026, 10, 26)), isFalse);
    });

    test('no due date is never due or overdue', () {
      final task = VikunjaTask(id: 1, projectId: 1, title: 'Task');
      expect(task.isDueTodayAt(DateTime(2026, 10, 25)), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 10, 25)), isFalse);
    });

    test('the DST switch does not move a task onto another day', () {
      // 29 March 2026: the EU clocks jump at 02:00 local time.
      final task = due(DateTime(2026, 3, 29, 0, 30));
      expect(task.isDueTodayAt(DateTime(2026, 3, 29, 23, 30)), isTrue);
      expect(task.isDueTodayAt(DateTime(2026, 3, 30, 0, 1)), isFalse);
    });
  });
}
