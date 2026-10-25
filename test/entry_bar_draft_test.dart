import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/entry_bar.dart';

Widget host(Future<bool> Function(String title) onSubmit) => MaterialApp(
  theme: buildTodoTheme(TodoColors.gruvboxLight),
  home: Scaffold(body: EntryBar(onSubmit: onSubmit)),
);

void main() {
  testWidgets('a failed add keeps the typed title in the bar', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      host((title) async {
        submitted.add(title);
        return false;
      }),
    );

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    await tester.pump();

    expect(submitted, ['Buy milk']);
    expect(
      find.text('Buy milk'),
      findsOneWidget,
      reason: 'the draft must survive a failed add',
    );
  });

  testWidgets('a successful add clears the bar', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      host((title) async {
        submitted.add(title);
        return true;
      }),
    );

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    await tester.pump();

    expect(submitted, ['Buy milk']);
    expect(find.text('Buy milk'), findsNothing);
  });
}
