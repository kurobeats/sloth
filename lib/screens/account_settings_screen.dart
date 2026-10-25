import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';

/// Vikunja general user settings (`POST /user/settings/general`).
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  // Languages Vikunja ships translations for (frontend/src/i18n/lang).
  static const _languages = [
    ('en', 'English'),
    ('de', 'Deutsch'),
    ('es', 'Español'),
    ('fr', 'Français'),
    ('it', 'Italiano'),
    ('nl', 'Nederlands'),
    ('pl', 'Polski'),
    ('pt', 'Português'),
    ('ru', 'Русский'),
    ('sv', 'Svenska'),
    ('tr', 'Türkçe'),
    ('uk', 'Українська'),
    ('zh-hans', '简体中文'),
    ('ja', '日本語'),
  ];

  final _name = TextEditingController();
  final _timezone = TextEditingController();
  VikunjaUserSettings _settings = const VikunjaUserSettings();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Inherited lookups are not allowed before the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final current = AppScope.of(context).userSettings;
    setState(() {
      _settings = current;
      _name.text = current.name;
      _timezone.text = current.timezone;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.of(context);
    setState(() => _saving = true);
    final updated = _settings.copyWith(
      name: _name.text.trim(),
      timezone: _timezone.text.trim().isEmpty ? 'GMT' : _timezone.text.trim(),
    );
    final error = await state.saveUserSettings(updated);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) _settings = state.userSettings;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? 'Settings saved')));
  }

  Future<void> _pickReminderTime() async {
    final parts = _settings.overdueRemindersTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(
      () => _settings = _settings.copyWith(
        overdueRemindersTime:
            '${picked.hour}:${picked.minute.toString().padLeft(2, '0')}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    final projects = state.writableProjects;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      // Edge-to-edge: the form must stop above the gesture bar.
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _languages.any((l) => l.$1 == _settings.language)
                  ? _settings.language
                  : 'en',
              decoration: const InputDecoration(
                labelText: 'Language',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final (code, label) in _languages)
                  DropdownMenuItem(value: code, child: Text(label)),
              ],
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(language: value ?? 'en'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _timezone,
              decoration: const InputDecoration(
                labelText: 'Timezone',
                helperText: 'IANA name, e.g. Australia/Sydney or GMT',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue:
                  projects.any((p) => p.id == _settings.defaultProjectId)
                  ? _settings.defaultProjectId
                  : 0,
              decoration: const InputDecoration(
                labelText: 'Default project',
                helperText: 'New tasks from quick add land here',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: 0, child: Text('None')),
                for (final project in projects)
                  DropdownMenuItem(
                    value: project.id,
                    child: Text(project.title),
                  ),
              ],
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(
                  defaultProjectId: value ?? 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _SettingsSection(
              divided: true,
              children: [
                _SwitchRow(
                  title: 'Week starts on Monday',
                  value: _settings.weekStart == 1,
                  onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(weekStart: v ? 1 : 0),
                  ),
                ),
              ],
            ),
            _SettingsSection(
              divided: true,
              children: [
                _SwitchRow(
                  title: 'Discoverable by name',
                  value: _settings.discoverableByName,
                  onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(discoverableByName: v),
                  ),
                ),
                _SwitchRow(
                  title: 'Discoverable by email',
                  value: _settings.discoverableByEmail,
                  onChanged: (v) => setState(
                    () =>
                        _settings = _settings.copyWith(discoverableByEmail: v),
                  ),
                ),
              ],
            ),
            _SettingsSection(
              children: [
                _SwitchRow(
                  title: 'Email reminders',
                  value: _settings.emailRemindersEnabled,
                  onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(
                      emailRemindersEnabled: v,
                    ),
                  ),
                ),
                _SwitchRow(
                  title: 'Overdue task reminders',
                  value: _settings.overdueRemindersEnabled,
                  onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(
                      overdueRemindersEnabled: v,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Reminder time',
                    style: TextStyle(color: c.primaryText),
                  ),
                  subtitle: Text(
                    _settings.overdueRemindersTime,
                    style: TextStyle(fontSize: 12, color: c.secondaryText),
                  ),
                  trailing: Icon(Icons.access_time, color: c.secondaryText),
                  onTap: _pickReminderTime,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Account: ${state.user?.username ?? ''}'
              '${state.user?.isAdmin == true ? " · administrator" : ""}',
              style: TextStyle(fontSize: 12, color: c.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// A group of rows, optionally closed by the divider that separates sections.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children, this.divided = false});

  final List<Widget> children;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        if (divided) Divider(color: c.divider, height: 24),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      activeThumbColor: c.accent,
      title: Text(title, style: TextStyle(color: c.primaryText)),
      onChanged: onChanged,
    );
  }
}
