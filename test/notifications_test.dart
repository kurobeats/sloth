import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/notification_tile.dart';

/// Payload shapes taken from a live Vikunja (`GET /notifications`).
const _comment = '''
{"id":3,"name":"task.comment","created":"2026-10-24T23:20:00Z",
 "read_at":"0001-01-01T00:00:00Z",
 "notification":{
   "doer":{"id":1,"name":"Joe","username":"joe"},
   "task":{"id":3,"title":"Fix bike","project_id":1},
   "comment":{"id":1,"comment":"Chain needs replacing"},
   "mentioned":false,
   "project":{"id":1,"title":"Inbox"}}}
''';

const _assigned = '''
{"id":2,"name":"task.assigned","created":"2026-10-24T23:18:00Z",
 "read_at":"2026-10-24T23:19:00Z",
 "notification":{
   "doer":{"id":1,"name":"Joe","username":"joe"},
   "task":{"id":3,"title":"Fix bike","project_id":1},
   "project":{"id":1,"title":"Inbox"}}}
''';

const _team = '''
{"id":1,"name":"team.member.added","created":"2026-10-24T13:00:00Z",
 "read_at":"0001-01-01T00:00:00Z",
 "notification":{
   "member":{"id":2,"username":"priya"},
   "doer":{"id":1,"name":"Joe","username":"joe"},
   "team":{"id":1,"title":"Household"}}}
''';

/// The same team notification, already read: a real `read_at` timestamp.
const _teamRead = '''
{"id":1,"name":"team.member.added","created":"2026-10-24T13:00:00Z",
 "read_at":"2026-10-24T13:05:00Z",
 "notification":{
   "member":{"id":2,"username":"priya"},
   "doer":{"id":1,"name":"Joe","username":"joe"},
   "team":{"id":1,"title":"Household"}}}
''';

VikunjaNotification parse(String json) =>
    VikunjaNotification.fromJson(jsonDecode(json) as Map<String, dynamic>);

Widget host(Widget child) => MaterialApp(
  theme: buildTodoTheme(TodoColors.gruvboxLight),
  home: Scaffold(body: child),
);

void main() {
  group('VikunjaNotification', () {
    test('a comment notification names the task, doer and comment', () {
      final n = parse(_comment);
      expect(n.taskId, 3);
      expect(n.taskTitle, 'Fix bike');
      expect(n.title, contains('Joe'));
      expect(n.title, contains('Fix bike'));
      expect(n.subtitle, 'Chain needs replacing');
      expect(n.isRead, isFalse);
    });

    test('an assignment notification says who assigned the task', () {
      final n = parse(_assigned);
      expect(n.taskId, 3);
      expect(n.title, contains('assigned'));
      expect(n.isRead, isTrue, reason: 'read_at is a real timestamp');
    });

    test('a team notification has no task to open', () {
      final n = parse(_team);
      expect(n.taskId, isNull);
      expect(n.title, contains('Household'));
      expect(n.subtitle, contains('Joe'));
      expect(n.isRead, isFalse);
    });
  });

  group('NotificationTile', () {
    // The unread dot is always in the tree — a read row paints the same icon
    // transparent — so `find.byIcon(Icons.circle)` says nothing about read
    // state. Read the painted colour (and the title weight) instead.
    Color? dotColour(WidgetTester tester) =>
        tester.widget<Icon>(find.byIcon(Icons.circle)).color;

    FontWeight? titleWeight(WidgetTester tester, String text) =>
        tester.widget<Text>(find.textContaining(text)).style?.fontWeight;

    testWidgets('an unread row paints the dot with the accent colour', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          NotificationTile(
            notification: parse(_comment),
            onOpen: () => opened++,
          ),
        ),
      );
      expect(parse(_comment).isRead, isFalse, reason: 'the fixture is unread');

      expect(
        dotColour(tester),
        TodoColors.gruvboxLight.accent,
        reason: 'an unread row must mark itself',
      );
      expect(titleWeight(tester, 'Fix bike'), FontWeight.w600);

      await tester.tap(find.textContaining('Fix bike'));
      expect(opened, 1);
    });

    testWidgets('a read row paints the dot transparent and cannot open', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          NotificationTile(
            notification: parse(_teamRead),
            onOpen: () => opened++,
          ),
        ),
      );
      expect(parse(_teamRead).isRead, isTrue, reason: 'the fixture is read');

      expect(
        dotColour(tester),
        Colors.transparent,
        reason: 'a read row must not show the unread dot',
      );
      expect(titleWeight(tester, 'Household'), FontWeight.normal);

      await tester.tap(find.textContaining('Household'));
      expect(opened, 0, reason: 'team notifications have no task to open');
    });
  });
}
