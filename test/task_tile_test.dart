import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/todo_format.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/task_tile.dart';

Widget host(TaskTile tile) => MaterialApp(
  theme: buildTodoTheme(TodoColors.gruvboxLight),
  home: Scaffold(body: tile),
);

VikunjaTask task({
  bool done = false,
  bool star = false,
  bool overdue = false,
}) => VikunjaTask(
  id: 1,
  projectId: 2,
  title: 'Buy milk',
  description: 'from the corner shop',
  done: done,
  isFavorite: star,
  dueDate: overdue
      ? DateTime.now().subtract(const Duration(days: 3))
      : DateTime.now(),
  labels: const [VikunjaLabel(id: 1, title: 'errand', hexColor: '#1174E4')],
);

void main() {
  testWidgets('renders title, metadata and check state', (tester) async {
    await tester.pumpWidget(
      host(
        TaskTile(
          task: task(),
          onTap: () {},
          onToggleDone: () {},
          onToggleStar: () {},
        ),
      ),
    );
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget); // due metadata
    expect(find.text('errand'), findsOneWidget); // first label name
    expect(find.byIcon(Icons.notes), findsOneWidget); // has description
  });

  testWidgets('done task strikes through and shows a filled check', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        TaskTile(
          task: task(done: true),
          onTap: () {},
          onToggleDone: () {},
          onToggleStar: () {},
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Buy milk'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tapping the circle and the star fires callbacks', (
    tester,
  ) async {
    var toggledDone = 0;
    var toggledStar = 0;
    await tester.pumpWidget(
      host(
        TaskTile(
          task: task(star: true),
          onTap: () {},
          onToggleDone: () => toggledDone++,
          onToggleStar: () => toggledStar++,
        ),
      ),
    );
    await tester.tap(find.byType(InkResponse).first); // checkbox target
    await tester.tap(find.byIcon(Icons.star));
    expect(toggledDone, 1);
    expect(toggledStar, 1);
  });

  testWidgets('overdue due date uses the overdue colour', (tester) async {
    await tester.pumpWidget(
      host(
        TaskTile(
          task: task(overdue: true),
          onTap: () {},
          onToggleDone: () {},
          onToggleStar: () {},
        ),
      ),
    );
    final due = DateTime.now().subtract(const Duration(days: 3));
    final label = tester.widget<Text>(find.text(TodoFormat.metadataLabel(due)));
    expect(label.style?.color, TodoColors.gruvboxLight.overdue);
  });
}
