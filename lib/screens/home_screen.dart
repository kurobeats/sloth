import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_format.dart';
import '../todo_theme.dart';
import '../widgets/entry_bar.dart';
import '../widgets/offline_banner.dart';
import '../widgets/task_tile.dart';
import 'labels_screen.dart';
import 'project_settings_screen.dart';
import 'board_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'teams_screen.dart';
import 'task_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showCompleted = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  IconData _iconFor(SmartList list) => switch (list) {
    SmartList.dueToday => Icons.today_outlined,
    SmartList.favorites => Icons.star_border,
    SmartList.upcoming => Icons.event_outlined,
    SmartList.allTasks => Icons.home_outlined,
    SmartList.assigned => Icons.person_outline,
  };

  Future<void> _add(String title) async {
    final state = AppScope.of(context);
    if (!requireOnline(context, state)) return;
    VikunjaProject? target = state.selection.project;
    if (target == null) {
      final projects = state.writableProjects
          .where((p) => !p.isArchived)
          .toList();
      if (projects.isEmpty) {
        // Nothing to add the task to. Silently dropping the typed title looks
        // like the app lost it; say what is missing instead.
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Create a list first')));
        return;
      }
      if (projects.length > 1) {
        target = await showModalBottomSheet<VikunjaProject>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Choose a project',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                for (final p in projects)
                  ListTile(
                    leading: Icon(
                      Icons.list_alt,
                      color: TodoColors.serverColor(
                        p.hexColor,
                        TodoColors.of(context),
                      ),
                    ),
                    title: Text(p.title),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            ),
          ),
        );
      } else {
        target = projects.first;
      }
    }
    if (target == null) return;
    await state.addTask(title, project: target);
  }

  Future<void> _openTask(VikunjaTask task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(taskId: task.id, initial: task),
      ),
    );
  }

  Future<void> _confirmDelete(AppState state, VikunjaTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task'),
        content: Text(
          'Are you sure you want to remove "${task.title}"? This cannot be undone.',
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
    // `deleteTask` reports failures through `state.error`.
    await state.deleteTask(task);
    if (!mounted) return;
    final error = state.error;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _createList(BuildContext context, AppState state) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateListDialog(),
    );
    if (title == null || title.isEmpty) return;
    if (!context.mounted) return;
    final accent = Theme.of(context)
        .extension<TodoThemeExtension>()
        ?.colors
        .accent;
    final error = await state.createProject(
      title,
      hexColor: accent == null ? null : TodoColors.toHex(accent),
    );
    if (!context.mounted) return;
    if (error == null) {
      await state.refresh();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final open = state.openTasks;
    final completed = state.completedTasks;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _Drawer(
        iconFor: _iconFor,
        onCreateProject: () => _createList(context, state),
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(state.selection.title),
        actions: [
          if (state.selection.project?.kanbanViewId != null)
            IconButton(
              icon: const Icon(Icons.view_kanban_outlined),
              tooltip: 'Kanban board',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      BoardScreen(project: state.selection.project!),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'refresh':
                  await state.refresh();
                case 'project':
                  final project = state.selection.project;
                  if (project != null) {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProjectSettingsScreen(project: project),
                      ),
                    );
                  }
                case 'appearance':
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                case 'signout':
                  await state.signOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              if (state.selection.project != null)
                const PopupMenuItem(
                  value: 'project',
                  child: Text('Project settings'),
                ),
              const PopupMenuItem(value: 'appearance', child: Text('Settings')),
              const PopupMenuItem(value: 'signout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(onRetry: state.refresh),
          if (state.listTruncated) const _TruncationNotice(),
          Expanded(
            child: RefreshIndicator(
              color: c.accent,
              onRefresh: state.refresh,
              child: _body(state, open, completed, c),
            ),
          ),
          EntryBar(
            onSubmit: _add,
            enabled: state.canEdit,
            disabledHint: 'Editing is disabled while offline',
          ),
        ],
      ),
    );
  }

  Widget _body(
    AppState state,
    List<VikunjaTask> open,
    List<VikunjaTask> completed,
    TodoColors c,
  ) {
    if (state.loading && open.isEmpty && completed.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && open.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.cloud_off, size: 48, color: c.secondaryText),
          const SizedBox(height: 16),
          Text(
            state.error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.secondaryText),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: state.refresh,
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    // Rows are flattened once into lazily-called builders: a task list can hold
    // hundreds of tasks, and building a TaskTile for each of them up front would
    // cost tens of thousands of widgets for the dozen rows that fit on screen.
    final rows = <Widget Function()>[];
    final showProject = state.selection.showProject;

    void addTile(VikunjaTask task) {
      rows.add(
        () => TaskTile(
          key: ValueKey('task-${task.id}'),
          task: task,
          project: state.projectOf(task),
          showProject: showProject,
          onTap: () => _openTask(task),
          onToggleDone: () {
            if (requireOnline(context, state)) state.toggleDone(task);
          },
          onToggleStar: () {
            if (requireOnline(context, state)) state.toggleImportant(task);
          },
          onLongPress: () {
            if (requireOnline(context, state)) _taskMenu(state, task);
          },
        ),
      );
    }

    if (open.isEmpty && completed.isEmpty) {
      rows.add(() => _EmptyState(list: state.selection));
    } else if (state.selection.groupsByDay) {
      for (final group in TodoFormat.groupByDay(open, (t) => t.dueDate)) {
        final label = TodoFormat.groupHeader(group.day);
        rows.add(() => _GroupHeader(label: label));
        for (final t in group.tasks) {
          addTile(t);
        }
      }
    } else {
      for (final t in open) {
        addTile(t);
      }
    }

    if (completed.isNotEmpty) {
      final completedCount = completed.length;
      rows.add(
        () => InkWell(
          onTap: () => setState(() => _showCompleted = !_showCompleted),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(
                  _showCompleted ? Icons.expand_more : Icons.chevron_right,
                  size: 20,
                  color: c.secondaryText,
                ),
                const SizedBox(width: 8),
                Text(
                  'Done',
                  style: TextStyle(
                    fontSize: TodoText.big,
                    color: c.secondaryText,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$completedCount',
                  style: TextStyle(
                    fontSize: TodoText.medium,
                    color: c.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (_showCompleted) {
        for (final t in completed) {
          addTile(t);
        }
      }
    }

    rows.add(() => const SizedBox(height: 24));

    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](),
    );
  }

  Future<void> _taskMenu(AppState state, VikunjaTask task) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(task.isFavorite ? Icons.star : Icons.star_border),
              title: Text(
                task.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
              ),
              onTap: () => Navigator.pop(context, 'star'),
            ),
            ListTile(
              leading: Icon(task.done ? Icons.undo : Icons.check),
              title: Text(task.done ? 'Mark as undone' : 'Mark task done!'),
              onTap: () => Navigator.pop(context, 'done'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'star':
        await state.toggleImportant(task);
      case 'done':
        await state.toggleDone(task);
      case 'delete':
        await _confirmDelete(state, task);
    }
  }
}

class _TruncationNotice extends StatelessWidget {
  const _TruncationNotice();

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        AppState.truncationNotice,
        style: TextStyle(fontSize: TodoText.small, color: c.secondaryText),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: TodoText.medium,
              fontWeight: FontWeight.w600,
              color: c.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.list});

  final ListSelection list;

  @override
  Widget build(BuildContext context) {
    // Read here, not from a field: the colours must follow a theme change
    // without the list having to hand them down.
    final c = TodoColors.of(context);
    final (icon, title, subtitle) = list.tag != null
        ? (
            Icons.label_outline,
            'No tasks with this label',
            'Labels are added to tasks in Vikunja.',
          )
        : list.project != null
        ? (
            Icons.check_circle_outline,
            'This project is currently empty.',
            'Create a new task with the bar below.',
          )
        : switch (list.smart) {
            SmartList.dueToday => (
              Icons.today_outlined,
              'Nothing due today',
              'Tasks due today or overdue show up here.',
            ),
            SmartList.favorites => (
              Icons.star_border,
              'No favorites yet',
              'Tasks you mark as favorite show up here.',
            ),
            SmartList.upcoming => (
              Icons.event_outlined,
              'Nothing upcoming',
              'Tasks with a due date show up here.',
            ),
            SmartList.assigned => (
              Icons.person_outline,
              'No tasks assigned to you',
              'Tasks assigned to you show up here.',
            ),
            SmartList.allTasks => (
              Icons.check_circle_outline,
              'No tasks yet',
              'Create a new task with the bar below.',
            ),
            null => (
              Icons.check_circle_outline,
              'No tasks yet',
              'Create a new task with the bar below.',
            ),
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      child: Column(
        children: [
          Icon(icon, size: 56, color: c.secondaryText.withValues(alpha: 0.6)),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: TodoText.xl, color: c.primaryText),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText),
          ),
        ],
      ),
    );
  }
}

