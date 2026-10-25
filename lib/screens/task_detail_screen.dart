import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_format.dart';
import '../todo_theme.dart';
import '../widgets/offline_banner.dart';
import '../widgets/task_extras.dart';
import '../widgets/unsaved_changes.dart';
import 'labels_screen.dart';

/// Task detail: title with a check target, then note / due date / reminder /
/// repeat / priority rows, with the creation date and delete in the footer.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId, this.initial});

  final int taskId;
  final VikunjaTask? initial;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  Timer? _debounce;
  bool _loading = true;
  bool _notesOpen = false;

  /// Whether the fields hold text the task does not have yet. A notifier, so
  /// typing does not have to rebuild the whole screen for the back guard.
  final _dirty = ValueNotifier<bool>(false);

  /// Set when the user confirmed leaving without the text: the flush in
  /// [deactivate] must then keep its hands off it.
  bool _discarded = false;

  /// Cached so the pending-edit flush never asks a dying element for its
  /// ancestors: by the time `dispose()` runs the element is defunct.
  AppState? _appState;

  @override
  void initState() {
    super.initState();
    // Only the editable text is widget-local; every other field is read from
    // [AppState], so a change made anywhere shows up here without a reload.
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _notes = TextEditingController(text: initial?.description ?? '');
    _notesOpen = initial?.description?.trim().isNotEmpty ?? false;
    _title.addListener(_onText);
    _notes.addListener(_onText);
    // Inherited lookups are not allowed before the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// The task, from the single source of truth. [widget.initial] only stands in
  /// for the frame before the state has it (a cold start or a deep link).
  VikunjaTask? _taskOf(AppState state) =>
      state.taskById(widget.taskId) ?? widget.initial;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = AppScope.of(context);
  }

  Future<void> _load() async {
    final fresh = await AppScope.of(context).loadTask(widget.taskId);
    if (!mounted) return;
    setState(() {
      // The state holds the fresh task now; the fields only need seeding.
      if (fresh != null) {
        if (_title.text.isEmpty) _title.text = fresh.title;
        if (_notes.text.isEmpty) _notes.text = fresh.description ?? '';
      }
      _loading = false;
    });
  }

  void _onText() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _saveText);
    _dirty.value = _pendingEdit() != null;
  }

  /// What is worth saving right now, or null when the text still matches the
  /// task (or there is nothing to save).
  ({VikunjaTask task, String title, String? description})? _pendingEdit() {
    final task = _appState?.taskById(widget.taskId) ?? widget.initial;
    if (task == null) return null;
    final title = _title.text.trim();
    if (title.isEmpty) return null;
    final description = _notes.text.trim().isEmpty ? null : _notes.text;
    // The server sends "" for a task without notes, `_notes` holds null: both
    // mean "no notes", so an untouched field is not an edit.
    final saved = (task.description ?? '').trim().isEmpty
        ? null
        : task.description;
    if (title == task.title && description == saved) return null;
    return (task: task, title: title, description: description);
  }

  /// Applies the pending edit. [afterFrame] is used when the screen is leaving
  /// the tree: the element is being removed *during* a build, and notifying the
  /// state from there would mark the scope dirty mid-build.
  void _saveText({bool afterFrame = false}) {
    final state = _appState;
    final edit = _pendingEdit();
    if (state == null || edit == null) return;
    void apply() => state.mutate(edit.task, (t) {
      t.title = edit.title;
      t.description = edit.description;
    });
    if (afterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
      _dirty.value = _pendingEdit() != null;
    }
  }

  @override
  void deactivate() {
    // The route is going away: flush the edit while the controllers are still
    // alive. There is no async teardown hook, so the save itself is not awaited;
    // `mutate()` applies the change locally first.
    _debounce?.cancel();
    if (!_discarded) _saveText(afterFrame: true);
    super.deactivate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dirty.dispose();
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final state = AppScope.of(context);
    final task = _taskOf(state);

    final scaffold = Scaffold(
      appBar: AppBar(
        actions: [
          if (task != null)
            IconButton(
              tooltip: task.isFavorite
                  ? 'Remove from Favorites'
                  : 'Add to Favorites',
              icon: Icon(
                task.isFavorite ? Icons.star : Icons.star_border,
                color: task.isFavorite ? c.starActive : c.secondaryText,
              ),
              onPressed: () => state.toggleImportant(task),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'delete') _delete(state, task);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: task == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                OfflineBanner(onRetry: state.refresh),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _TitleRow(
                        task: task,
                        controller: _title,
                        onToggleDone: () =>
                            _set(state, task, (t) => t.done = !t.done),
                      ),
                      const SizedBox(height: 8),
                      _NotesField(
                        controller: _notes,
                        open: _notesOpen,
                        onOpen: () => setState(() => _notesOpen = true),
                      ),
                      const Divider(height: 24),
                      _MetaRows(
                        task: task,
                        projectTitle:
                            state.projectOf(task)?.title ?? task.identifier,
                        onDue: () => _pickDate(state, task),
                        onDueClear: task.dueDate == null
                            ? null
                            : () => _set(state, task, (t) => t.dueDate = null),
                        onReminders: () => _pickReminder(state, task),
                        onRemindersClear: task.reminders.isEmpty
                            ? null
                            : () => _set(
                                state,
                                task,
                                (t) => t.reminders = const [],
                              ),
                        onRepeat: () => _pickRepeat(state, task),
                        onRepeatClear: task.repeatAfter == 0
                            ? null
                            : () => _set(state, task, (t) => t.repeatAfter = 0),
                        onPriority: () => _pickPriority(state, task),
                        onPriorityClear: task.priority == 0
                            ? null
                            : () => _set(state, task, (t) => t.priority = 0),
                        onLabels: () async {
                          await showLabelPicker(context, state, task);
                          await state.loadTask(task.id);
                        },
                      ),
                      _LabelChips(labels: task.labels),
                      AssigneesSection(task: task, onChanged: _reload),
                      RelationsSection(task: task, onChanged: _reload),
                      AttachmentsSection(taskId: task.id),
                      CommentsSection(taskId: task.id),
                      const SizedBox(height: 24),
                      const Divider(height: 1),
                      _FooterRow(
                        created: task.created,
                        onDelete: () => _delete(state, task),
                      ),
                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: Text(
                              'Syncing…',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.secondaryText,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
    // The title and the notes are saved on a 700 ms debounce: until that
    // lands, a back press would drop them.
    return ValueListenableBuilder<bool>(
      valueListenable: _dirty,
      builder: (context, dirty, child) => UnsavedChangesGuard(
        dirty: dirty,
        message: 'Your edits to this task have not been saved yet.',
        onDiscard: () => _discarded = true,
        child: child!,
      ),
      child: scaffold,
    );
  }

  Future<void> _reload() async {
    // The state keeps the result and notifies; there is no local copy to patch.
    await AppScope.read(context).loadTask(widget.taskId);
  }

  Future<void> _set(
    AppState state,
    VikunjaTask task,
    void Function(VikunjaTask) change,
  ) async {
    await state.mutate(task, change);
  }

  Future<void> _pickDate(AppState state, VikunjaTask task) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    final time =
        task.dueDate ?? DateTime(picked.year, picked.month, picked.day, 17);
    await _set(
      state,
      task,
      (t) => t.dueDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickReminder(AppState state, VikunjaTask task) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: task.reminders.isEmpty ? now : task.reminders.first.reminder,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        task.reminders.isEmpty ? now : task.reminders.first.reminder,
      ),
    );
    if (time == null) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await _set(
      state,
      task,
      (t) => t.reminders = [VikunjaReminder(reminder: at)],
    );
  }

  Future<void> _pickRepeat(AppState state, VikunjaTask task) async {
    // Vikunja's own repeat presets.
    const options = <(String, int)>[
      ('Never', 0),
      ('Every Day', 86400),
      ('Every Week', 604800),
      ('Every 30 Days', 2592000),
      ('Yearly', 31536000),
    ];
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (label, seconds) in options)
              ListTile(
                title: Text(label),
                trailing: task.repeatAfter == seconds
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => Navigator.pop(context, seconds),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _set(state, task, (t) => t.repeatAfter = choice);
  }

  Future<void> _pickPriority(AppState state, VikunjaTask task) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Priority',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (var p = 0; p <= 5; p++)
              ListTile(
                title: Text(TodoFormat.priority(p)),
                trailing: task.priority == p
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _set(state, task, (t) => t.priority = choice);
  }

  Future<void> _delete(AppState state, VikunjaTask? task) async {
    if (task == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task'),
        content: Text(
          'Are you sure you want to remove "${task.title}"? This will also '
          'remove all attachments, reminders and relations associated with '
          'this task and cannot be undone!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await state.deleteTask(task);
    if (mounted) Navigator.of(context).pop();
  }
}

/// The check target and the (autosaving) title field.
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.task,
    required this.controller,
    required this.onToggleDone,
  });

  final VikunjaTask task;
  final TextEditingController controller;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _DetailCheckbox(done: task.done, onTap: onToggleDone),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: null,
            style: TextStyle(
              fontSize: TodoText.xxl,
              fontWeight: FontWeight.w600,
              color: c.primaryText,
              decoration: task.done ? TextDecoration.lineThrough : null,
              decorationColor: c.secondaryText,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Task title',
            ),
          ),
        ),
      ],
    );
  }
}

