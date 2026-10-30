import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'home_widget_sync.dart';
import 'models.dart';
import 'state.dart';
import 'todo_theme.dart';

/// Android status-bar notifications for Vikunja's own notification feed, plus
/// the reminders Vikunja stores on tasks.
///
/// The feed has no push channel, so it is polled: the app asks `/notifications`
/// while it is running and posts whatever is new. Nothing from the feed is
/// delivered while the app is closed.
/// shortcut: no background feed delivery, add a WorkManager poll or Vikunja
/// webhooks when mentions and comments must arrive with the app closed.
///
/// Reminders do fire with the app closed: they are known times, so they are
/// handed to the platform alarm queue instead of being polled for.
class NotificationsService {
  NotificationsService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
      _ready = false;

  /// A service that skips the platform handshake: a test host has no
  /// notification channel to initialise, but the poll and the seen-id
  /// bookkeeping can still be driven.
  @visibleForTesting
  NotificationsService.ready({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
      _ready = true;

  static const _channelId = 'vikunja_notifications';
  static const _channelName = 'Vikunja notifications';
  static const _seenKey = 'seen_notification_ids';

  /// Reminder alarms sit above the feed's ids: Vikunja notification ids are
  /// small and the two sets must never cancel each other.
  static const reminderIdBase = 1000000;

  /// The mono sloth is white; on a light scheme the status bar is light too, so
  /// the glyph is inverted to stay visible.
  static String notificationIconFor(TodoColors scheme) =>
      scheme.primaryBackground.computeLuminance() > 0.5
      ? '@drawable/ic_notification_dark'
      : '@drawable/ic_notification';

  final FlutterLocalNotificationsPlugin _plugin;
  final ValueNotifier<String?> tappedPayload = ValueNotifier(null);
  bool _ready;

  /// Releases the payload notifier: it lives as long as the app state that
  /// owns the service, and a listener added after teardown is a bug.
  void dispose() {
    tappedPayload.dispose();
  }

  Future<void> init() async {
    if (_ready || kIsWeb || !Platform.isAndroid) return;
    // `tz.local` stays UTC on purpose: every schedule is converted from an
    // instant, so the device's zone name is not needed — only the database.
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        tappedPayload.value = response.payload;
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      tappedPayload.value = launch!.notificationResponse?.payload;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Assignments, comments and mentions from your server',
      ),
    );
    // Android 13+ asks the user; older versions grant it on install.
    await android?.requestNotificationsPermission();
    _ready = true;
  }

  /// Posts a status-bar notification for each item in [current] that is new and
  /// unread, and remembers what it has seen. [scheme] decides the icon: the
  /// glyph is white, so a light theme gets the inverted one.
  Future<void> publish(
    List<VikunjaNotification> current,
    TodoColors scheme,
  ) async {
    if (!_ready || current.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(_seenKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    final fresh = freshNotifications(current, seen);
    for (final item in fresh) {
      await _plugin.show(
        id: item.id,
        title: item.title,
        body: item.subtitle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            icon: notificationIconFor(scheme),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        payload: item.payload,
      );
    }
    // Remember only what the feed still serves. The old union kept every id
    // ever seen, so the list grew for the life of the account; an id that
    // dropped out of the feed would only come back as a notification if the
    // server resurrected it, which is exactly when re-posting is right.
    final known = {for (final item in current) item.id};
    if (!setEquals(known, seen)) {
      await prefs.setStringList(_seenKey, [
        for (final id in known) id.toString(),
      ]);
    }
  }

  /// Arms a notification for every reminder on an open task, replacing the
  /// previous set: an edited, completed or deleted task must not leave a stale
  /// alarm armed. [now] is the caller's clock, so a test can pin it.
  Future<void> rescheduleReminders(
    List<VikunjaTask> tasks,
    TodoColors scheme,
    DateTime now,
  ) async {
    if (!_ready) return;
    // Arming alarms is best effort: a host without the platform plugin (a test
    // host, a locked-down device) must not turn a refresh into a failure.
    try {
      await _cancelReminders();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Only Android 12+ gates exact alarms; below that no permission exists and
      // an inexact alarm is just a deferred one, so null means "allowed".
      // Only Android 12+ gates exact alarms; below that no permission exists and
      // an inexact alarm is just a deferred one, so null means "allowed".
      final exact = await android?.canScheduleExactNotifications() ?? true;
      for (final reminder in reminderSchedules(tasks, now)) {
        await _plugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          payload: reminder.payload,
          scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              icon: notificationIconFor(scheme),
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          // shortcut: exact alarms need SCHEDULE_EXACT_ALARM granted by the
          // user; without it the reminder still fires, a few minutes late.
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Arming is best effort; the refresh that triggered it must still finish.
    }
  }

  Future<void> _cancelReminders() async {
    for (final request in await _plugin.pendingNotificationRequests()) {
      if (request.id >= reminderIdBase) await _plugin.cancel(id: request.id);
    }
  }

  /// Polls the server and posts anything new, then re-arms the task reminders;
  /// called on launch, on refresh and by the foreground timer.
  Future<void> poll(AppState state) async {
    if (!_ready || state.offline) return;
    final scheme = activeScheme(state);
    // The feed and the reminder alarms are independent: a server that answers
    // the feed with an error must not leave a reminder unarmed.
    if (await state.loadNotifications() == null) {
      await publish(state.notifications, scheme);
    }
    await rescheduleReminders(state.allTasksForWidget, scheme, state.clock());
  }
}

/// One armed reminder: the task title, at the server's reminder time.
class ReminderSchedule {
  const ReminderSchedule({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

/// The reminders still in the future on tasks that are not done. Vikunja keeps
/// a list per task; three are all the platform ids one task can own without
/// colliding with its neighbour.
List<ReminderSchedule> reminderSchedules(
  Iterable<VikunjaTask> tasks,
  DateTime now,
) => [
  for (final task in tasks)
    if (!task.done)
      for (final (i, reminder) in task.reminders.indexed)
        if (i < 3 && reminder.reminder.isAfter(now))
          ReminderSchedule(
            id: NotificationsService.reminderIdBase + task.id * 3 + i,
            at: reminder.reminder,
            title: task.title,
            body: 'Reminder',
            payload: 'task:${task.id}',
          ),
];

/// The unread notifications whose ids [seen] does not contain.
List<VikunjaNotification> freshNotifications(
  List<VikunjaNotification> current,
  Set<int> seen,
) => [
  for (final notification in current)
    if (!notification.isRead && !seen.contains(notification.id)) notification,
];

extension NotificationPayload on VikunjaNotification {
  /// Notification payload: the task to open, or empty for team events.
  String get payload => taskId == null ? '' : 'task:$taskId';
}
