import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

Map<String, dynamic> taskJson(
  int id,
  String title, {
  int projectId = 1,
  DateTime? due,
}) => {
  'id': id,
  'project_id': projectId,
  'title': title,
  if (due != null) 'due_date': due.toUtc().toIso8601String(),
};

VikunjaApi apiFixture(List<Map<String, dynamic>> tasks) => VikunjaApi(
  baseUrl: 'https://tasks.example.com',
  client: MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.contains('/views/')) {
      return http.Response(jsonEncode(tasks), 200);
    }
    if (request.method == 'GET' && path.contains('/projects')) {
      return http.Response(
        jsonEncode([
          {'id': 1, 'title': '2 Work'},
          {'id': 2, 'title': '11 Archive'},
          {'id': 3, 'title': '1 Personal', 'is_favorite': true},
        ]),
        200,
      );
    }
    if (request.method == 'GET' && path.endsWith('/tasks')) {
      return http.Response(jsonEncode(tasks), 200);
    }
    return http.Response('[]', 200);
  }),
);

/// In-memory storage: the sort setting is persisted, and a real
/// FlutterSecureStorage would need a platform binding.
class MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

Future<AppState> stateWith(List<Map<String, dynamic>> tasks) async {
  final state = AppState(storage: MemoryStorage());
  state.api = apiFixture(tasks);
  state.user = const VikunjaUser(id: 1, username: 'me');
  await state.refresh();
  return state;
}

void main() {
  test('compareNatural sorts digits numerically and letters A→Z', () {
    final titles = ['11.42 Z', '1.10 B', '1.2 A', '2.01 C', 'apple', 'Banana'];
    final sorted = [...titles]..sort(compareNatural);
    expect(sorted, [
      '1.2 A',
      '1.10 B',
      '2.01 C',
      '11.42 Z',
      'apple',
      'Banana',
    ]);
  });

  test('projects sort favorites first, then A→Z by title', () async {
    final state = await stateWith([]);
    expect(
      state.sortedProjects.map((p) => p.id).toList(),
      [3, 1, 2],
      reason: '1 Personal (fav) first, then 2 Work, 11 Archive',
    );
    state.dispose();
  });

  test('sortMode A→Z orders tasks by title; due date stays the default',
      () async {
    final state = await stateWith([
      taskJson(1, 'Beta task', due: DateTime(2030, 2, 1)),
      taskJson(2, 'Alpha task', due: DateTime(2030, 1, 1)),
    ]);
    await state.select(const ListSelection.smart(SmartList.allTasks));

    expect(state.openTasks.map((t) => t.id).toList(), [2, 1],
        reason: 'default: due date');

    await state.setSortMode(SortMode.alphabetical);
    expect(state.openTasks.map((t) => t.title).toList(),
        ['Alpha task', 'Beta task']);

    await state.setSortMode(SortMode.dueDate);
    expect(state.openTasks.map((t) => t.id).toList(), [2, 1]);
    state.dispose();
  });
}