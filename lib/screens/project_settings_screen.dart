import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';
import '../widgets/unsaved_changes.dart';
import 'team_detail_screen.dart';

/// Vikunja project management: details, colour, favorite/archive, sharing with
/// users, teams and link shares, and deletion.
class ProjectSettingsScreen extends StatefulWidget {
  const ProjectSettingsScreen({super.key, required this.project});

  final VikunjaProject project;

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _identifier = TextEditingController();
  String _hexColor = '';
  bool _favorite = false;
  bool _archived = false;

  bool _loading = true;

  /// Whether the name or the description differs from the saved project; the
  /// back guard follows this.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _title.text = p.title;
    _description.text = p.description ?? '';
    // Vikunja clears the identifier when the field is missing from the update
    // body, so the screen always sends what the field holds — which means the
    // field has to start out with the saved value, not empty.
    _identifier.text = p.identifier ?? '';
    _hexColor = p.hexColor;
    _favorite = p.isFavorite;
    _archived = p.isArchived;
    _title.addListener(_syncDirty);
    _description.addListener(_syncDirty);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _syncDirty() {
    final dirty =
        _title.text.trim() != widget.project.title ||
        _description.text.trim() != (widget.project.description ?? '');
    if (dirty == _dirty) return;
    if (mounted) {
      setState(() => _dirty = dirty);
    } else {
      _dirty = dirty;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _identifier.dispose();
    super.dispose();
  }

  /// The shares live in [AppState]; the screen only asks for a fresh read.
  Future<void> _load() async {
    if (!mounted) return;
    final error = await AppScope.of(context).projectShares(widget.project.id);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _save(AppState state, {String? identifier}) async {
    final error = await state.saveProject(
      widget.project,
      title: _title.text.trim(),
      description: _description.text.trim(),
      hexColor: _hexColor,
      identifier:
          identifier ?? (_identifier.text.trim().isEmpty
              ? ''
              : _identifier.text.trim()),
      isFavorite: _favorite,
      isArchived: _archived,
    );
    if (mounted) {
      // The save reports its own failure now, so the snackbar no longer reads
      // the shared `state.error` (which the poller also writes).
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error ?? 'Project saved')));
      _syncDirty();
    }
  }

  Future<void> _addUser(AppState state) async {
    final user = await showUserSearch(context, state);
    if (user == null) return;
    if (!mounted) return;
    final permission = await _pickPermission(context, 1);
    if (permission == null) return;
    final error = await state.shareWithUser(
      widget.project.id,
      user.username,
      permission,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    await _load();
  }

  Future<void> _addTeam(AppState state) async {
    if (state.teams.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Create a team first')));
      return;
    }
    final team = await showModalBottomSheet<VikunjaTeam>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Share with team',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final t in state.teams)
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(t.name),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (team == null || !mounted) return;
    if (!mounted) return;
    final permission = await _pickPermission(context, 1);
    if (permission == null) return;
    final error = await state.shareWithTeam(
      widget.project.id,
      team.id,
      permission,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    await _load();
  }

  Future<void> _createLink(AppState state) async {
    final draft = await showDialog<({String name, String password})>(
      context: context,
      builder: (_) => const _CreateLinkDialog(),
    );
    if (draft == null || !mounted) return;
    final permission = await _pickPermission(context, 0);
    if (permission == null) return;
    final error = await state.createLinkShare(
      widget.project.id,
      draft.name.isEmpty ? 'Shared link' : draft.name,
      permission,
      password: draft.password,
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    await _load();
  }

  Future<void> _delete(AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${widget.project.title}"?'),
        content: const Text(
          'Are you sure you want to delete this project and all of '
          'its contents? This includes all tasks and CANNOT BE UNDONE!',
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
    if (confirmed != true) return;
    final error = await state.deleteProject(widget.project);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _setUserShare(
    AppState state,
    VikunjaProjectShare share,
    int permission,
  ) async {
    // A share the server sent without a username cannot be addressed.
    final username = share.username;
    if (username == null || username.isEmpty) return;
    await state.setUserShare(widget.project.id, username, permission);
    await _load();
  }

  Future<void> _removeUserShare(
    AppState state,
    VikunjaProjectShare share,
  ) async {
    final username = share.username;
    if (username == null || username.isEmpty) return;
    await state.unshareUser(widget.project.id, username);
    await _load();
  }

  Future<void> _setTeamShare(
    AppState state,
    VikunjaProjectShare share,
    int permission,
  ) async {
    final teamId = share.teamId;
    if (teamId == null) return;
    await state.setTeamShare(widget.project.id, teamId, permission);
    await _load();
  }

  Future<void> _removeTeamShare(
    AppState state,
    VikunjaProjectShare share,
  ) async {
    final teamId = share.teamId;
    if (teamId == null) return;
    await state.unshareTeam(widget.project.id, teamId);
    await _load();
  }

  Future<void> _deleteLink(AppState state, VikunjaLinkShare link) async {
    final error = await state.deleteLinkShare(widget.project.id, link.id);
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
    final shares = state.sharesOf(widget.project.id);

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Project'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: () => _save(state),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'delete') _delete(state);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          _ProjectFields(
            title: _title,
            description: _description,
            identifier: _identifier,
          ),
          _ColourPicker(
            hexColor: _hexColor,
            onSelected: (swatch) =>
                setState(() => _hexColor = TodoColors.toHex(swatch)),
          ),
          const SizedBox(height: 8),
          _ToggleRows(
            favorite: _favorite,
            archived: _archived,
            onFavorite: (v) {
              setState(() => _favorite = v);
              _save(state);
            },
            onArchived: (v) {
              setState(() => _archived = v);
              _save(state);
            },
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          _ShareSection(
            label: 'Share with users',
            action: 'Add user',
            onAction: () => _addUser(state),
            icon: Icons.person_outline,
            shares: shares.users,
            emptyText: 'Not shared with anyone yet',
            onPermission: (share, permission) =>
                _setUserShare(state, share, permission),
            onRemove: (share) => _removeUserShare(state, share),
          ),
          _ShareSection(
            label: 'Share with teams',
            action: 'Add team',
            onAction: () => _addTeam(state),
            icon: Icons.groups_outlined,
            shares: shares.teams,
            emptyText: 'Not shared with any team',
            onPermission: (share, permission) =>
                _setTeamShare(state, share, permission),
            onRemove: (share) => _removeTeamShare(state, share),
          ),
          _LinkShares(
            links: shares.links,
            frontendUrl: shares.frontendUrl ?? state.baseUrl ?? '',
            onCreate: () => _createLink(state),
            onDelete: (link) => _deleteLink(state, link),
          ),
        ],
      ),
    );
    // The name and the description only reach the server on Save; leaving
    // without one would drop them.
    return UnsavedChangesGuard(
      dirty: _dirty,
      message: 'Your changes to this project have not been saved yet.',
      child: scaffold,
    );
  }
}

/// Title, description and identifier inputs; their controllers live on the
/// screen so a save reads them at any time.
class _ProjectFields extends StatelessWidget {
  const _ProjectFields({
    required this.title,
    required this.description,
    required this.identifier,
  });

  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController identifier;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: title,
          style: TextStyle(
            fontSize: TodoText.xxl,
            fontWeight: FontWeight.w600,
            color: c.primaryText,
          ),
          decoration: const InputDecoration(
            labelText: 'Title',
            border: InputBorder.none,
          ),
        ),
        TextField(
          controller: description,
          maxLines: null,
          style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText),
          decoration: const InputDecoration(
            labelText: 'Description',
            border: InputBorder.none,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: identifier,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Project Identifier',
            helperText:
                'Identifies tasks across projects; leave empty to disable.',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// The server colour swatches; the selected one gets a ring.
class _ColourPicker extends StatelessWidget {
  const _ColourPicker({required this.hexColor, required this.onSelected});

  final String hexColor;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Colour',
          style: TextStyle(fontSize: TodoText.small, color: c.secondaryText),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final swatch in TodoColors.swatches(c))
              GestureDetector(
                onTap: () => onSelected(swatch),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          TodoColors.toHex(swatch).toUpperCase() ==
                              hexColor.toUpperCase()
                          ? c.primaryText
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Favorite and archive switches; both save immediately.
class _ToggleRows extends StatelessWidget {
  const _ToggleRows({
    required this.favorite,
    required this.archived,
    required this.onFavorite,
    required this.onArchived,
  });

  final bool favorite;
  final bool archived;
  final ValueChanged<bool> onFavorite;
  final ValueChanged<bool> onArchived;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: favorite,
          activeThumbColor: c.accent,
          title: Text('Favorite', style: TextStyle(color: c.primaryText)),
          onChanged: onFavorite,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: archived,
          activeThumbColor: c.accent,
          title: Text(
            'Archive this project',
            style: TextStyle(color: c.primaryText),
          ),
          subtitle: Text(
            'Archived projects cannot be edited or receive new tasks.',
            style: TextStyle(fontSize: 12, color: c.secondaryText),
          ),
          onChanged: onArchived,
        ),
      ],
    );
  }
}