/// Every count the drawer shows, gathered in one pass over the task list.
///
/// The state counts one list at a time; the drawer needs all of them, so it
/// counts locally rather than scanning the list twice per row.
class _DrawerCounts {
  _DrawerCounts(List<VikunjaTask> tasks, {required int? me}) {
    final today = startOfDay(DateTime.now());
    final tomorrow = endOfToday(DateTime.now());
    for (final t in tasks) {
      if (t.done) continue;
      projects.update(t.projectId, (n) => n + 1, ifAbsent: () => 1);
      for (final id in {for (final l in t.labels) l.id}) {
        labels.update(id, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final smart in SmartList.values) {
        if (_matches(smart, t, today, tomorrow, me)) {
          this.smart.update(smart, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
  }

  final smart = <SmartList, int>{};
  final projects = <int, int>{};
  final labels = <int, int>{};

  /// Mirrors `AppState.countFor`, which the drawer cannot call per row.
  static bool _matches(
    SmartList smart,
    VikunjaTask t,
    DateTime today,
    DateTime tomorrow,
    int? me,
  ) => switch (smart) {
    SmartList.dueToday => t.isDueBy(tomorrow),
    SmartList.favorites => t.isFavorite,
    SmartList.upcoming =>
      t.dueDate != null &&
          !DateTime(
            t.dueDate!.year,
            t.dueDate!.month,
            t.dueDate!.day,
          ).isBefore(today) &&
          t.dueDate!.isBefore(today.add(const Duration(days: 7))),
    SmartList.assigned => me != null && t.assignees.any((a) => a.id == me),
    SmartList.allTasks => true,
  };
}

class _Drawer extends StatefulWidget {
  const _Drawer({required this.iconFor, required this.onCreateProject});

  final IconData Function(SmartList) iconFor;
  final VoidCallback onCreateProject;

  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  List<VikunjaTask>? _countedSource;
  _DrawerCounts? _counts;

  /// Counted once per task list; mutations replace the list, so identity is the
  /// signal to recount.
  _DrawerCounts _countsFor(AppState state) {
    final source = state.allTasksForWidget;
    if (!identical(source, _countedSource)) {
      _countedSource = source;
      _counts = _DrawerCounts(source, me: state.user?.id);
    }
    return _counts!;
  }

  void _close() => Navigator.pop(context);

  void _push(Widget screen) {
    _close();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final counts = _countsFor(state);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _DrawerHeader(state: state),
            _DrawerRow(
              icon: Icons.notifications_none,
              label: 'Notifications',
              trailing: state.unreadNotifications,
              onTap: () => _push(const NotificationsScreen()),
            ),
            _SmartListRows(
              iconFor: widget.iconFor,
              counts: counts.smart,
              selected: state.selection.smart,
              onSelected: (smart) {
                _close();
                state.select(ListSelection.smart(smart));
              },
            ),
            _ProjectRows(
              projects: state.sortedProjects,
              counts: counts.projects,
              selectedId: state.selection.project?.id,
              onCreate: widget.onCreateProject,
              onSelected: (project) {
                _close();
                state.select(ListSelection.project(project));
              },
              onSettings: (project) =>
                  _push(ProjectSettingsScreen(project: project)),
            ),
            _FilterRows(
              filters: state.savedFilters,
              selectedId: state.selection.project?.id,
              onSelected: (filter) {
                _close();
                state.select(ListSelection.project(filter));
              },
            ),
            _LabelRows(
              labels: state.labels,
              counts: counts.labels,
              selectedId: state.selection.tag?.id,
              onCreate: () => _push(const LabelsScreen()),
              onSelected: (label) {
                _close();
                state.select(ListSelection.tag(label));
              },
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: c.divider),
            _DrawerRow(
              icon: Icons.groups_outlined,
              label: 'Teams',
              trailing: state.teams.length,
              onTap: () => _push(const TeamsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final user = state.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 8, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: c.accent,
            foregroundImage: state.avatar == null
                ? null
                : MemoryImage(state.avatar!),
            child: Text(
              user?.initials ?? '?',
              style: TextStyle(color: c.onAccent, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TodoText.big,
                    fontWeight: FontWeight.w600,
                    color: c.primaryText,
                  ),
                ),
                if (user?.email != null)
                  Text(
                    user!.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TodoText.s,
                      color: c.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            color: c.secondaryText,
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
            },
          ),
        ],
      ),
    );
  }
}

class _SmartListRows extends StatelessWidget {
  const _SmartListRows({
    required this.iconFor,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final IconData Function(SmartList) iconFor;
  final Map<SmartList, int> counts;
  final SmartList? selected;
  final ValueChanged<SmartList> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final smart in SmartList.values)
          _DrawerRow(
            icon: iconFor(smart),
            label: smart.label,
            trailing: counts[smart] ?? 0,
            selected: selected == smart,
            onTap: () => onSelected(smart),
          ),
      ],
    );
  }
}

class _ProjectRows extends StatelessWidget {
  const _ProjectRows({
    required this.projects,
    required this.counts,
    required this.selectedId,
    required this.onCreate,
    required this.onSelected,
    required this.onSettings,
  });

