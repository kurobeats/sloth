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
  String? _error;

  /// Identifies the newest query, so a slower answer to an older one is dropped.
  int _seq = 0;

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
      if (!mounted) return;
      if (query.isEmpty) {
        setState(() {
          _results = const [];
          _error = null;
        });
        return;
      }
      final seq = ++_seq;
      setState(() {
        _searching = true;
        _error = null;
      });
      final state = AppScope.of(context);
      try {
        final results = await state.searchTasks(query);
        if (!mounted || seq != _seq) return;
        setState(() => _results = results);
      } catch (e) {
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = const [];
          _error = '$e';
        });
      } finally {
        if (mounted && seq == _seq) setState(() => _searching = false);
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
      body: SafeArea(
        top: false,
        child: _searching
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.overdue, fontSize: TodoText.medium),
                ),
              )
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
      ),
    );
  }
}
