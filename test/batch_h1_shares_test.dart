import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

const _server = 'https://tasks.example.com';

/// A server that keeps its own share/board/team state, so a mutation followed
/// by a read shows what the server now holds.
class ShareServer {
  final List<String> requests = [];
  int status = 200;
  final users = <Map<String, dynamic>>[
    {'id': 7, 'username': 'joe', 'name': 'Joe', 'permission': 1},
  ];
  final teams = <Map<String, dynamic>>[
    {'id': 3, 'name': 'Household', 'permission': 2},
  ];
  final links = <Map<String, dynamic>>[
    {'id': 5, 'hash': 'abc123', 'name': 'Public link', 'permission': 0},
  ];
  final members = <Map<String, dynamic>>[
    {'id': 1, 'username': 'me', 'admin': true},
    {'id': 2, 'username': 'joe', 'admin': false},
  ];
  final bucketTasks = <int, List<int>>{
    1: [1, 2],
    2: [],
  };

  VikunjaApi get api => VikunjaApi(
    baseUrl: _server,
    client: MockClient((request) async {
      final path = request.url.path;
      final method = request.method;
      requests.add('$method $path');
      if (status != 200) {
        return http.Response('{"message":"Server said no"}', status);
      }
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      if (path.endsWith('/info')) {
        return http.Response('{"frontend_url":"$_server"}', 200);
      }
      if (path.endsWith('/projects/1/users')) {
        if (method == 'PUT') {
          users.add({
            'id': body['user_id'],
            'username': 'added',
            'name': 'Added',
            'permission': body['permission'],
          });
          return http.Response('{}', 200);
        }
        return http.Response(jsonEncode(users), 200);
      }
      if (path.contains('/projects/1/users/')) {
        final id = path.split('/').last;
        users.removeWhere((u) => '${u['id']}' == id);
        return http.Response('{}', 200);
      }
      if (path.endsWith('/projects/1/teams')) {
        if (method == 'PUT') {
          teams.add({
            'id': body['team_id'],
            'name': 'Added team',
            'permission': body['permission'],
          });
          return http.Response('{}', 200);
        }
        return http.Response(jsonEncode(teams), 200);
      }
      if (path.contains('/projects/1/teams/')) {
        final id = path.split('/').last;
        teams.removeWhere((t) => '${t['id']}' == id);
        return http.Response('{}', 200);
      }
      if (path.endsWith('/projects/1/shares')) {
        if (method == 'PUT') {
          links.add({
            'id': 9,
            'hash': 'newhash',
            'name': body['name'],
            'permission': body['permission'],
          });
          return http.Response(jsonEncode(links.last), 200);
        }
        return http.Response(jsonEncode(links), 200);
      }
      if (path.contains('/projects/1/shares/')) {
        final id = path.split('/').last;
        links.removeWhere((l) => '${l['id']}' == id);
        return http.Response('{}', 200);
      }
      if (method == 'PUT' && path.endsWith('/projects')) {
        return http.Response(
          jsonEncode({'id': 9, 'title': body['title']}),
          200,
        );
      }
      if (path.endsWith('/teams/1')) {
        return http.Response(
          jsonEncode({'id': 1, 'name': 'Household', 'members': members}),
          200,
        );
      }
      if (path.contains('/members/') && path.endsWith('/admin')) {
        final username = path.split('/')[4];
        for (final member in members) {
          if (member['username'] == username) {
            member['admin'] = !(member['admin'] as bool);
          }
        }
        return http.Response('{}', 200);
      }
      if (path.contains('/buckets/')) {
        final bucketId = int.parse(path.split('/buckets/')[1].split('/')[0]);
        final taskId = body['task_id'] as int;
        for (final tasks in bucketTasks.values) {
          tasks.remove(taskId);
        }
        bucketTasks[bucketId] = [...?bucketTasks[bucketId], taskId];
        return http.Response('{}', 200);
      }
      if (path.endsWith('/views/4/tasks')) {
        return http.Response(
          jsonEncode([
            for (final entry in bucketTasks.entries)
              {
                'id': entry.key,
                'title': 'Bucket ${entry.key}',
                'tasks': [
                  for (final id in entry.value)
                    {'id': id, 'title': 'Task $id', 'project_id': 1},
                ],
              },
          ]),
          200,
        );
      }
      return http.Response('[]', 200);
    }),
  );

  AppState state({bool offline = false}) => AppState()
    ..api = api
    ..user = const VikunjaUser(id: 1, username: 'me')
    ..offline = offline;
}

const _project = VikunjaProject(
  id: 1,
  title: 'Inbox',
  views: [VikunjaView(id: 4, title: 'Kanban', viewKind: 'kanban')],
);

