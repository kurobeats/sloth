import 'package:flutter/material.dart';

import '../state.dart';
import '../todo_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {state.themeMode},
              onSelectionChanged: (selection) =>
                  state.setThemeMode(selection.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: c.primaryBackground,
                foregroundColor: c.primaryText,
                selectedBackgroundColor: c.accent,
                selectedForegroundColor: c.onAccent,
                side: BorderSide(color: c.divider),
              ),
            ),
          ),
          _Section(
            title: 'Dark theme',
            subtitle: state.darkTheme.id == TodoColors.defaultDark.id
                ? 'Default'
                : null,
            themes: TodoColors.darkThemes,
            selectedId: state.darkThemeId,
            onSelected: state.setDarkTheme,
          ),
          _Section(
            title: 'Light theme',
            subtitle: state.lightTheme.id == TodoColors.defaultLight.id
                ? 'Default'
                : null,
            themes: TodoColors.lightThemes,
            selectedId: state.lightThemeId,
            onSelected: state.setLightTheme,
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Colour schemes from Gogh (gogh.website), a collection of terminal '
              'themes by their respective authors, MIT / Apache-2.0 licensed. '
              'Accent and muted tones are contrast-adjusted here so icons and '
              'small text stay legible on screen.',
              style: TextStyle(fontSize: 11, height: 1.4, color: c.secondaryText),
            ),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: c.secondaryText),
            title: Text('Logout', style: TextStyle(color: c.primaryText)),
            subtitle: Text(
              state.baseUrl ?? '',
              style: TextStyle(fontSize: 12, color: c.secondaryText),
            ),
            onTap: () async {
              await state.signOut();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.themes,
    required this.selectedId,
    required this.onSelected,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<TodoColors> themes;
  final String selectedId;
  final Future<void> Function(String id) onSelected;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: TodoText.small,
                  fontWeight: FontWeight.w600,
                  color: c.secondaryText,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    subtitle!,
                    style: TextStyle(fontSize: 10, color: c.accent),
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final theme in themes)
          _ThemeRow(
            theme: theme,
            selected: theme.id == selectedId,
            onTap: () => onSelected(theme.id),
          ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final TodoColors theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _Swatch(theme: theme),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    style: TextStyle(
                      fontSize: TodoText.big,
                      color: selected ? c.accent : c.primaryText,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    theme.author,
                    style: TextStyle(fontSize: 11, color: c.secondaryText),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 20, color: c.accent),
          ],
        ),
      ),
    );
  }
}

/// A miniature of the scheme: background chip with its accent and text colours.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme});

  final TodoColors theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 32,
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.primaryText.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: theme.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
              color: theme.primaryText,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