/// One share list: a header with its add action, then a row per share.
class _ShareSection extends StatelessWidget {
  const _ShareSection({
    required this.label,
    required this.action,
    required this.onAction,
    required this.icon,
    required this.shares,
    required this.emptyText,
    required this.onPermission,
    required this.onRemove,
  });

  final String label;
  final String action;
  final VoidCallback onAction;
  final IconData icon;
  final List<VikunjaProjectShare> shares;
  final String emptyText;
  final void Function(VikunjaProjectShare share, int permission) onPermission;
  final ValueChanged<VikunjaProjectShare> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: label, action: action, onAction: onAction),
        if (shares.isEmpty) _EmptyRow(text: emptyText),
        for (final share in shares)
          _ShareRow(
            leading: icon,
            name: share.displayName,
            permission: share.permission,
            onPermission: (permission) => onPermission(share, permission),
            onRemove: () => onRemove(share),
          ),
      ],
    );
  }
}

/// Link shares with copy and delete actions.
class _LinkShares extends StatelessWidget {
  const _LinkShares({
    required this.links,
    required this.frontendUrl,
    required this.onCreate,
    required this.onDelete,
  });

  final List<VikunjaLinkShare> links;
  final String frontendUrl;
  final VoidCallback onCreate;
  final ValueChanged<VikunjaLinkShare> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final prefix = frontendUrl.endsWith('/') ? frontendUrl : '$frontendUrl/';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: 'Link shares',
          action: 'Create link share',
          onAction: onCreate,
        ),
        if (links.isEmpty) const _EmptyRow(text: 'No link shares'),
        for (final link in links)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link, color: c.accent),
            title: Text(link.name, style: TextStyle(color: c.primaryText)),
            subtitle: Text(
              '${permissionLabel(link.permission)} link'
              '${link.hasPassword ? " · password protected" : ""}',
              style: TextStyle(fontSize: 12, color: c.secondaryText),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy link',
                  icon: Icon(Icons.copy, size: 18, color: c.secondaryText),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: '${prefix}share/${link.hash}/auth'),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Delete link share',
                  icon: Icon(Icons.close, size: 18, color: c.secondaryText),
                  onPressed: () => onDelete(link),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: TodoText.medium,
          color: TodoColors.of(context).secondaryText,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.action,
    required this.onAction,
  });

  final String label;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
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
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.leading,
    required this.name,
    required this.permission,
    required this.onPermission,
    required this.onRemove,
  });

  final IconData leading;
  final String name;
  final int permission;
  final ValueChanged<int> onPermission;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(leading, color: c.accent),
      title: Text(name, style: TextStyle(color: c.primaryText)),
      subtitle: Text(
        permissionLabel(permission),
        style: TextStyle(fontSize: 12, color: c.secondaryText),
      ),
      onTap: () async {
        final picked = await _pickPermission(context, permission);
        if (picked != null) onPermission(picked);
      },
      trailing: IconButton(
        tooltip: 'Remove',
        icon: Icon(Icons.close, size: 18, color: c.secondaryText),
        onPressed: onRemove,
      ),
    );
  }
}

Future<int?> _pickPermission(BuildContext context, int current) {
  final c = TodoColors.of(context);
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Permission',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          for (var permission = 0; permission <= 2; permission++)
            ListTile(
              title: Text(permissionLabel(permission)),
              trailing: permission == current
                  ? Icon(Icons.check, size: 20, color: c.accent)
                  : null,
              onTap: () => Navigator.pop(context, permission),
            ),
        ],
      ),
    ),
  );
}

/// New link share form. Owns its controllers so they die with the dialog.
class _CreateLinkDialog extends StatefulWidget {
  const _CreateLinkDialog();

  @override
  State<_CreateLinkDialog> createState() => _CreateLinkDialogState();
}

class _CreateLinkDialogState extends State<_CreateLinkDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New link share'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              helperText: 'Optional — visitors must enter it to open the link.',
            ),
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
            password: _password.text.trim(),
          )),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