void main() {
  group('F-054 state-level shares', () {
    test('offline every share call refuses without a request', () async {
      final server = ShareServer();
      final state = server.state(offline: true);

      final errors = [
        await state.projectShares(1),
        await state.addUserShare(1, 7, 2),
        await state.addTeamShare(1, 3, 2),
        await state.removeShare(1, userId: 7),
        await state.removeShare(1, teamId: 3),
        await state.deleteLinkShare(1, 5),
        await state.createProject('New list'),
      ];

      expect(errors, everyElement(AppState.offlineEditError));
      expect(server.requests, isEmpty, reason: 'offline is read-only');
    });

    test('projectShares loads once and the state owns the result', () async {
      final server = ShareServer();
      final state = server.state();

      expect(await state.projectShares(1), isNull);

      final shares = state.sharesOf(1);
      expect(shares.users.single.displayName, 'Joe');
      expect(shares.teams.single.displayName, 'Household');
      expect(shares.links.single.name, 'Public link');
      expect(shares.frontendUrl, _server);
      expect(server.requests.length, 4, reason: 'one read per endpoint');
    });

    test('a share mutation calls the api once and reaches the state', () async {
      final server = ShareServer();
      final state = server.state();
      await state.projectShares(1);
      server.requests.clear();

      expect(await state.addUserShare(1, 11, 2), isNull);
      expect(server.requests, ['PUT /api/v1/projects/1/users']);

      await state.projectShares(1);
      expect(state.sharesOf(1).users.map((s) => s.userId), [
        7,
        11,
      ], reason: 'the new share is in the state after the reload');
    });

    test('removing a share and a link share each cost one request', () async {
      final server = ShareServer();
      final state = server.state();
      await state.projectShares(1);
      server.requests.clear();

      expect(await state.removeShare(1, userId: 7), isNull);
      await state.projectShares(1);
      expect(state.sharesOf(1).users, isEmpty);
      expect(server.requests, [
        'DELETE /api/v1/projects/1/users/7',
        'GET /api/v1/projects/1/users',
        'GET /api/v1/projects/1/teams',
        'GET /api/v1/projects/1/shares',
        'GET /api/v1/info',
      ]);

      server.requests.clear();
      expect(await state.deleteLinkShare(1, 5), isNull);
      expect(server.requests, ['DELETE /api/v1/projects/1/shares/5']);
      await state.projectShares(1);
      expect(state.sharesOf(1).links, isEmpty);
    });

    test(
      'createProject goes through the offline guard and the state',
      () async {
        final server = ShareServer();
        final state = server.state();

        expect(await state.createProject('New list'), isNull);

        expect(server.requests, ['PUT /api/v1/projects']);
        expect(state.projects.map((p) => p.title), contains('New list'));
      },
    );
  });

  group('F-055 last admin', () {
    test('demoting the last admin is refused and changes nothing', () async {
      final server = ShareServer();
      final state = server.state();
      // Only 'me' is an admin: demoting them would lock the team.
      server.members.removeWhere((m) => m['username'] == 'me');
      server.members.add({'id': 1, 'username': 'me', 'admin': true});

      final error = await state.toggleTeamMemberAdmin(1, 'me');

      expect(error, AppState.lastAdminError);
      expect(
        server.requests.where((r) => r.endsWith('/admin')),
        isEmpty,
        reason: 'the server is never asked to break the team',
      );
    });

    test('demoting an admin while another exists succeeds', () async {
      final server = ShareServer();
      final state = server.state();
      server.members
        ..clear()
        ..addAll([
          {'id': 1, 'username': 'me', 'admin': true},
          {'id': 2, 'username': 'joe', 'admin': true},
        ]);

      final error = await state.toggleTeamMemberAdmin(1, 'joe');

      expect(error, isNull);
      expect(server.requests.where((r) => r.endsWith('/admin')), hasLength(1));
    });
  });

  group('F-057 buckets', () {
    test('loadBoard fills the state, not the screen', () async {
      final server = ShareServer();
      final state = server.state();

      expect(state.bucketsFor(_project), isNull);
      expect(await state.loadBoard(_project), isNull);

      final buckets = state.bucketsFor(_project)!;
      expect(buckets.map((b) => b.title), ['Bucket 1', 'Bucket 2']);
      expect(buckets.first.tasks.map((t) => t.id), [1, 2]);
    });

    test('a move updates the buckets the state holds', () async {
      final server = ShareServer();
      final state = server.state();
      await state.loadBoard(_project);

      expect(await state.moveToBucket(_project, 1, 2), isNull);

      final buckets = state.bucketsFor(_project)!;
      expect(buckets[0].tasks.map((t) => t.id), [2]);
      expect(buckets[1].tasks.map((t) => t.id), [1]);
    });

    test('a failed move leaves the buckets as they were', () async {
      final server = ShareServer();
      final state = server.state();
      await state.loadBoard(_project);
      final before = state.bucketsFor(_project)!;

      server.status = 500;
      final error = await state.moveToBucket(_project, 1, 2);

      expect(error, 'Server said no');
      final after = state.bucketsFor(_project)!;
      expect(after[0].tasks.map((t) => t.id), before[0].tasks.map((t) => t.id));
      expect(after[1].tasks, isEmpty);
    });
  });

  group('F-060 showProject', () {
    test('every selection maps to the boolean the screen used', () {
      const project = ListSelection.project(
        VikunjaProject(id: 1, title: 'Inbox'),
      );
      const tag = ListSelection.tag(
        VikunjaLabel(id: 2, title: 'Urgent', hexColor: 'ff0000'),
      );
      final selections = <ListSelection>[
        for (final smart in SmartList.values) ListSelection.smart(smart),
        project,
        tag,
      ];

      /// The expression the home screen decided inline.
      bool oldRule(ListSelection s) =>
          s.tag != null ||
          s.smart == SmartList.allTasks ||
          s.smart == SmartList.assigned ||
          s.smart == SmartList.favorites;

      for (final selection in selections) {
        expect(
          selection.showProject,
          oldRule(selection),
          reason: selection.key,
        );
      }
    });
  });
}
