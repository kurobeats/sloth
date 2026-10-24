import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../screens/task_detail_screen.dart';
import '../screens/team_detail_screen.dart' show showUserSearch;
import '../state.dart';
import '../todo_format.dart';
import '../todo_theme.dart';
import 'offline_banner.dart';

// --------------------------------------------------------------- tiles -----
// Presentation only: no AppScope, no network. The sections below wire these to
// the app state, so the tiles can be tested on their own.

class RelationTile extends StatelessWidget {
  const RelationTile({
    super.key,
    required this.relation,
    required this.onOpen,
    required this.onToggleDone,
    required this.onRemove,
  });

  final VikunjaRelation relation;
  final VoidCallback onOpen;
  final VoidCallback onToggleDone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final isSubtask = relation.kind == VikunjaRelation.subtask;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: isSubtask
          ? IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: relation.done ? 'Mark task undone' : 'Mark task done',
              icon: Icon(
                relation.done
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
                color: relation.done ? c.accent : c.secondaryText,
              ),
              onPressed: onToggleDone,
            )
          : Icon(Icons.link, size: 18, color: c.accent),
      title: Text(
        relation.title,
        style: TextStyle(
          color: relation.done ? c.secondaryText : c.primaryText,
          decoration: relation.done ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        VikunjaRelation.label(relation.kind),
        style: TextStyle(fontSize: 11, color: c.secondaryText),
      ),
      onTap: onOpen,
      trailing: IconButton(
        tooltip: 'Remove relation',
        icon: Icon(Icons.close, size: 16, color: c.secondaryText),
        onPressed: onRemove,
      ),
    );
  }
}

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.onOpen,
    required this.onRemove,
  });

  final VikunjaAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.attach_file, size: 18, color: c.accent),
      title: Text(attachment.name, style: TextStyle(color: c.primaryText)),
      subtitle: Text(
        attachment.readableSize,
        style: TextStyle(fontSize: 11, color: c.secondaryText),
      ),
      onTap: onOpen,
      trailing: IconButton(
        tooltip: 'Delete attachment',
        icon: Icon(Icons.close, size: 16, color: c.secondaryText),
        onPressed: onRemove,
      ),
    );
  }
}

class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  final VikunjaComment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final author = comment.author?.displayName ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: c.accent,
            child: Text(
              author.isEmpty ? '?' : author.substring(0, 1).toUpperCase(),
              style: TextStyle(fontSize: 9, color: c.onAccent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      author,
                      style: TextStyle(
                        fontSize: TodoText.small,
                        fontWeight: FontWeight.w600,
                        color: c.primaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      comment.created == null
                          ? ''
                          : TodoFormat.metadataLabel(comment.created!),
                      style: TextStyle(fontSize: 11, color: c.secondaryText),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.comment,
                  style: TextStyle(
                    fontSize: TodoText.medium,
                    color: c.primaryText,
                  ),
                ),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              tooltip: 'Delete this comment',
              icon: Icon(Icons.close, size: 14, color: c.secondaryText),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ sections -----

/// Assignees for a task (`/tasks/{id}/assignees`).
class AssigneesSection extends StatelessWidget {
  const AssigneesSection({
    super.key,
    required this.task,
    required this.onChanged,
  });

  final VikunjaTask task;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          label: 'Assignees',
          action: task.assignees.isEmpty ? null : 'Add',
          onAction: () => _add(context, state),
        ),
        if (task.assignees.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: InkWell(
              onTap: () => _add(context, state),
              child: Text(
                'Assign to User',
                style: TextStyle(
                  fontSize: TodoText.medium,
                  color: c.secondaryText,
                ),
              ),
            ),
          ),
        for (final user in task.assignees)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: c.accent,
              child: Text(
                user.initials,
                style: TextStyle(fontSize: 10, color: c.onAccent),
              ),
            ),
            title: Text(
              user.displayName,
              style: TextStyle(color: c.primaryText),
            ),
            trailing: IconButton(
              tooltip: 'Remove assignee',
              icon: Icon(Icons.close, size: 16, color: c.secondaryText),
              onPressed: () async {
                if (!requireOnline(context, state)) return;
                final error = await state.unassign(task, user);
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                }
                onChanged();
              },
            ),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context, AppState state) async {
    if (!requireOnline(context, state)) return;
    final user = await showUserSearch(context, state);
    if (user == null) return;
    final error = await state.assign(task, user);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    onChanged();
  }
}

/// Task relations, e.g. subtasks (`/tasks/{id}/relations`).
class RelationsSection extends StatelessWidget {
  const RelationsSection({
    super.key,
    required this.task,
    required this.onChanged,
  });

