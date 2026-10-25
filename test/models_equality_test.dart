import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/models.dart';

/// Models carry value equality so a locally edited task can be compared with
/// the one the server returned, and so `copyWith` clones can stand in for the
/// instance held in the caches.
void main() {
  VikunjaTask sample() => VikunjaTask(
    id: 7,
    projectId: 4,
    title: 'Fix bike',
    description: 'Chain first.',
    dueDate: DateTime(2026, 10, 25, 12),
    priority: 4,
    isFavorite: true,
    percentDone: 0.5,
    labels: [const VikunjaLabel(id: 2, title: 'Errands', hexColor: '#2e7dd1')],
    assignees: [const VikunjaUser(id: 2, username: 'priya', name: 'Priya')],
    reminders: [VikunjaReminder(reminder: DateTime(2026, 10, 25, 9))],
    repeatAfter: 3600,
    repeatMode: 1,
  );

  test('models compare by value', () {
    expect(sample(), sample());
    expect(sample().hashCode, sample().hashCode);
    expect(sample(), isNot(sample()..title = 'Buy chain'));
    expect(
      VikunjaTask(id: 1, projectId: 1, title: 'x'),
      isNot(VikunjaTask(id: 2, projectId: 1, title: 'x')),
      reason: 'ids differ',
    );
    expect(
      const VikunjaProject(id: 1, title: 'Home'),
      const VikunjaProject(id: 1, title: 'Home'),
    );
    expect(
      const VikunjaLabel(id: 1, title: 'Home', hexColor: '#fff'),
      isNot(const VikunjaLabel(id: 1, title: 'Home', hexColor: '#000')),
    );
    expect(
      const VikunjaUser(id: 1, username: 'me'),
      const VikunjaUser(id: 1, username: 'me'),
    );
  });

  test('copyWith changes one field and leaves the rest alone', () {
    final copy = sample().copyWith(title: 'Buy chain');

    expect(copy.title, 'Buy chain');
    expect(copy, isNot(sample()));
    expect(copy, sample()..title = 'Buy chain');
    expect(copy.hashCode, (sample()..title = 'Buy chain').hashCode);
    expect(copy.dueDate, DateTime(2026, 10, 25, 12));
    expect(copy.labels.single.title, 'Errands');
    expect(copy.repeatAfter, 3600);
  });

  test('the cache JSON shape survives a round trip', () {
    // toJson is the POST body: it carries what the server replaces wholesale,
    // so an assignee's display name is not part of it.
    final task = VikunjaTask(
      id: 7,
      projectId: 4,
      title: 'Fix bike',
      description: 'Chain first.',
      done: true,
      doneAt: DateTime(2026, 10, 25, 18),
      dueDate: DateTime(2026, 10, 25, 12),
      startDate: DateTime(2026, 10, 24, 9),
      endDate: DateTime(2026, 10, 26, 9),
      priority: 4,
      isFavorite: true,
      percentDone: 1,
      labels: [
        const VikunjaLabel(id: 2, title: 'Errands', hexColor: '#2e7dd1'),
      ],
      assignees: [const VikunjaUser(id: 2, username: 'priya')],
      reminders: [VikunjaReminder(reminder: DateTime(2026, 10, 25, 9))],
      repeatAfter: 3600,
      repeatMode: 1,
    );
    final encoded = jsonEncode(task.toJson());
    final back = VikunjaTask.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );

    expect(back, task);
    expect(back.toJson(), task.toJson(), reason: 'offline cache stays readable');
    // The keys the snapshot on disk is written with must not change.
    expect(
      task.toJson().keys,
      containsAll([
        'id',
        'project_id',
        'title',
        'description',
        'done',
        'due_date',
        'priority',
        'is_favorite',
        'percent_done',
        'labels',
        'assignees',
        'reminders',
      ]),
    );
  });
}
