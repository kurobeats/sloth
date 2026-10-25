import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/notifications_service.dart';
import 'package:sloth/todo_theme.dart';

VikunjaNotification note(
  int id, {
  bool read = false,
  int? taskId = 4,
  String name = 'task.assigned',
}) => VikunjaNotification(
  id: id,
  name: name,
  readAt: read ? DateTime(2026, 10, 25) : null,
  doer: 'Priya',
  taskId: taskId,
  taskTitle: 'Fix bike',
);

/// Only unseen, unread items should reach the status bar; a refresh must not
/// re-post the same notification.
void main() {
  test('first run posts every unread notification once', () {
    expect(freshNotifications([note(1), note(2)], const {}).map((n) => n.id), [
      1,
      2,
    ]);
  });

  test('already posted ids are not posted again', () {
    expect(freshNotifications([note(1), note(2)], {1, 2}), isEmpty);
    expect(
      freshNotifications([note(1), note(2), note(3)], {1, 2}).single.id,
      3,
    );
  });

  test('read notifications never reach the status bar', () {
    expect(freshNotifications([note(1, read: true)], const {}), isEmpty);
  });

  test('a light theme inverts the white glyph', () {
    expect(
      NotificationsService.notificationIconFor(TodoColors.gruvboxLight),
      '@drawable/ic_notification_dark',
    );
    expect(
      NotificationsService.notificationIconFor(TodoColors.patinaLight),
      '@drawable/ic_notification_dark',
    );
    expect(
      NotificationsService.notificationIconFor(TodoColors.catppuccinMocha),
      '@drawable/ic_notification',
    );
    expect(
      NotificationsService.notificationIconFor(TodoColors.oceanicNext),
      '@drawable/ic_notification',
    );
  });

  test('a notification without a task still works, payload is empty', () {
    final team = note(9, taskId: null, name: 'team.member.added');
    expect(freshNotifications([team], const {}).single.payload, '');
    expect(freshNotifications([note(1)], const {}).single.payload, 'task:4');
  });
}
