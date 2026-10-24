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
      final projects = state.writableProjects.where((p) => !p.isArchived).toList();
      if (projects.isEmpty) return;
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
                  child: Text('Choose a project',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                for (final p in projects)
                  ListTile(
                    leading: Icon(
                      Icons.list_alt,
                      color: TodoColors.serverColor(p.hexColor, TodoColors.of(context)),
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
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id, initial: task)),
    );
  }

  void _confirmDelete(AppState state, VikunjaTask task) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task'),
        content: Text(
          'Are you sure you want to remove "${task.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              state.deleteTask(task);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final open = state.openTasks;
    final completed = state.completedTasks;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _Drawer(iconFor: _iconFor),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(state.selection.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
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
                const PopupMenuItem(value: 'project', child: Text('Project settings')),
              const PopupMenuItem(value: 'appearance', child: Text('Settings')),
              const PopupMenuItem(value: 'signout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(onRetry: state.refresh),
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

  Widget _body(AppState state, List<VikunjaTask> open,
      List<VikunjaTask> completed, TodoColors c) {
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
          Text(state.error!, textAlign: TextAlign.center, style: TextStyle(color: c.secondaryText)),
          const SizedBox(height: 16),
          Center(
            child: TextButton(onPressed: state.refresh, child: const Text('Try again')),
          ),
        ],
      );
    }

    final rows = <Widget>[];
    final showProject = state.selection.tag != null ||
        state.selection.smart == SmartList.allTasks ||
        state.selection.smart == SmartList.assigned ||
        state.selection.smart == SmartList.favorites;

    void addTile(VikunjaTask task) {
      rows.add(TaskTile(
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
      ));
    }

    if (open.isEmpty && completed.isEmpty) {
      rows.add(_EmptyState(list: state.selection, c: c));
    } else if (state.selection.groupsByDay) {
      for (final group in TodoFormat.groupByDay(open, (t) => t.dueDate)) {
        rows.add(_GroupHeader(label: TodoFormat.groupHeader(group.day)));
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
      rows.add(InkWell(
        onTap: () => setState(() => _showCompleted = !_showCompleted),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Icon(_showCompleted ? Icons.expand_more : Icons.chevron_right,
                  size: 20, color: c.secondaryText),
              const SizedBox(width: 8),
              Text('Done',
                  style: TextStyle(fontSize: TodoText.big, color: c.secondaryText)),
              const SizedBox(width: 8),
              Text('${completed.length}',
                  style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText)),
            ],
          ),
        ),
      ));
      if (_showCompleted) {
        for (final t in completed) {
          addTile(t);
        }
      }
    }

    rows.add(const SizedBox(height: 24));

    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      children: rows,
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
              title: Text(task.isFavorite
                  ? 'Remove from Favorites'
                  : 'Add to Favorites'),
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
    switch (action) {
      case 'star':
        await state.toggleImportant(task);
      case 'done':
        await state.toggleDone(task);
      case 'delete':
        _confirmDelete(state, task);
    }
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
  const _EmptyState({required this.list, required this.c});

  final ListSelection list;
  final TodoColors c;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = list.tag != null
        ? (
            Icons.label_outline,
            'No tasks with this label',
            'Labels are added to tasks in Vikunja.'
          )
        : list.project != null
            ? (
                Icons.check_circle_outline,
                'This project is currently empty.',
                'Create a new task with the bar below.'
              )
            : switch (list.smart) {
                SmartList.dueToday => (
                    Icons.today_outlined,
                    'Nothing due today',
                    'Tasks due today or overdue show up here.'
                  ),
                SmartList.favorites => (
                    Icons.star_border,
                    'No favorites yet',
                    'Tasks you mark as favorite show up here.'
                  ),
                SmartList.upcoming => (
                    Icons.event_outlined,
                    'Nothing upcoming',
                    'Tasks with a due date show up here.'
                  ),
                SmartList.assigned => (
                    Icons.person_outline,
                    'No tasks assigned to you',
                    'Tasks assigned to you show up here.'
                  ),
                SmartList.allTasks => (
                    Icons.check_circle_outline,
                    'No tasks yet',
                    'Create a new task with the bar below.'
                  ),
                null => (
                    Icons.check_circle_outline,
                    'No tasks yet',
                    'Create a new task with the bar below.'
                  ),
              };
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      child: Column(
        children: [
          Icon(icon, size: 56, color: c.secondaryText.withValues(alpha: 0.6)),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: TodoText.xl, color: c.primaryText)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText)),
        ],
      ),
    );
  }
}

class _Drawer extends StatelessWidget {
  const _Drawer({required this.iconFor});

  final IconData Function(SmartList) iconFor;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final user = state.user;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
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
                                fontSize: TodoText.s, color: c.secondaryText),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    color: c.secondaryText,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            for (final smart in SmartList.values)
              _DrawerRow(
                icon: iconFor(smart),
                label: smart.label,
                trailing: state.countFor(smart),
                selected: state.selection.smart == smart,
                onTap: () {
                  Navigator.pop(context);
                  state.select(ListSelection.smart(smart));
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Projects',
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
                    tooltip: 'New project',
                    onPressed: () => _createList(context, state),
                  ),
                ],
              ),
            ),
            for (final project in state.sortedProjects)
              _DrawerRow(
                icon: Icons.list_alt,
                iconColor: TodoColors.serverColor(project.hexColor, c, min: 3.5),
                label: project.title,
                trailing: state.countForProject(project),
                selected: state.selection.project?.id == project.id,
                onTap: () {
                  Navigator.pop(context);
                  state.select(ListSelection.project(project));
                },
                onLongPress: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProjectSettingsScreen(project: project),
                    ),
                  );
                },
              ),
            if (state.savedFilters.isNotEmpty)
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
            for (final filter in state.savedFilters)
              _DrawerRow(
                icon: Icons.filter_alt_outlined,
                label: filter.title,
                selected: state.selection.project?.id == filter.id,
                onTap: () {
                  Navigator.pop(context);
                  state.select(ListSelection.project(filter));
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Labels',
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
                    tooltip: 'New label',
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LabelsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            for (final label in state.labels)
              _DrawerRow(
                icon: Icons.label_outline,
                iconColor: TodoColors.serverColor(label.hexColor, c, min: 3.5),
                label: label.title,
                trailing: state.countForTag(label),
                selected: state.selection.tag?.id == label.id,
                onTap: () {
                  Navigator.pop(context);
                  state.select(ListSelection.tag(label));
                },
              ),
            const SizedBox(height: 12),
            Divider(height: 1, color: c.divider),
            _DrawerRow(
              icon: Icons.groups_outlined,
              label: 'Teams',
              trailing: state.teams.length,
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TeamsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createList(BuildContext context, AppState state) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "The project's title goes here…",
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create project'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      final accent = Theme.of(context).extension<TodoThemeExtension>()?.colors.accent;
      final hex = accent == null
          ? null
          : '#${(accent.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      await state.api!.createProject(title.trim(), hexColor: hex);
      await state.refresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create project: $e')));
      }
    }
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
                style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText),
              ),
          ],
        ),
      ),
    );
  }
}
