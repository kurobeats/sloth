import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';
import '../widgets/task_tile.dart';
import 'task_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<VikunjaTask> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = value.trim();
      if (query.isEmpty) {
        setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      final state = AppScope.of(context);
      try {
        final results = await state.searchTasks(query);
        if (mounted) setState(() => _results = results);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          style: TextStyle(fontSize: TodoText.xl, color: c.primaryText),
          decoration: InputDecoration(
            hintText: 'Search Tasks',
            border: InputBorder.none,
            hintStyle: TextStyle(fontSize: TodoText.xl, color: c.secondaryText),
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? Center(
              child: Text(
                _controller.text.isEmpty
                    ? 'Search your tasks'
                    : 'No tasks found',
                style: TextStyle(
                  color: c.secondaryText,
                  fontSize: TodoText.medium,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final task = _results[i];
                return TaskTile(
                  task: task,
                  project: state.projectOf(task),
                  showProject: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TaskDetailScreen(taskId: task.id, initial: task),
                    ),
                  ),
                  onToggleDone: () => state.toggleDone(task),
                  onToggleStar: () => state.toggleImportant(task),
                );
              },
            ),
    );
  }
}
