import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/main.dart';
import 'package:sloth/screens/login_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The shell only rebuilds its `MaterialApp` for appearance and session
/// changes, so those are the transitions it must still get right.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in ['home_widget', 'home_widget/updates']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        return null;
      });
    }
  });

  testWidgets('the shell leaves the splash for the login screen', (
    tester,
  ) async {
    await tester.pumpWidget(const SlothApp());

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'the session is still being restored',
    );

    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    // Tears the app down so the notification poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a theme change repaints the shell', (tester) async {
    await tester.pumpWidget(const SlothApp());
    await tester.pumpAndSettle();

    final state = AppScope.of(tester.element(find.byType(LoginScreen)));
    await state.setLightTheme(TodoColors.patinaLight.id);
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme!.colorScheme.surface,
      TodoColors.patinaLight.primaryBackground,
    );

    await tester.pumpWidget(const SizedBox());
  });
}
