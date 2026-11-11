import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/main.dart';
import 'package:sloth/models.dart';
import 'package:sloth/widgets/entry_bar.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/screens/login_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const HomeScreen(),
  ),
);

/// Signed in from the start and never restores: shell goes to the list.
class ReadyState extends AppState {
  ReadyState() {
    api = VikunjaApi(
      baseUrl: 'https://tasks.example.com',
      client: MockClient((request) async => http.Response('[]', 200)),
    );
    user = const VikunjaUser(id: 1, username: 'me');
    restoring = false;
  }

  @override
  Future<void> restore() async {}
}

Future<AppState> signedInState() async {
  final state = AppState();
  state.api = VikunjaApi(
    baseUrl: 'https://tasks.example.com',
    client: MockClient((request) async {
      if (request.url.path.endsWith('/tasks')) {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('[]', 200);
    }),
  );
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

/// Android's answer for 'sloth/share' getSharedText; null means no share.
void mockSharedText(String? text) {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('sloth/share'), (call) async {
        if (call.method == 'getSharedText') return text;
        return null as String?;
      });
}

void main() {
  testWidgets('shared text lands in the add-a-task bar as a draft', (
    tester,
  ) async {
    final state = await signedInState();
    state.sharedDraft.value = 'Read the article';
    state.newTaskRequests.value++;
    await tester.pumpWidget(host(state));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Read the article'), findsOneWidget);
    // Consumed: another home-screen pass must not refill the bar.
    expect(state.sharedDraft.value, isNull);
  });

  testWidgets('SlothApp pulls the share from the channel on start', (
    tester,
  ) async {
    mockSharedText('Firefox page title\nhttps://example.com/article');
    final app = SlothApp(state: ReadyState());
    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump();
    // The share is one collapsed single-line draft: "title\nURL" -> spaces.
    expect(
      find.widgetWithText(
        TextField,
        'Firefox page title https://example.com/article',
      ),
      findsOneWidget,
    );
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('EntryBar.setDraft fills the bar and moves the cursor', (
    tester,
  ) async {
    late EntryBarState bar;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryBar(
            onSubmit: (_) async => true,
            onDraftChanged: (_) {},
          ),
        ),
      ),
    );
    bar = tester.state(find.byType(EntryBar));
    bar.setDraft('Shared text');
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Shared text'), findsOneWidget);
  });
}
