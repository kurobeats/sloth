import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/screens/login_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The login button must follow the chosen scheme like every other control:
/// one accent per theme, no second hardcoded call-to-action colour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Color?> loginButtonColour(WidgetTester tester, String id) async {
    FlutterSecureStorage.setMockInitialValues({
      'theme_dark': id,
      'theme_light': id,
      'theme_mode': 'dark',
    });
    final state = AppState();
    await state.loadAppearance();
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTodoTheme(state.darkTheme),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    return button.style?.backgroundColor?.resolve(<WidgetState>{});
  }

  testWidgets('each theme paints the login button with its own accent', (
    tester,
  ) async {
    final seen = <Color>{};
    for (final id in ['oceanic-next', 'panda', 'catppuccin-mocha']) {
      final colour = await loginButtonColour(tester, id);
      expect(colour, TodoColors.byId(id, Brightness.dark).accent, reason: id);
      seen.add(colour!);
    }
    expect(seen, hasLength(3), reason: 'three themes, three accents');
  });

  testWidgets('the light schemes are used too', (tester) async {
    for (final id in ['gruvbox-light', 'patina-light']) {
      final colour = await loginButtonColour(tester, id);
      expect(colour, TodoColors.byId(id, Brightness.light).accent, reason: id);
    }
  });
}
