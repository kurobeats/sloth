import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sloth/models.dart';
import 'package:sloth/notifications_service.dart';
import 'package:sloth/todo_theme.dart';

/// `seen_notification_ids` used to be the union of every id ever published, so
/// it grew for the life of the account. It only has to cover the feed the
/// server is currently serving.
VikunjaNotification note(int id) => VikunjaNotification(
  id: id,
  name: 'task.assigned',
  // Read, so the poll stores ids without posting anything to the status bar:
  // publishing a notification needs the Android plugin, pruning does not.
  readAt: DateTime(2026, 10, 25),
  doer: 'Priya',
  taskId: 4,
  taskTitle: 'Fix bike',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the stored seen set does not grow past the current feed', () async {
    SharedPreferences.setMockInitialValues({});
    final service = NotificationsService.ready();

    await service.publish([note(1), note(2)], TodoColors.gruvboxLight);
    await service.publish([note(2), note(3)], TodoColors.gruvboxLight);

    final stored =
        (await SharedPreferences.getInstance()).getStringList(
          'seen_notification_ids',
        ) ??
        const [];
    expect(stored.toSet(), {
      '2',
      '3',
    }, reason: 'id 1 left the feed, so it must not be remembered forever');
    expect(stored.length, lessThanOrEqualTo(2));
  });
}
