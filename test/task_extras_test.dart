import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/task_extras.dart';

Widget host(Widget child) => MaterialApp(
  theme: buildTodoTheme(TodoColors.gruvboxLight),
  home: Scaffold(body: child),
);

VikunjaRelation relation({
  String kind = VikunjaRelation.related,
  bool done = false,
}) => VikunjaRelation(kind: kind, taskId: 9, title: 'Buy Oat Milk', done: done);

VikunjaAttachment attachment({int size = 40}) =>
    VikunjaAttachment(id: 3, taskId: 1, name: 'chain-notes.txt', size: size);

VikunjaComment comment({int authorId = 1}) => VikunjaComment(
  id: 5,
  comment: 'Chain needs replacing',
  author: VikunjaUser(id: authorId, username: 'joe', name: 'Joe'),
  created: DateTime.now(),
);

void main() {
  test('offline state reports editing as disabled', () {
    final state = AppState();
    expect(state.canEdit, isTrue);
    state.offline = true;
    expect(state.canEdit, isFalse);
    expect(AppState.offlineEditError, contains('disabled while offline'));
  });

  group('RelationTile', () {
    testWidgets('a subtask shows a check box and toggles done', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        host(
          RelationTile(
            relation: relation(kind: VikunjaRelation.subtask),
            onOpen: () {},
            onRemove: () {},
            onToggleDone: () => toggles++,
          ),
        ),
      );

      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      expect(toggles, 1);
    });

    testWidgets('a done subtask is struck through', (tester) async {
      await tester.pumpWidget(
        host(
          RelationTile(
            relation: relation(kind: VikunjaRelation.subtask, done: true),
            onOpen: () {},
            onRemove: () {},
            onToggleDone: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      final title = tester.widget<Text>(find.text('Buy Oat Milk'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('other kinds show a link icon and no checkbox', (tester) async {
      await tester.pumpWidget(
        host(
          RelationTile(
            relation: relation(),
            onOpen: () {},
            onRemove: () {},
            onToggleDone: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.link), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(
        find.text(VikunjaRelation.label(VikunjaRelation.related)),
        findsOneWidget,
      );
    });

    testWidgets('row opens the task and the x removes the relation', (
      tester,
    ) async {
      var opened = 0, removed = 0;
      await tester.pumpWidget(
        host(
          RelationTile(
            relation: relation(),
            onOpen: () => opened++,
            onRemove: () => removed++,
            onToggleDone: () {},
          ),
        ),
      );

      await tester.tap(find.text('Buy Oat Milk'));
      expect(opened, 1);
      await tester.tap(find.byIcon(Icons.close));
      expect(removed, 1);
      expect(opened, 1);
    });
  });

  group('AttachmentTile', () {
    testWidgets('shows the name and a human readable size', (tester) async {
      await tester.pumpWidget(
        host(
          AttachmentTile(
            attachment: attachment(),
            onOpen: () {},
            onRemove: () {},
          ),
        ),
      );

      expect(find.text('chain-notes.txt'), findsOneWidget);
      expect(find.text('40 B'), findsOneWidget);
    });

    testWidgets('tap shares and x deletes', (tester) async {
      var opened = 0, removed = 0;
      await tester.pumpWidget(
        host(
          AttachmentTile(
            attachment: attachment(),
            onOpen: () => opened++,
            onRemove: () => removed++,
          ),
        ),
      );

      await tester.tap(find.text('chain-notes.txt'));
      expect(opened, 1);
      await tester.tap(find.byIcon(Icons.close));
      expect(removed, 1);
      expect(opened, 1);
    });
  });

  group('CommentTile', () {
    testWidgets('shows author and text, no delete for other people', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          CommentTile(comment: comment(), canDelete: false, onDelete: () {}),
        ),
      );

      expect(find.text('Joe'), findsOneWidget);
      expect(find.text('Chain needs replacing'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('your own comment can be deleted', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(
        host(
          CommentTile(
            comment: comment(),
            canDelete: true,
            onDelete: () => deleted++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      expect(deleted, 1);
    });
  });
}
