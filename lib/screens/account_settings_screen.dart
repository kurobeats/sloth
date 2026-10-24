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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Settings saved')),
    );
  }

  Future<void> _pickReminderTime() async {
    final parts = _settings.overdueRemindersTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() => _settings = _settings.copyWith(
          overdueRemindersTime: '${picked.hour}:${picked.minute.toString().padLeft(2, '0')}',
        ));
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
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
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
                () => _settings = _settings.copyWith(language: value ?? 'en')),
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
            initialValue: projects.any((p) => p.id == _settings.defaultProjectId)
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
                DropdownMenuItem(value: project.id, child: Text(project.title)),
            ],
            onChanged: (value) => setState(() =>
                _settings = _settings.copyWith(defaultProjectId: value ?? 0)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.weekStart == 1,
            activeThumbColor: c.accent,
            title: Text('Week starts on Monday',
                style: TextStyle(color: c.primaryText)),
            onChanged: (v) => setState(
                () => _settings = _settings.copyWith(weekStart: v ? 1 : 0)),
          ),
          Divider(color: c.divider, height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.discoverableByName,
            activeThumbColor: c.accent,
            title: Text('Discoverable by name',
                style: TextStyle(color: c.primaryText)),
            onChanged: (v) => setState(
                () => _settings = _settings.copyWith(discoverableByName: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.discoverableByEmail,
            activeThumbColor: c.accent,
            title: Text('Discoverable by email',
                style: TextStyle(color: c.primaryText)),
            onChanged: (v) => setState(
                () => _settings = _settings.copyWith(discoverableByEmail: v)),
          ),
          Divider(color: c.divider, height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.emailRemindersEnabled,
            activeThumbColor: c.accent,
            title: Text('Email reminders',
                style: TextStyle(color: c.primaryText)),
            onChanged: (v) => setState(
                () => _settings = _settings.copyWith(emailRemindersEnabled: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.overdueRemindersEnabled,
            activeThumbColor: c.accent,
            title: Text('Overdue task reminders',
                style: TextStyle(color: c.primaryText)),
            onChanged: (v) => setState(() =>
                _settings = _settings.copyWith(overdueRemindersEnabled: v)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Reminder time', style: TextStyle(color: c.primaryText)),
            subtitle: Text(_settings.overdueRemindersTime,
                style: TextStyle(fontSize: 12, color: c.secondaryText)),
            trailing: Icon(Icons.access_time, color: c.secondaryText),
            onTap: _pickReminderTime,
          ),
          const SizedBox(height: 16),
          Text(
            'Account: ${state.user?.username ?? ''}'
            '${state.user?.isAdmin == true ? " · administrator" : ""}',
            style: TextStyle(fontSize: 12, color: c.secondaryText),
          ),
        ],
      ),
    );
  }
}
