import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';
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

  List<VikunjaProjectShare> _userShares = const [];
  List<VikunjaProjectShare> _teamShares = const [];
  List<VikunjaLinkShare> _links = const [];
  String? _frontendUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _title.text = p.title;
    _description.text = p.description ?? '';
    _hexColor = p.hexColor;
    _favorite = p.isFavorite;
    _archived = p.isArchived;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _identifier.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    final api = state.api;
    if (api == null) return;
    final id = widget.project.id;
    try {
      final results = await Future.wait([
        api.projectUsers(id),
        api.projectTeams(id),
        api.linkShares(id),
        api.frontendUrl(),
      ]);
      if (!mounted) return;
      setState(() {
        _userShares = results[0] as List<VikunjaProjectShare>;
        _teamShares = results[1] as List<VikunjaProjectShare>;
        _links = results[2] as List<VikunjaLinkShare>;
        _frontendUrl = results[3] as String?;
        _loading = false;
      });
    } on VikunjaException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _save(AppState state, {String? identifier}) async {
    await state.saveProject(
      widget.project,
      title: _title.text.trim(),
      description: _description.text.trim(),
      hexColor: _hexColor,
      identifier: identifier ?? (_identifier.text.trim().isEmpty ? null : _identifier.text.trim()),
      isFavorite: _favorite,
      isArchived: _archived,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Project saved')));
    }
  }

  Future<void> _addUser(AppState state) async {
    final user = await showUserSearch(context, state);
    if (user == null) return;
    if (!mounted) return;
    final permission = await _pickPermission(context, 1);
    if (permission == null) return;
    final error = await state.shareWithUser(widget.project.id, user.id, permission);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
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
              child: Text('Share with team',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    final error = await state.shareWithTeam(widget.project.id, team.id, permission);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
    await _load();
  }

  Future<void> _createLink(AppState state) async {
    final name = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New link share'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (created != true || !mounted) return;
    final permission = await _pickPermission(context, 0);
    if (permission == null) return;
    try {
      await state.api?.createLinkShare(widget.project.id,
          name: name.text.trim().isEmpty ? 'Shared link' : name.text.trim(),
          permission: permission);
    } on VikunjaException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);

    return Scaffold(
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
            onSelected: (value) async {
              if (value == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Delete "${widget.project.title}"?'),
                    content: const Text(
                      'Are you sure you want to delete this project and all of '
                      'its contents? This includes all tasks and CANNOT BE UNDONE!',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirmed != true) return;
                final error = await state.deleteProject(widget.project);
                if (!context.mounted) return;
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                } else {
                  Navigator.of(context).pop();
                }
              }
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
          TextField(
            controller: _title,
            style: TextStyle(
                fontSize: TodoText.xxl, fontWeight: FontWeight.w600, color: c.primaryText),
            decoration: const InputDecoration(labelText: 'Title', border: InputBorder.none),
          ),
          TextField(
            controller: _description,
            maxLines: null,
            style: TextStyle(fontSize: TodoText.medium, color: c.secondaryText),
            decoration: const InputDecoration(labelText: 'Description', border: InputBorder.none),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _identifier,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Project Identifier',
              helperText: 'Identifies tasks across projects; leave empty to disable.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Colour',
              style: TextStyle(fontSize: TodoText.small, color: c.secondaryText)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in TodoColors.swatches(c))
                GestureDetector(
                  onTap: () => setState(() => _hexColor = _toHex(swatch)),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _toHex(swatch).toUpperCase() == _hexColor.toUpperCase()
                            ? c.primaryText
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _favorite,
            activeThumbColor: c.accent,
            title: Text('Favorite', style: TextStyle(color: c.primaryText)),
            onChanged: (v) {
              setState(() => _favorite = v);
              _save(state);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _archived,
            activeThumbColor: c.accent,
            title: Text('Archive this project', style: TextStyle(color: c.primaryText)),
            subtitle: Text(
              'Archived projects cannot be edited or receive new tasks.',
              style: TextStyle(fontSize: 12, color: c.secondaryText),
            ),
            onChanged: (v) {
              setState(() => _archived = v);
              _save(state);
            },
          ),
          const SizedBox(height: 8),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          _SectionHeader(
            label: 'Share with users',
            action: 'Add user',
            onAction: () => _addUser(state),
          ),
          if (_userShares.isEmpty) _emptyRow('Not shared with anyone yet'),
          for (final share in _userShares)
            _ShareRow(
              leading: Icons.person_outline,
              name: share.displayName,
              permission: share.permission,
              onPermission: (permission) async {
                await state.setUserShare(widget.project.id, share.userId!, permission);
                await _load();
              },
              onRemove: () async {
                await state.unshareUser(widget.project.id, share.userId!);
                await _load();
              },
            ),
          _SectionHeader(
            label: 'Share with teams',
            action: 'Add team',
            onAction: () => _addTeam(state),
          ),
          if (_teamShares.isEmpty) _emptyRow('Not shared with any team'),
          for (final share in _teamShares)
            _ShareRow(
              leading: Icons.groups_outlined,
              name: share.displayName,
              permission: share.permission,
              onPermission: (permission) async {
                await state.setTeamShare(widget.project.id, share.teamId!, permission);
                await _load();
              },
              onRemove: () async {
                await state.unshareTeam(widget.project.id, share.teamId!);
                await _load();
              },
            ),
          _SectionHeader(
            label: 'Link shares',
            action: 'Create link share',
            onAction: () => _createLink(state),
          ),
          if (_links.isEmpty) _emptyRow('No link shares'),
          for (final link in _links)
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
                      final base = _frontendUrl ?? state.baseUrl ?? '';
                      final prefix = base.endsWith('/') ? base : '$base/';
                      await Clipboard.setData(
                        ClipboardData(text: '${prefix}share/${link.hash}/auth'),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Link copied')));
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Delete link share',
                    icon: Icon(Icons.close, size: 18, color: c.secondaryText),
                    onPressed: () async {
                      await state.api?.deleteLinkShare(widget.project.id, link.id);
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

  static String _toHex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Widget _emptyRow(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: TodoText.medium, color: TodoColors.of(context).secondaryText)),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.action, required this.onAction});

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
      subtitle: Text(permissionLabel(permission),
          style: TextStyle(fontSize: 12, color: c.secondaryText)),
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
            child: Text('Permission',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (var permission = 0; permission <= 2; permission++)
            ListTile(
              title: Text(permissionLabel(permission)),
              trailing: permission == current ? Icon(Icons.check, size: 20, color: c.accent) : null,
              onTap: () => Navigator.pop(context, permission),
            ),
        ],
      ),
    ),
  );
}
