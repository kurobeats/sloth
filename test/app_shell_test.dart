import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The `MaterialApp` is driven by `AppState.shell` alone: the appearance and
/// whether a session is up. Everything else the state notifies about (loading
/// flips, mutations, the notification poll) must not rebuild the app shell,
/// which would rebuild the navigator and the active route with it.
VikunjaApi fakeApi() => VikunjaApi(
  baseUrl: 'https://tasks.example.com',
  client: MockClient((request) async {
    if (request.url.path.endsWith('/tasks/1')) {
      return http.Response(
        jsonEncode({'id': 1, 'project_id': 1, 'title': 'Buy milk'}),
        200,
      );
    }
    return http.Response('[]', 200);
  }),
);

Future<AppState> signedIn() async {
  final state = AppState();
  state.api = fakeApi();
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.loadTask(1);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a data change does not reach the app shell', () async {
    final state = await signedIn();
    var shellEvents = 0;
    var dataEvents = 0;
    state.shell.addListener(() => shellEvents++);
    state.addListener(() => dataEvents++);
    final before = state.shell.value;

    await state.loadTask(1); // loading flip / mutation stand-in

    expect(dataEvents, greaterThan(0), reason: 'AppScope still rebuilds');
    expect(
      shellEvents,
      0,
      reason: 'the MaterialApp must not rebuild for data',
    );
    expect(identical(state.shell.value, before), isTrue);
  });

  test('an appearance change reaches the app shell once', () async {
    final state = await signedIn();
    var shellEvents = 0;
    state.shell.addListener(() => shellEvents++);

    await state.setLightTheme(TodoColors.patinaLight.id);

    expect(shellEvents, 1);
    expect(state.shell.value.lightTheme.id, 'patina-light');
    expect(state.shell.value.themeMode, state.themeMode);
  });

  test('a session change reaches the app shell', () async {
    final state = await signedIn();
    var shellEvents = 0;
    state.shell.addListener(() => shellEvents++);
    expect(state.shell.value.signedIn, isTrue);

    await state.signOut();

    expect(shellEvents, 1);
    expect(state.shell.value.signedIn, isFalse);
  });

  test('the shell keeps the restoring flag, so the app waits for the session',
      () async {
    final state = AppState();
    expect(state.shell.value.restoring, isTrue);
    expect(state.shell.value.themeMode, ThemeMode.system);
  });
}