  final List<VikunjaProject> projects;
  final Map<int, int> counts;
  final int? selectedId;
  final VoidCallback onCreate;
  final ValueChanged<VikunjaProject> onSelected;
  final ValueChanged<VikunjaProject> onSettings;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      children: [
        _DrawerSectionHeader(
          label: 'Projects',
          tooltip: 'New project',
          onAction: onCreate,
        ),
        for (final project in projects)
          _DrawerRow(
            icon: Icons.list_alt,
            iconColor: TodoColors.serverColor(project.hexColor, c, min: 3.5),
            label: project.title,
            trailing: counts[project.id] ?? 0,
            selected: selectedId == project.id,
            onTap: () => onSelected(project),
            onLongPress: () => onSettings(project),
          ),
      ],
    );
  }
}

class _FilterRows extends StatelessWidget {
  const _FilterRows({
    required this.filters,
    required this.selectedId,
    required this.onSelected,
  });

  final List<VikunjaProject> filters;
  final int? selectedId;
  final ValueChanged<VikunjaProject> onSelected;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    final c = TodoColors.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            'Filters',
            style: TextStyle(
              fontSize: TodoText.small,
              fontWeight: FontWeight.w600,
              color: c.secondaryText,
            ),
          ),
        ),
        for (final filter in filters)
          _DrawerRow(
            icon: Icons.filter_alt_outlined,
            label: filter.title,
            selected: selectedId == filter.id,
            onTap: () => onSelected(filter),
          ),
      ],
    );
  }
}

