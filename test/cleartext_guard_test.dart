import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';
import 'package:sloth/screens/login_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// Plain http would put the password and the 90-day session token on the wire
/// in the clear, so only https (or loopback, for tests and desktop dev) is
/// allowed.
const cleartext =
    'Use https:// — plain http would send your password in the clear';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plain http to a remote host is refused', () {
    expect(
      () => VikunjaApi(baseUrl: 'http://vikunja.example.com'),
      throwsA(
        isA<VikunjaException>().having((e) => e.message, 'message', cleartext),
      ),
    );
    expect(
      () => VikunjaApi(baseUrl: 'http://192.168.0.10:3456'),
      throwsA(isA<VikunjaException>()),
    );
  });

  test('https and loopback http are accepted', () {
    for (final url in [
      'https://vikunja.example.com',
      'vikunja.example.com',
      'http://127.0.0.1:3456',
      'http://localhost:3456',
    ]) {
      VikunjaApi(baseUrl: url).close();
    }
  });

  testWidgets('the login form says why plain http is refused', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
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
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'http://vikunja.example.com');
    await tester.enterText(fields.at(1), 'joe');
    await tester.enterText(fields.at(2), 'secret');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(cleartext), findsOneWidget);
  });
}
