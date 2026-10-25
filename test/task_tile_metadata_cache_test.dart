import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/todo_format.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/task_tile.dart';

VikunjaTask task() => VikunjaTask(
  id: 1,
  projectId: 2,
  title: 'Buy milk',
  description: 'from the corner shop',
  // Far enough out that the label is a formatted date, not a "Today" literal.
  dueDate: DateTime.now().add(const Duration(days: 10)),
  labels: const [VikunjaLabel(id: 1, title: 'errand', hexColor: '#1174E4')],
);

Widget host(VikunjaTask t, void Function(StateSetter rebuild) onRebuild) =>
    MaterialApp(
      theme: buildTodoTheme(TodoColors.gruvboxLight),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            onRebuild(setState);
            return TaskTile(
              task: t,
              onTap: () {},
              onToggleDone: () {},
              onToggleStar: () {},
            );
          },
        ),
      ),
    );

void main() {
  testWidgets('renders the same metadata text as before', (tester) async {
    final t = task();
    await tester.pumpWidget(host(t, (_) {}));

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text(TodoFormat.metadataLabel(t.dueDate!)), findsOneWidget);
    expect(find.text('errand'), findsOneWidget);
  });

  testWidgets('a rebuild reuses the formatted date label', (tester) async {
    final t = task();
    late StateSetter rebuild;
    await tester.pumpWidget(host(t, (setState) => rebuild = setState));

    String label() =>
        tester.widget<Text>(find.text(TodoFormat.metadataLabel(t.dueDate!))).data!;

    final first = label();
    rebuild(() {});
    await tester.pump();
    final second = label();

    expect(
      identical(first, second),
      isTrue,
      reason: 'the date label is re-formatted on every build',
    );
  });
}