class _LabelRows extends StatelessWidget {
  const _LabelRows({
    required this.labels,
    required this.counts,
    required this.selectedId,
    required this.onCreate,
    required this.onSelected,
  });

  final List<VikunjaLabel> labels;
  final Map<int, int> counts;
  final int? selectedId;
  final VoidCallback onCreate;
  final ValueChanged<VikunjaLabel> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      children: [
        _DrawerSectionHeader(
          label: 'Labels',
          tooltip: 'New label',
          onAction: onCreate,
        ),
        for (final label in labels)
          _DrawerRow(
            icon: Icons.label_outline,
            iconColor: TodoColors.serverColor(label.hexColor, c, min: 3.5),
            label: label.title,
            trailing: counts[label.id] ?? 0,
            selected: selectedId == label.id,
            onTap: () => onSelected(label),
          ),
      ],
    );
  }
}

/// The "Projects" / "Labels" header: a label and an add button.
class _DrawerSectionHeader extends StatelessWidget {
  const _DrawerSectionHeader({
    required this.label,
    required this.tooltip,
    required this.onAction,
  });

  final String label;
  final String tooltip;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
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
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            color: c.secondaryText,
            tooltip: tooltip,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// New project form. Owns its controller so it dies with the dialog.
class _CreateListDialog extends StatefulWidget {
  const _CreateListDialog();

  @override
  State<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends State<_CreateListDialog> {
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New project'),
      content: TextField(
        controller: _title,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: "The project's title goes here…",
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _title.text.trim()),
          child: const Text('Create project'),
        ),
      ],
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.iconColor,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int? trailing;
  final bool selected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 44,
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.10) : null,
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected ? c.accent : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? c.accent),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TodoText.medium,
                  color: selected ? c.accent : c.primaryText,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (trailing != null && trailing! > 0)
              Text(
                '$trailing',
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
