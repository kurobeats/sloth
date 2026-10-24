import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';

void main() {
  test('bucket parses embedded tasks from the kanban view endpoint', () {
    // Shape taken from GET /projects/1/views/4/tasks on a live Vikunja.
    final json = jsonDecode('''
    [{"id":1,"title":"To-Do","project_view_id":4,"tasks":[
      {"id":3,"title":"Fix bike","done":false,"project_id":1,"labels":[]},
      {"id":4,"title":"Buy Oat Milk","done":true}
    ]},
    {"id":2,"title":"Doing","project_view_id":4,"tasks":[]}]
    ''') as List;

    final buckets = json
        .map((e) => VikunjaBucket.fromJson(e as Map<String, dynamic>))
        .toList();

    expect(buckets.map((b) => b.title), ['To-Do', 'Doing']);
    expect(buckets.first.tasks.map((t) => t.title), [
      'Fix bike',
      'Buy Oat Milk',
    ]);
    expect(buckets.first.tasks.last.done, isTrue);
    expect(buckets.last.tasks, isEmpty);
  });

  test('relations parse from both name and number keys', () {
    // Current servers key related_tasks by name; old ones used numbers.
    final byName = parseRelations({
      'subtask': [
        {'id': 7, 'title': 'Child', 'done': false},
      ],
      'related': [
        {'id': 2, 'title': 'Sibling', 'done': true},
      ],
    });
    expect(byName.map((r) => r.kind), ['subtask', 'related']);
    expect(byName.first.title, 'Child');

    final byNumber = parseRelations({
      '1': [
        {'id': 7, 'title': 'Child', 'done': false},
      ],
      '3': [
        {'id': 2, 'title': 'Sibling', 'done': true},
      ],
    });
    expect(byNumber.map((r) => r.kind), ['subtask', 'related']);
    expect(VikunjaRelation.label(byNumber.last.kind), 'Related');
  });

  test('project exposes its kanban view only when one exists', () {
    VikunjaProject project(List<Map<String, dynamic>> views) =>
        VikunjaProject.fromJson({'id': 1, 'title': 'Inbox', 'views': views});

    expect(
      project([
        {'id': 1, 'title': 'List', 'view_kind': 'list'},
        {'id': 4, 'title': 'Kanban', 'view_kind': 'kanban'},
      ]).kanbanViewId,
      4,
    );
    expect(
      project([
        {'id': 1, 'title': 'List', 'view_kind': 'list'},
        {'id': 2, 'title': 'Gantt', 'view_kind': 'gantt'},
      ]).kanbanViewId,
      isNull,
    );
  });
}
