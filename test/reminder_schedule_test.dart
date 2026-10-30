import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/notifications_service.dart';

/// Reminders are known times, so they are armed as alarms instead of polled for.
/// What gets armed, and when, is decided by `reminderSchedules`; the platform
/// call only forwards it.
VikunjaTask task({
  required int id,
  String title = 'A task',
  bool done = false,
  List<DateTime> reminders = const [],
}) => VikunjaTask(
  id: id,
  projectId: 1,
  title: title,
  done: done,
  reminders: [for (final at in reminders) VikunjaReminder(reminder: at)],
);

void main() {
  final now = DateTime(2026, 10, 28, 9);
  final soon = DateTime(2026, 10, 28, 10);
  final later = DateTime(2026, 10, 29, 10);

  test('only future reminders on open tasks are armed', () {
    final schedules = reminderSchedules([
      task(id: 1, reminders: [soon, now.subtract(const Duration(minutes: 1))]),
      task(id: 2, done: true, reminders: [later]),
      task(id: 3),
    ], now);

    expect(schedules.map((s) => s.at), [soon]);
    expect(schedules.single.title, 'A task');
    expect(schedules.single.payload, 'task:1');
  });

  test('ids stay distinct and above the feed range', () {
    final schedules = reminderSchedules([
      task(id: 1, reminders: [soon, later]),
      task(id: 2, reminders: [soon]),
    ], now);

    final ids = schedules.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.every((id) => id >= NotificationsService.reminderIdBase), isTrue);
  });
}