  final VikunjaTask task;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final relations = task.relations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          label: 'Related Tasks',
          action: 'Add relation',
          onAction: () => _add(context, state),
        ),
        if (relations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No related tasks',
              style: TextStyle(
                fontSize: TodoText.medium,
                color: c.secondaryText,
              ),
            ),
          ),
        for (final relation in relations)
          RelationTile(
            relation: relation,
            onOpen: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TaskDetailScreen(taskId: relation.taskId),
                ),
              );
              onChanged();
            },
            onToggleDone: () async {
              if (!requireOnline(context, state)) return;
              final target = state.taskById(relation.taskId);
              if (target != null) await state.toggleDone(target);
              onChanged();
            },
            onRemove: () async {
              if (!requireOnline(context, state)) return;
              final error = await state.removeRelation(
                task.id,
                relation.kind,
                relation.taskId,
              );
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error)));
              }
              onChanged();
            },
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context, AppState state) async {
    if (!requireOnline(context, state)) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Relation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final k in VikunjaRelation.selectableKinds)
              ListTile(
                title: Text(VikunjaRelation.label(k)),
                onTap: () => Navigator.pop(context, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !context.mounted) return;

    final target = await showModalBottomSheet<VikunjaTask>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(height: 420, child: _TaskSearchSheet(state: state)),
      ),
    );
    if (target == null) return;
    final error = await state.addRelation(task.id, target.id, kind);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    onChanged();
  }
}

class _TaskSearchSheet extends StatefulWidget {
  const _TaskSearchSheet({required this.state});

  final AppState state;

  @override
  State<_TaskSearchSheet> createState() => _TaskSearchSheetState();
}

class _TaskSearchSheetState extends State<_TaskSearchSheet> {
  final _controller = TextEditingController();
  List<VikunjaTask> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    final results = await widget.state.searchTasks(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search tasks',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _search,
              ),
            ),
          ),
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        Expanded(
          child: ListView(
            children: [
              if (!_searching && _results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Search for a task to relate',
                    style: TextStyle(color: c.secondaryText),
                  ),
                ),
              for (final task in _results)
                ListTile(
                  title: Text(task.title),
                  subtitle: Text(
                    task.identifier ?? '',
                    style: TextStyle(fontSize: 11, color: c.secondaryText),
                  ),
                  onTap: () => Navigator.pop(context, task),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// File attachments (`/tasks/{id}/attachments`).
class AttachmentsSection extends StatefulWidget {
  const AttachmentsSection({super.key, required this.taskId});

  final int taskId;

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  List<VikunjaAttachment> _items = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    try {
      final items = await state.attachmentsOf(widget.taskId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final state = AppScope.of(context);
    if (!requireOnline(context, state)) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty) return;
      final file = picked.first;
      final bytes = await file.xFile.readAsBytes();
      if (bytes.isEmpty) return;
      final error = await state.uploadAttachment(
        widget.taskId,
        file.name,
        bytes,
      );
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      await _load();
    } finally {
      // Cancelling the picker must not leave the button spinning forever.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(VikunjaAttachment attachment) async {
    final state = AppScope.of(context);
    final bytes = await state.downloadAttachment(widget.taskId, attachment.id);
    if (bytes == null) return;
    // Share needs a real file to keep the original name and mime type.
    final dir = await Directory.systemTemp.createTemp('sloth-share');
    final name = attachment.name.replaceAll(RegExp(r'[/\\]'), '_');
    final file = await File('${dir.path}/$name').writeAsBytes(bytes);
    await Share.shareXFiles([
      XFile(file.path, name: name, mimeType: attachment.mime),
    ]);
    await dir.delete(recursive: true).catchError((_) => dir);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          label: 'Attachments',
          action: _busy ? null : 'Add Attachments',
          onAction: _upload,
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No attachments',
              style: TextStyle(
                fontSize: TodoText.medium,
                color: c.secondaryText,
              ),
            ),
          ),
        for (final attachment in _items)
          AttachmentTile(
            attachment: attachment,
            onOpen: () => _share(attachment),
            onRemove: () async {
              if (!requireOnline(context, state)) return;
              await state.deleteAttachment(widget.taskId, attachment.id);
              await _load();
            },
          ),
      ],
    );
  }
}

/// Task comments (`/tasks/{id}/comments`).
class CommentsSection extends StatefulWidget {
  const CommentsSection({super.key, required this.taskId});

  final int taskId;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _controller = TextEditingController();
  List<VikunjaComment> _items = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    try {
      final items = await state.commentsOf(widget.taskId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final state = AppScope.of(context);
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!requireOnline(context, state)) return;
    setState(() => _busy = true);
    final error = await state.addComment(widget.taskId, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _controller.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final me = state.user?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(label: 'Comments'),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        for (final comment in _items)
          CommentTile(
            comment: comment,
            canDelete: comment.author?.id == me,
            onDelete: () async {
              if (!requireOnline(context, state)) return;
              await state.deleteComment(widget.taskId, comment.id);
              await _load();
            },
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: TextStyle(
                  fontSize: TodoText.medium,
                  color: c.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: 'Add your comment…',
                  hintStyle: TextStyle(
                    fontSize: TodoText.medium,
                    color: c.secondaryText,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              tooltip: 'Add',
              onPressed: _busy ? null : _send,
              icon: Icon(Icons.send, size: 18, color: c.accent),
            ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label, this.action, this.onAction});

  final String label;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: TodoText.small,
                fontWeight: FontWeight.w600,
                color: c.secondaryText,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
