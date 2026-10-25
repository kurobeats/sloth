import 'package:flutter/material.dart';

import '../state.dart';
import '../todo_theme.dart';
import 'team_detail_screen.dart';

/// Vikunja teams: groups of users a project can be shared with.
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        tooltip: 'New team',
        onPressed: () => _createTeam(context, state),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: state.reloadTeams,
          child: state.teams.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: 56,
                      color: c.secondaryText,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No teams yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TodoText.xl,
                        color: c.primaryText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Teams group users so a project can be shared with all of them at once.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TodoText.medium,
                        color: c.secondaryText,
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: state.teams.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: c.divider),
                  itemBuilder: (context, i) {
                    final team = state.teams[i];
                    return ListTile(
                      leading: Icon(Icons.groups_outlined, color: c.accent),
                      title: Text(
                        team.name,
                        style: TextStyle(color: c.primaryText),
                      ),
                      subtitle: Text(
                        team.members.isEmpty
                            ? 'No members'
                            : '${team.members.length} '
                                  '${team.members.length == 1 ? "member" : "members"}',
                        style: TextStyle(fontSize: 12, color: c.secondaryText),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: c.secondaryText,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeamDetailScreen(teamId: team.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _createTeam(BuildContext context, AppState state) async {
    final draft = await showDialog<({String name, String description})>(
      context: context,
      builder: (_) => const _CreateTeamDialog(),
    );
    if (draft == null) return;
    final error = await state.createTeam(
      draft.name,
      description: draft.description.isEmpty ? null : draft.description,
    );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// New team form. Owns its controllers so they die with the dialog.
class _CreateTeamDialog extends StatefulWidget {
  const _CreateTeamDialog();

  @override
  State<_CreateTeamDialog> createState() => _CreateTeamDialogState();
}

class _CreateTeamDialogState extends State<_CreateTeamDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New team'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, (
            name: _name.text.trim(),
            description: _description.text.trim(),
          )),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
