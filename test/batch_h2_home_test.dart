import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The list screen: what it says when there is nowhere to add a task, when the
/// read hit the row ceiling, and which colours its empty state paints with.
Widget host(AppState state, {TodoColors? scheme}) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(scheme ?? TodoColors.gruvboxLight),
    home: const HomeScreen(),
  ),
);

/// A signed-in state with no projects at all, and a count of the writes it saw.
class CountingState extends AppState {
  int writes = 0;
}

Future<CountingState> emptyState() async {
  final state = CountingState();
  state.api = VikunjaApi(
    baseUrl: 'https://tasks.example.com',
    client: MockClient((request) async {
      if (request.method != 'GET') state.writes++;
      return http.Response(request.method == 'GET' ? '[]' : '{}', 200);
    }),
  );
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

void main() {
  testWidgets('adding a task with no project says what is missing', (
    tester,
  ) async {
    final state = await emptyState();
    await tester.pumpWidget(host(state));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();

    expect(find.text('Create a list first'), findsOneWidget);
    expect(state.writes, 0, reason: 'no project means nothing to send');
  });

  testWidgets('the empty state repaints with the new scheme', (tester) async {
    final state = await emptyState();
    await tester.pumpWidget(host(state));
    await tester.pump();

    final before = tester
        .widget<Text>(find.text('Nothing due today'))
        .style
        ?.color;
    expect(before, TodoColors.gruvboxLight.primaryText);

    await tester.pumpWidget(host(state, scheme: TodoColors.patinaLight));
    // The theme change is animated, so the first frame still paints the old
    // scheme.
    await tester.pumpAndSettle();

    final after = tester
        .widget<Text>(find.text('Nothing due today'))
        .style
        ?.color;
    expect(after, TodoColors.patinaLight.primaryText);
  });

  testWidgets('a list cut at the row ceiling says so', (tester) async {
    final state = await emptyState();
    await tester.pumpWidget(host(state));
    await tester.pump();
    expect(find.text(AppState.truncationNotice), findsNothing);

    state.listTruncated = true;
    state.notifyListeners();
    await tester.pump();

    expect(find.text(AppState.truncationNotice), findsOneWidget);
  });
}
