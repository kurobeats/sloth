import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_format.dart';
import '../todo_theme.dart';
import '../widgets/offline_banner.dart';
import 'task_detail_screen.dart';

/// Kanban board for a project, backed by its kanban view buckets.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.project});

  final VikunjaProject project;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  List<VikunjaBucket>? _buckets;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final buckets = await AppScope.of(context).board(widget.project);
    if (!mounted) return;
    setState(() {
      _buckets = buckets;
      _loading = false;
    });
  }

  Future<void> _move(int taskId, VikunjaBucket bucket) async {
    final state = AppScope.of(context);
    if (!requireOnline(context, state)) return;
    final error = await state.moveToBucket(widget.project, taskId, bucket.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final buckets = _buckets;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.title),
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
                : buckets == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        state.offline
                            ? 'The board needs a connection to your server.'
                            : 'This project has no kanban view.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    children: [
                      for (final bucket in buckets)
                        _Column(
                          bucket: bucket,
                          onDrop: (taskId) => _move(taskId, bucket),
                          onOpen: _open,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _open(VikunjaTask task) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.bucket,
    required this.onDrop,
    required this.onOpen,
  });

  final VikunjaBucket bucket;
  final ValueChanged<int> onDrop;
  final ValueChanged<VikunjaTask> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return DragTarget<int>(
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidate, rejected) => Container(
        // Wide enough to read a card, narrow enough to show the next column
        // peeking in on a phone.
        width: (MediaQuery.sizeOf(context).width * 0.78).clamp(220.0, 300.0),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: candidate.isEmpty ? c.secondaryBackground : c.hover,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: candidate.isEmpty ? c.divider : c.accent,
            width: candidate.isEmpty ? 1 : 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      bucket.title,
                      style: TextStyle(
                        fontSize: TodoText.medium,
                        fontWeight: FontWeight.w600,
                        color: c.primaryText,
                      ),
                    ),
                  ),
                  Text(
                    '${bucket.tasks.length}',
                    style: TextStyle(
                      fontSize: TodoText.small,
                      color: c.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                children: [
                  for (final task in bucket.tasks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Material(
                        color: c.primaryBackground,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onOpen(task),
                          child: Draggable<int>(
                            data: task.id,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: 240,
                                child: _Card(task: task, onOpen: () {}),
                              ),
                            ),
                            child: _Card(
                              task: task,
                              onOpen: () => onOpen(task),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (bucket.tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No tasks',
                        style: TextStyle(fontSize: 12, color: c.secondaryText),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.task, required this.onOpen});

  final VikunjaTask task;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final due = task.dueDate;
    final meta = <String>[
      if (due != null) TodoFormat.dueLabel(due),
      if (task.labels.isNotEmpty) task.labels.first.title,
    ].where((e) => e.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: task.done ? c.accent : c.secondaryText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: TodoText.medium,
                    color: task.done ? c.secondaryText : c.primaryText,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Text(
                meta.join(' · '),
                style: TextStyle(fontSize: 11, color: c.secondaryText),
              ),
            ),
        ],
      ),
    );
  }
}
