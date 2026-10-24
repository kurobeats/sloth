import 'package:flutter/material.dart';

import '../models.dart';
import '../todo_format.dart';
import '../todo_theme.dart';

/// A task row: 52dp minimum height, 48dp check and star hit areas,
/// 16sp title with a 14sp metadata row underneath.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onTap,
    required this.onToggleDone,
    required this.onToggleStar,
    this.onLongPress,
    this.project,
    this.showProject = false,
    this.showStar = true,
  });

  final VikunjaTask task;
  final VikunjaProject? project;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleStar;
  final VoidCallback? onLongPress;
  final bool showProject;
  final bool showStar;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final metadata = _metadataItems(context, c);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TodoText.taskMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: TodoText.tilePadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CheckButton(done: task.done, onTap: onToggleDone),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.title.isEmpty ? 'Untitled task' : task.title,
                      style: TextStyle(
                        fontSize: TodoText.big,
                        color: task.done ? c.secondaryText : c.primaryText,
                        height: 1.25,
                        decoration: task.done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: c.secondaryText,
                      ),
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _metadataRow(metadata, c),
                    ],
                  ],
                ),
              ),
              if (showStar)
                _IconButton(
                  icon: task.isFavorite ? Icons.star : Icons.star_border,
                  color: task.isFavorite ? c.starActive : c.secondaryText,
                  tooltip: task.isFavorite
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  onTap: onToggleStar,
                )
              else
                const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _metadataItems(BuildContext context, TodoColors c) {
    final items = <Widget>[];

    if (task.labels.isNotEmpty) {
      items.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in task.labels.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(Icons.label, size: 13, color: TodoColors.serverColor(l.hexColor, c)),
            ),
          Text(
            task.labels.first.title,
            style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText),
          ),
        ],
      ));
    }

    if (showProject && project != null) {
      items.add(Text(
        project!.title,
        style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText),
        overflow: TextOverflow.ellipsis,
      ));
    }

    if (task.dueDate != null) {
      final overdue = task.isOverdue;
      final dueToday = task.isDueToday;
      items.add(Text(
        TodoFormat.metadataLabel(task.dueDate!),
        style: TextStyle(
          fontSize: TodoText.medium,
          color: overdue
              ? c.overdue
              : dueToday
                  ? c.accent
                  : c.secondaryText,
          fontWeight: overdue || dueToday ? FontWeight.w500 : FontWeight.normal,
        ),
      ));
    }

    if (task.reminders.isNotEmpty) {
      items.add(Icon(Icons.notifications_none, size: 15, color: c.secondaryText));
    }
    if (task.repeatAfter > 0) {
      items.add(Icon(Icons.repeat, size: 15, color: c.secondaryText));
    }
    if (task.description != null && task.description!.trim().isNotEmpty) {
      items.add(Icon(Icons.notes, size: 15, color: c.secondaryText));
    }
    if (task.commentCount > 0) {
      items.add(Icon(Icons.chat_bubble_outline, size: 14, color: c.secondaryText));
    }
    if (task.assignees.isNotEmpty) {
      items.add(
        CircleAvatar(
          radius: 8,
          backgroundColor: c.accent,
          child: Text(
            task.assignees.first.initials,
            style: TextStyle(fontSize: 7, color: c.onAccent),
          ),
        ),
      );
    }

    return items;
  }

  Widget _metadataRow(List<Widget> items, TodoColors c) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(Container(
          width: 2,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: c.secondaryText.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
        ));
      }
      children.add(items[i]);
    }
    return Row(children: children);
  }

}

class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.done, required this.onTap});

  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? c.accent : Colors.transparent,
              border: Border.all(
                color: done ? c.accent : c.secondaryText,
                width: 1.5,
              ),
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              scale: done ? 1 : 0,
              child: Icon(Icons.check, size: 14, color: c.onAccent),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22, color: color),
      tooltip: tooltip,
      splashRadius: 22,
    );
  }
}
