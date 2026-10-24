import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';
import '../widgets/notification_tile.dart';
import '../widgets/offline_banner.dart';
import 'task_detail_screen.dart';

/// Everything Vikunja reported for this account: assignments, comments,
/// mentions, overdue tasks and team changes.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final error = await AppScope.of(context).loadNotifications();
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _open(VikunjaNotification notification) async {
    final state = AppScope.of(context);
    final taskId = notification.taskId;
    if (taskId == null) return;
    // Opening counts as reading it.
    if (!notification.isRead) await state.markNotificationRead(notification.id);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: taskId)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final items = state.notifications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.offline) OfflineBanner(onRetry: state.refresh),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: items.isEmpty
                        ? ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 80,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.notifications_none,
                                      size: 48,
                                      color: c.secondaryText,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Nothing new',
                                      style: TextStyle(
                                        fontSize: TodoText.xl,
                                        color: c.primaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Assignments and comments on your tasks '
                                      'show up here.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: c.secondaryText),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: c.divider),
                            itemBuilder: (context, i) => NotificationTile(
                              notification: items[i],
                              onOpen: () => _open(items[i]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
