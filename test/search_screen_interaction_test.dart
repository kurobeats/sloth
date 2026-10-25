import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/search_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// An [AppState] whose searches the test answers by hand, so it can see when
/// the screen asks and what it does with a slow or failed answer.
class SearchFake extends AppState {
  final searches = <String, Completer<List<VikunjaTask>>>{};
  Object? searchError;

  @override
  Future<List<VikunjaTask>> searchTasks(String query) {
    final error = searchError;
    if (error != null) return Future.error(error);
    final completer = Completer<List<VikunjaTask>>();
    searches[query] = completer;
    return completer.future;
  }
}

Widget host(AppState state) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: const SearchScreen(),
  ),
);

VikunjaTask result(int id, String title) =>
    VikunjaTask(id: id, projectId: 1, title: title);

void main() {
  testWidgets('typing waits for the debounce, then renders the results', (
    tester,
  ) async {
    final state = SearchFake();
    await tester.pumpWidget(host(state));
    expect(find.text('Search your tasks'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bike');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      state.searches,
      isEmpty,
      reason: 'a keystroke on its own must not hit the server',
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(state.searches.keys, ['bike'], reason: 'one search for the query');
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'the spinner is up while the answer is outstanding',
    );

    state.searches['bike']!.complete([result(1, 'Fix bike')]);
    await tester.pump();

    expect(find.text('Fix bike'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed search says so and clears the spinner', (tester) async {
    final state = SearchFake()
      ..searchError = VikunjaException(500, 'Server said no');
    await tester.pumpWidget(host(state));

    await tester.enterText(find.byType(TextField), 'bike');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Server said no'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('No tasks found'),
      findsNothing,
      reason: 'a failure is not an empty result set',
    );
  });
}
