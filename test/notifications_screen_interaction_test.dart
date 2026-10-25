import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/screens/home_screen.dart';
import 'package:sloth/screens/notifications_screen.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/notification_tile.dart';

const _server = 'https://tasks.example.com';

/// One unread notification about a task, and one read team notification: the
/// two states the list has to tell apart.
const _feed = '''
[{"id":1,"name":"task.assigned","created":"2026-10-24T23:18:00Z",
  "read_at":"0001-01-01T00:00:00Z",
  "notification":{
    "doer":{"id":1,"name":"Joe","username":"joe"},
    "task":{"id":3,"title":"Fix bike","project_id":1},
    "project":{"id":1,"title":"Inbox"}}},
 {"id":2,"name":"team.member.added","created":"2026-10-24T13:00:00Z",
  "read_at":"2026-10-24T13:05:00Z",
  "notification":{
    "member":{"id":2,"username":"priya"},
    "doer":{"id":1,"name":"Joe","username":"joe"},
    "team":{"id":1,"title":"Household"}}}]
''';

/// The notifications feed plus the single task and the read receipt.
class InboxServer {
  InboxServer({this.feed = _feed});

  final String feed;
  final requests = <String>[];

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    final method = request.method;
    requests.add('$method $path');
    if (path.endsWith('/notifications')) {
      return http.Response(feed, 200);
    }
    if (path.contains('/notifications/')) return http.Response('{}', 200);
    final single = RegExp(r'/tasks/(\d+)$').firstMatch(path);
    if (single != null) {
      return http.Response(
        jsonEncode({
          'id': int.parse(single.group(1)!),
          'title': 'Fix bike',
          'project_id': 1,
        }),
        200,
      );
    }
    if (path.endsWith('/projects')) {
      return http.Response(
        jsonEncode([
          {'id': 1, 'title': 'Inbox'},
        ]),
        200,
      );
    }
    return http.Response('[]', 200);
  });

  Future<AppState> state({bool refresh = true}) async {
    final state = AppState();
    state.api = VikunjaApi(baseUrl: _server, client: client());
    state.user = const VikunjaUser(id: 1, username: 'me');
    if (refresh) await state.refresh();
    return state;
  }
}

Widget host(AppState state, Widget child) => AppScope(
  state: state,
  child: MaterialApp(
    theme: buildTodoTheme(TodoColors.gruvboxLight),
    home: child,
  ),
);

/// The dot colours of the rows on screen: accent means unread, transparent
/// means read.
List<Color?> dotColours(WidgetTester tester) => [
  for (final icon in tester.widgetList<Icon>(find.byIcon(Icons.circle)))
    icon.color,
];

void main() {
  testWidgets('unread rows keep their dot and read rows lose it', (
    tester,
  ) async {
    final server = InboxServer();
    final state = await server.state(refresh: false);
    await tester.pumpWidget(host(state, const NotificationsScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationTile), findsNWidgets(2));
    final colours = dotColours(tester);
    expect(colours.where((c) => c == TodoColors.gruvboxLight.accent), hasLength(1));
    expect(colours.where((c) => c == Colors.transparent), hasLength(1));
    expect(state.unreadNotifications, 1);
  });

  testWidgets('the drawer badge counts the unread notifications', (
    tester,
  ) async {
    final server = InboxServer();
    final state = await server.state();
    await tester.pumpWidget(host(state, const HomeScreen()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Notifications'),
      ),
      findsOneWidget,
    );
    expect(state.unreadNotifications, 1, reason: 'one row is unread');
    // Same helper shape as `home_screen_test.dart`: the count inside the
    // Notifications row itself, not some other row that happens to show 1.
    expect(
      find.descendant(
        of: find
            .ancestor(
              of: find.descendant(
                of: find.byType(Drawer),
                matching: find.text('Notifications'),
              ),
              matching: find.byType(InkWell),
            )
            .first,
        matching: find.text('1'),
      ),
      findsOneWidget,
      reason: 'the drawer row carries the unread count',
    );
  });

  testWidgets('tapping a notification marks it read and opens its task', (
    tester,
  ) async {
    final server = InboxServer();
    final state = await server.state(refresh: false);
    await tester.pumpWidget(host(state, const NotificationsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Fix bike'));
    await tester.pumpAndSettle();

    expect(
      server.requests.where((r) => r == 'POST /api/v1/notifications/1'),
      hasLength(1),
      reason: 'opening counts as reading it',
    );
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(server.requests.where((r) => r == 'GET /api/v1/tasks/3'), hasLength(1));
  });

  testWidgets('an empty feed renders the empty state', (tester) async {
    final server = InboxServer(feed: '[]');
    final state = await server.state(refresh: false);
    await tester.pumpWidget(host(state, const NotificationsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing new'), findsOneWidget);
    expect(find.byType(NotificationTile), findsNothing);
  });
}
