import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/screens/login_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

const _server = 'https://tasks.example.com';

/// A password manager only offers the vault entry when the fields say what they
/// are: one AutofillGroup holding a `username` and a `password` hint. Saving is
/// signalled by `finishAutofillContext` once, on a login that worked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(AppState state) => AppScope(
    state: state,
    child: MaterialApp(
      theme: buildTodoTheme(TodoColors.gruvboxLight),
      home: const LoginScreen(),
    ),
  );

  /// The login form talks to whatever the client factory hands it, so a fake
  /// server decides whether the attempt works.
  Future<AppState> stateWith({int loginStatus = 200}) async {
    FlutterSecureStorage.setMockInitialValues({});
    final state = AppState();
    await state.loadAppearance();
    state.clientFactory = (baseUrl, {allowSelfSigned = false}) => VikunjaApi(
      baseUrl: baseUrl,
      allowSelfSigned: allowSelfSigned,
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/login')) {
          if (loginStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'Wrong username or password'}),
              loginStatus,
            );
          }
          return http.Response(jsonEncode({'token': 'not-a-jwt'}), 200);
        }
        if (path.endsWith('/info')) return http.Response('{}', 200);
        if (path.endsWith('/routes')) return http.Response('{}', 404);
        if (path.endsWith('/user')) {
          return http.Response(jsonEncode({'id': 1, 'username': 'me'}), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    return state;
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), _server);
    await tester.enterText(fields.at(1), 'me');
    await tester.enterText(fields.at(2), 'hunter2');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
  }

  testWidgets('the fields advertise a username and a password in one group', (
    tester,
  ) async {
    await tester.pumpWidget(host(await stateWith()));
    await tester.pumpAndSettle();

    expect(
      find.byType(AutofillGroup),
      findsOneWidget,
      reason: 'Bitwarden saves the pair as one entry',
    );
    final hints = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.autofillHints)
        .toList();
    expect(hints, hasLength(3), reason: 'server, username, password');
    expect(hints[0], isNull, reason: 'the server URL is not a credential');
    expect(hints[1], contains(AutofillHints.username));
    expect(hints[2], contains(AutofillHints.password));
  });

  testWidgets('the platform gets both hints in one autofill context', (
    tester,
  ) async {
    // What Flutter hands to Android is the whole contract with Bitwarden: a
    // context holding the username and the password field.
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null),
    );

    await tester.pumpWidget(host(await stateWith()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).at(1));
    await tester.pumpAndSettle();

    final payload = calls
        .where((c) => c.method == 'TextInput.setClient')
        .map((c) => jsonEncode(c.arguments))
        .join();
    expect(payload, contains('"hints":["username"]'));
    expect(payload, contains('"hints":["password"]'));
  });

  testWidgets('a successful login finishes the autofill context', (
    tester,
  ) async {
    final state = await stateWith();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null),
    );

    await fillAndSubmit(tester);

    expect(state.isSignedIn, isTrue, reason: 'the fake server said yes');
    expect(
      calls.where((m) => m == 'TextInput.finishAutofillContext'),
      hasLength(1),
      reason: 'the vault is offered the new password exactly once',
    );
  });

  testWidgets('a rejected login leaves the vault alone', (tester) async {
    final state = await stateWith(loginStatus: 401);
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null),
    );

    await fillAndSubmit(tester);

    expect(state.isSignedIn, isFalse);
    expect(
      calls.where((m) => m == 'TextInput.finishAutofillContext'),
      isEmpty,
      reason: 'a wrong password must not be offered for saving',
    );
  });
}
