import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_widget_sync.dart';
import 'models.dart';
import 'state.dart';
import 'todo_theme.dart';

/// Android status-bar notifications for Vikunja's own notification feed.
///
/// Vikunja has no push channel, so this is polling: the app asks for
/// `/notifications` while it is running and posts whatever is new. Nothing is
/// delivered while the app is closed.
/// shortcut: no background delivery, add a WorkManager poll or Vikunja webhooks
/// when notifications must arrive with the app closed.
class NotificationsService {
  NotificationsService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'vikunja_notifications';
  static const _channelName = 'Vikunja notifications';
  static const _seenKey = 'seen_notification_ids';

  /// The mono sloth is white; on a light scheme the status bar is light too, so
  /// the glyph is inverted to stay visible.
  static String notificationIconFor(TodoColors scheme) =>
      scheme.primaryBackground.computeLuminance() > 0.5
      ? '@drawable/ic_notification_dark'
      : '@drawable/ic_notification';

  final FlutterLocalNotificationsPlugin _plugin;
  final ValueNotifier<String?> tappedPayload = ValueNotifier(null);
  bool _ready = false;

  Future<void> init() async {
    if (_ready || kIsWeb || !Platform.isAndroid) return;
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
    if (fresh.isEmpty) return;
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
    await prefs.setStringList(
      _seenKey,
      {
        ...seen,
        ...current.map((n) => n.id),
      }.map((id) => id.toString()).toList(),
    );
  }

  /// Polls the server and posts anything new; called on launch, on refresh and
  /// by the foreground timer.
  Future<void> poll(AppState state) async {
    if (!_ready || state.offline) return;
    if (await state.loadNotifications() != null) return;
    await publish(state.notifications, activeScheme(state));
  }
}

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
