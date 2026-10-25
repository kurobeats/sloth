import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The chosen appearance is a device preference, not session state: logging out
/// or letting a token expire must not throw it away, and neither must the next
/// launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chosen = {
    'theme_light': 'patina-light',
    'theme_dark': 'panda',
    'theme_mode': 'dark',
    'vikunja_base': 'https://tasks.example.com',
    'vikunja_token': 'expired-token',
    'vikunja_allow_self_signed': 'true',
  };

  void setPrefs() => FlutterSecureStorage.setMockInitialValues(
    Map<String, String>.from(chosen),
  );

  setUp(setPrefs);

  test('the theme survives a logout in memory', () async {
    final state = AppState();
    await state.loadAppearance();
    expect(state.lightTheme.id, 'patina-light');
    expect(state.darkTheme.id, 'panda');
    expect(state.themeMode, ThemeMode.dark);

    await state.signOut();

    expect(state.lightTheme.id, 'patina-light', reason: 'still painted');
    expect(state.darkTheme.id, 'panda');
    expect(state.themeMode, ThemeMode.dark);
  });

  test('the theme survives a logout on disk', () async {
    final state = AppState();
    await state.loadAppearance();
    await state.signOut();

    final fresh = AppState();
    await fresh.loadAppearance();

    expect(fresh.lightTheme.id, 'patina-light');
    expect(fresh.darkTheme.id, 'panda');
    expect(fresh.themeMode, ThemeMode.dark);
  });

  test('a logout keeps the per-server certificate trust', () async {
    final state = AppState();
    await state.loadAppearance();
    await state.signOut();

    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'vikunja_allow_self_signed'), 'true');
    expect(
      await storage.read(key: 'vikunja_token'),
      isNull,
      reason: 'token gone',
    );
    expect(state.allowSelfSigned, isTrue, reason: 'login prefills the box');
  });

  test('changing the theme writes it for the next launch', () async {
    final state = AppState();
    await state.loadAppearance();
    await state.setDarkTheme(TodoColors.catppuccinMocha.id);
    await state.setThemeMode(ThemeMode.system);

    final fresh = AppState();
    await fresh.loadAppearance();
    expect(fresh.darkTheme.id, 'catppuccin-mocha');
    expect(fresh.themeMode, ThemeMode.system);
  });
}
