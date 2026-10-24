import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';

/// Edit a team: name, description and members.
class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final int teamId;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<VikunjaTeamMember> _members = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  VikunjaTeam? get _team {
    final state = AppScope.of(context);
    for (final team in state.teams) {
      if (team.id == widget.teamId) return team;
    }
    return null;
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    final team = _team;
    if (team != null) {
      _name.text = team.name;
      _description.text = team.description ?? '';
    }
    try {
      final members = await state.membersOf(widget.teamId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save(AppState state) async {
    final team = _team;
    if (team == null) return;
    final error = await state.saveTeam(
      team,
      name: _name.text.trim(),
      description: _description.text.trim(),
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _addMember(AppState state) async {
    final user = await showUserSearch(context, state);
    if (user == null) return;
    final error = await state.addTeamMember(widget.teamId, user.username);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    await _load();
  }

  Future<void> _deleteTeam(AppState state) async {
    final team = _team;
    if (team == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${team.name}"?'),
        content: const Text(
          'The team will be removed. Projects shared with it stay in place.',
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
    await state.deleteTeam(team);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final team = _team;

    return Scaffold(
      appBar: AppBar(
        title: Text(team?.name ?? 'Team'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: () => _save(state),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'delete') _deleteTeam(state);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        tooltip: 'Add member',
        onPressed: () => _addMember(state),
        child: const Icon(Icons.person_add_alt),
      ),
      body: team == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                TextField(
                  controller: _name,
                  style: TextStyle(
                    fontSize: TodoText.xxl,
                    fontWeight: FontWeight.w600,
                    color: c.primaryText,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: InputBorder.none,
                  ),
                ),
                TextField(
                  controller: _description,
                  maxLines: null,
                  style: TextStyle(
                    fontSize: TodoText.medium,
                    color: c.secondaryText,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                Divider(color: c.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                  child: Text(
                    'Members',
                    style: TextStyle(
                      fontSize: TodoText.small,
                      fontWeight: FontWeight.w600,
                      color: c.secondaryText,
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: c.overdue,
                        fontSize: TodoText.medium,
                      ),
                    ),
                  )
                else if (_members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No members yet',
                      style: TextStyle(
                        color: c.secondaryText,
                        fontSize: TodoText.medium,
                      ),
                    ),
                  ),
                for (final member in _members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: c.accent,
                      child: Text(
                        member.initials,
                        style: TextStyle(fontSize: 12, color: c.onAccent),
                      ),
                    ),
                    title: Text(
                      member.displayName,
                      style: TextStyle(
                        fontSize: TodoText.big,
                        color: c.primaryText,
                      ),
                    ),
                    subtitle: member.username.isEmpty
                        ? null
                        : Text(
                            '@${member.username}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.secondaryText,
                            ),
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            // Vikunja lets the last admin demote themselves,
                            // which locks everyone out of team management.
                            final admins = _members
                                .where((m) => m.admin)
                                .length;
                            if (member.admin && admins <= 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'A team needs at least one admin. '
                                    'Promote someone else first.',
                                  ),
                                ),
                              );
                              return;
                            }
                            await state.toggleTeamMemberAdmin(
                              widget.teamId,
                              member.username,
                            );
                            await _load();
                          },
                          child: Text(
                            member.admin ? 'Admin' : 'Member',
                            style: TextStyle(
                              color: member.admin ? c.accent : c.secondaryText,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove from team',
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: c.secondaryText,
                          ),
                          onPressed: () async {
                            final error = await state.removeTeamMember(
                              widget.teamId,
                              member.username,
                            );
                            if (!mounted) return;
                            if (error != null) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(error)));
                            }
                            await _load();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// User picker backed by `GET /users?s=`.
Future<VikunjaUser?> showUserSearch(BuildContext context, AppState state) {
  return showModalBottomSheet<VikunjaUser>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _UserSearchSheet(),
  );
}

class _UserSearchSheet extends StatefulWidget {
  const _UserSearchSheet();

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final _controller = TextEditingController();
  List<VikunjaUser> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    final state = AppScope.of(context);
    try {
      final results = await state.searchUsers(query.trim());
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Search users',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _search(_controller.text),
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, style: TextStyle(color: c.overdue)),
                    ),
                  if (!_searching && _results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _controller.text.isEmpty
                            ? 'Type a name or username to search.'
                            : 'No users found. Vikunja only lists users who '
                                  'enabled "Discoverable by name" in their '
                                  'settings.',
                        style: TextStyle(color: c.secondaryText),
                      ),
                    ),
                  for (final user in _results)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: c.accent,
                        child: Text(
                          (user.name?.isNotEmpty == true
                                  ? user.name!
                                  : user.username)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: TextStyle(fontSize: 12, color: c.onAccent),
                        ),
                      ),
                      title: Text(
                        user.name?.isNotEmpty == true
                            ? user.name!
                            : user.username,
                      ),
                      subtitle: Text(
                        '@${user.username}',
                        style: TextStyle(fontSize: 12, color: c.secondaryText),
                      ),
                      onTap: () => Navigator.pop(context, user),
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
