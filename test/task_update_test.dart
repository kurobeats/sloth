import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';

/// `POST /tasks/{id}` is a full replace: a field left out of the body is
/// zeroed by the server (verified against Vikunja v2.7.1 — omitting due_date
/// cleared a task's due date). So every update must carry the whole task.
const _serverTask = '''
{"id":7,"project_id":4,"title":"Fix bike","description":"Chain first.",
 "done":false,"done_at":"0001-01-01T00:00:00Z","due_date":"2026-10-25T12:00:00Z",
 "start_date":"0001-01-01T00:00:00Z","end_date":"0001-01-01T00:00:00Z",
 "priority":4,"is_favorite":false,"percent_done":0,"repeat_after":3600,
 "repeat_mode":1,"labels":[{"id":2,"title":"Errands","hex_color":"2e7dd1"}],
 "assignees":[{"id":2,"username":"priya","name":"Priya"}],
 "reminders":[{"reminder":"2026-10-25T09:00:00Z"}],
 "related_tasks":{"subtask":[{"id":2,"title":"Buy Oat Milk"}]},
 "attachments":[{"id":1,"task_id":7,"file":{"name":"chain.txt","size":40}}]}
''';

void main() {
  test('an update body keeps every field the server stores', () {
    final task = VikunjaTask.fromJson(
      jsonDecode(_serverTask) as Map<String, dynamic>,
    );
    final body = task.toJson();

    expect(body['description'], 'Chain first.');
    expect(body['due_date'], '2026-10-25T12:00:00.000Z');
    expect(body['priority'], 4);
    expect(body['repeat_after'], 3600);
    expect(body['repeat_mode'], 1);
    expect((body['labels'] as List).single, containsPair('title', 'Errands'));
    expect(
      (body['assignees'] as List).single,
      containsPair('username', 'priya'),
    );
    expect(
      (body['reminders'] as List).single,
      containsPair('reminder', isA<String>()),
    );
  });

  test('marking done keeps the rest of the task intact', () {
    final task = VikunjaTask.fromJson(
      jsonDecode(_serverTask) as Map<String, dynamic>,
    );
    task
      ..done = true
      ..percentDone = 1
      ..doneAt = DateTime.utc(2026, 10, 25, 18);
    final body = task.toJson();

    expect(body['done'], isTrue);
    expect(body['done_at'], startsWith('2026-10-25T18:00:00'));
    expect(body['due_date'], '2026-10-25T12:00:00.000Z', reason: 'not cleared');
    expect(body['description'], 'Chain first.');
    expect(body['labels'], hasLength(1));
  });

  test('a cleared due date is sent as the zero timestamp', () {
    final task = VikunjaTask.fromJson(
      jsonDecode(_serverTask) as Map<String, dynamic>,
    );
    task.dueDate = null;
    expect(task.toJson()['due_date'], startsWith('0001-01-01'));
  });
}
