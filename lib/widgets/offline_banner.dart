import 'package:flutter/material.dart';

import '../state.dart';
import '../todo_theme.dart';

/// Shown whenever the visible data came from the offline snapshot.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    if (!state.offline) return const SizedBox.shrink();
    final since = state.cachedAt;
    return Material(
      color: c.overdue.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: c.overdue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Offline${since == null ? "" : " · data from ${_stamp(since)}"}. '
                '${AppState.offlineEditError}',
                style: TextStyle(fontSize: 12, color: c.primaryText),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text('Retry', style: TextStyle(color: c.accent)),
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Shows the offline explanation instead of letting an edit silently fail.
bool requireOnline(BuildContext context, AppState state) {
  if (state.canEdit) return true;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(AppState.offlineEditError)));
  return false;
}
