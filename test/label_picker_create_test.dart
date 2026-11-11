import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/labels_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// The task label picker needs a way to create a label in place: opening the
/// full Labels screen mid-edit loses the task context.
void main() {
  testWidgets('picker creates a label and leaves it ticked', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final calls = <String>[];
    final api = VikunjaApi(
      baseUrl: 'https://tasks.example.com',
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode({'id': 9, 'title': 'Fresh', 'hex_color': ''}),
          200,
        );
      }),
    );
    final task = VikunjaTask(id: 4, projectId: 1, title: 'Fix bike');
    final state = AppState()
      ..api = api
      ..user = const VikunjaUser(id: 1, username: 'me')
      ..labels = const [VikunjaLabel(id: 1, title: 'Errands', hexColor: '')];

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTodoTheme(TodoColors.gruvboxLight),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    final flow = showLabelPicker(
      tester.element(find.byType(Scaffold)),
      state,
      task,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New label'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField).first, 'Fresh');
    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(state.labels.last.title, 'Fresh');
    // The created label is pre-ticked; Apply attaches it to the task.
    expect(
      find.byType(CheckboxListTile),
      findsNWidgets(2),
      reason: 'the picker now lists the created label',
    );
    final fresh = find.byType(CheckboxListTile).last;
    expect(
      tester.widget<CheckboxListTile>(fresh).value,
      isTrue,
      reason: 'newly created labels start selected',
    );

    await tester.tap(find.text('Apply'));
    await tester.pump();
    await flow;
    await tester.pump();

    expect(
      calls,
      containsAllInOrder([
        'PUT /api/v1/labels',
        'POST /api/v1/tasks/4/labels/bulk',
      ]),
      reason: 'create then bulk-set on the task',
    );
  });
}