/// The description: a "Set Description" button until it is opened, then the
/// multiline field.
class _NotesField extends StatelessWidget {
  const _NotesField({
    required this.controller,
    required this.open,
    required this.onOpen,
  });

  final TextEditingController controller;
  final bool open;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    if (!open) {
      return _RowButton(
        icon: Icons.notes,
        label: 'Set Description',
        onTap: onOpen,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.notes, size: 18, color: c.secondaryText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              minLines: 2,
              style: TextStyle(fontSize: TodoText.medium, color: c.primaryText),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Add a description, hit / for more options…',
                hintStyle: TextStyle(
                  color: c.secondaryText,
                  fontSize: TodoText.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Due date, reminders, repeat, priority, project and labels.
class _MetaRows extends StatelessWidget {
  const _MetaRows({
    required this.task,
    required this.projectTitle,
    required this.onDue,
    required this.onDueClear,
    required this.onReminders,
    required this.onRemindersClear,
    required this.onRepeat,
    required this.onRepeatClear,
    required this.onPriority,
    required this.onPriorityClear,
    required this.onLabels,
  });

  final VikunjaTask task;
  final String? projectTitle;
  final VoidCallback onDue;
  final VoidCallback? onDueClear;
  final VoidCallback onReminders;
  final VoidCallback? onRemindersClear;
  final VoidCallback onRepeat;
  final VoidCallback? onRepeatClear;
  final VoidCallback onPriority;
  final VoidCallback? onPriorityClear;
  final VoidCallback onLabels;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      children: [
        _RowValue(
          icon: Icons.calendar_today_outlined,
          label: 'Due Date',
          value: task.dueDate == null
              ? null
              : TodoFormat.dueLabel(task.dueDate!),
          valueColor: task.isOverdue ? c.overdue : c.accent,
          onTap: onDue,
          onClear: onDueClear,
        ),
        _RowValue(
          icon: Icons.notifications_none,
          label: 'Reminders',
          value: task.reminders.isEmpty
              ? null
              : TodoFormat.withTime(task.reminders.first.reminder),
          onTap: onReminders,
          onClear: onRemindersClear,
        ),
        _RowValue(
          icon: Icons.repeat,
          label: 'Repeat',
          value: task.repeatAfter > 0
              ? TodoFormat.repeat(task.repeatAfter)
              : null,
          onTap: onRepeat,
          onClear: onRepeatClear,
        ),
        _RowValue(
          icon: Icons.flag_outlined,
          label: 'Priority',
          value: task.priority > 0 ? TodoFormat.priority(task.priority) : null,
          onTap: onPriority,
          onClear: onPriorityClear,
        ),
        _RowValue(
          icon: Icons.list_alt,
          label: 'Project',
          value: projectTitle,
          onTap: null,
        ),
        _RowValue(
          icon: Icons.label_outline,
          label: 'Labels',
          value: task.labels.isEmpty
              ? null
              : task.labels.map((l) => l.title).join(', '),
          onTap: onLabels,
        ),
      ],
    );
  }
}

/// The label chips under the meta rows.
class _LabelChips extends StatelessWidget {
  const _LabelChips({required this.labels});

  final List<VikunjaLabel> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final c = TodoColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final label in labels)
            Chip(
              label: Text(
                label.title,
                style: TextStyle(
                  fontSize: 12,
                  color: TodoColors.serverColor(label.hexColor, c, min: 4.5),
                ),
              ),
              backgroundColor: TodoColors.serverColor(
                label.hexColor,
                c,
                min: 4.5,
              ).withValues(alpha: 0.15),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Creation date and the delete action.
class _FooterRow extends StatelessWidget {
  const _FooterRow({required this.created, required this.onDelete});

  final DateTime? created;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              TodoFormat.created(created),
              style: TextStyle(
                fontSize: TodoText.medium,
                color: c.secondaryText,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: c.secondaryText),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _DetailCheckbox extends StatelessWidget {
  const _DetailCheckbox({required this.done, required this.onTap});

  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? c.accent : Colors.transparent,
          border: Border.all(
            color: done ? c.accent : c.secondaryText,
            width: 1.5,
          ),
        ),
        child: done ? Icon(Icons.check, size: 15, color: c.onAccent) : null,
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c.secondaryText),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: TodoText.medium,
                color: c.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowValue extends StatelessWidget {
  const _RowValue({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.valueColor,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: hasValue ? c.accent : c.secondaryText),
          const SizedBox(width: 14),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Row(
                children: [
                  Text(
                    hasValue ? value! : label,
                    style: TextStyle(
                      fontSize: TodoText.medium,
                      color: hasValue
                          ? (valueColor ?? c.primaryText)
                          : c.secondaryText,
                    ),
                  ),
                  if (hasValue) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: TodoText.s,
                        color: c.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: c.secondaryText),
              tooltip: 'Clear',
              onPressed: onClear,
              splashRadius: 18,
            ),
        ],
      ),
    );
  }
}
