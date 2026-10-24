import 'package:flutter/material.dart';

import '../models.dart';
import '../todo_format.dart';
import '../todo_theme.dart';

/// One notification row: unread dot, headline, detail and time.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onOpen,
  });

  final VikunjaNotification notification;

  /// Opens the task behind the notification, or does nothing when the
  /// notification is not about a task.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final subtitle = notification.subtitle;
    final created = notification.created;
    final canOpen = notification.taskId != null;

    return InkWell(
      onTap: canOpen ? onOpen : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Icon(
                Icons.circle,
                size: 8,
                color: notification.isRead ? Colors.transparent : c.accent,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: TodoText.medium,
                      color: c.primaryText,
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TodoText.small,
                        color: c.secondaryText,
                      ),
                    ),
                  ],
                  if (created != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      TodoFormat.metadataLabel(created),
                      style: TextStyle(fontSize: 11, color: c.secondaryText),
                    ),
                  ],
                ],
              ),
            ),
            if (canOpen)
              Icon(Icons.chevron_right, size: 18, color: c.secondaryText),
          ],
        ),
      ),
    );
  }
}
