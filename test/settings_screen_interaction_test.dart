import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/screens/settings_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The appearance screen writes its choices to the keychain, so the secure
/// store is mocked the same way `theme_persistence_test.dart` does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Widget host(AppState state) => AppScope(
    state: state,
    child: MaterialApp(
      theme: buildTodoTheme(TodoColors.gruvboxLight),
      home: const SettingsScreen(),
    ),
  );

  /// The tick that marks the selected scheme inside [name]'s row, so a moved
  /// selection is visible and not just a field on the state.
  Finder tickIn(String name) => find.descendant(
    of: find
        .ancestor(of: find.text(name), matching: find.byType(InkWell))
        .first,
    matching: find.byIcon(Icons.check),
  );

  testWidgets('tapping a light scheme selects and marks it', (tester) async {
    final state = AppState();
    await tester.pumpWidget(host(state));
    expect(state.lightThemeId, TodoColors.defaultLight.id);
    expect(tickIn('Gruvbox Light'), findsOneWidget);

    await tester.tap(find.text('Patina Light'));
    await tester.pumpAndSettle();

    expect(state.lightThemeId, 'patina-light');
    expect(tickIn('Patina Light'), findsOneWidget);
    expect(tickIn('Gruvbox Light'), findsNothing, reason: 'the tick moved');
    expect(
      state.darkThemeId,
      TodoColors.defaultDark.id,
      reason: 'the dark choice is untouched',
    );
  });

  testWidgets('tapping a dark scheme selects and marks it', (tester) async {
    final state = AppState();
    await tester.pumpWidget(host(state));
    expect(tickIn('Oceanic Next'), findsOneWidget);

    await tester.tap(find.text('Catppuccin Mocha'));
    await tester.pumpAndSettle();

    expect(state.darkThemeId, 'catppuccin-mocha');
    expect(tickIn('Catppuccin Mocha'), findsOneWidget);
    expect(tickIn('Oceanic Next'), findsNothing);
    expect(
      state.lightThemeId,
      TodoColors.defaultLight.id,
      reason: 'picking a dark scheme does not move the light one',
    );
  });

  testWidgets('the mode buttons switch system, light and dark', (tester) async {
    final state = AppState();
    await tester.pumpWidget(host(state));
    expect(state.themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.light);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.system);
  });
}
