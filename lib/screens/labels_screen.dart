import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../todo_theme.dart';

/// Vikunja labels: list, create, edit and delete.
class LabelsScreen extends StatelessWidget {
  const LabelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = TodoColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Labels')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        tooltip: 'New label',
        onPressed: () => _edit(context, state, null),
        child: const Icon(Icons.add),
      ),
      body: state.labels.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
              children: [
                Icon(Icons.label_outline, size: 56, color: c.secondaryText),
                const SizedBox(height: 20),
                Text(
                  'No labels yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: TodoText.xl, color: c.primaryText),
                ),
                const SizedBox(height: 8),
                Text(
                  'Labels tag tasks across projects and get their own list here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: TodoText.medium,
                    color: c.secondaryText,
                  ),
                ),
              ],
            )
          : ListView.separated(
              itemCount: state.labels.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.divider),
              itemBuilder: (context, i) {
                final label = state.labels[i];
                return ListTile(
                  leading: Icon(
                    Icons.label,
                    color: TodoColors.serverColor(label.hexColor, c),
                  ),
                  title: Text(
                    label.title,
                    style: TextStyle(color: c.primaryText),
                  ),
                  subtitle: Text(
                    '${state.countForTag(label)} open tasks',
                    style: TextStyle(fontSize: 12, color: c.secondaryText),
                  ),
                  onTap: () => _edit(context, state, label),
                );
              },
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    AppState state,
    VikunjaLabel? label,
  ) async {
    final title = TextEditingController(text: label?.title ?? '');
    final description = TextEditingController();
    final scheme = TodoColors.of(context);
    final swatches = TodoColors.swatches(scheme);
    var selected = label == null || label.hexColor.isEmpty
        ? swatches.first
        : TodoColors.serverColor(label.hexColor, scheme);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(label == null ? 'New label' : 'Edit label'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: title,
                  autofocus: label == null,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final swatch in swatches)
                      GestureDetector(
                        onTap: () => setLocal(() => selected = swatch),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: swatch,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: swatch == selected
                                  ? TodoColors.of(context).primaryText
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (label != null)
              TextButton(
                onPressed: () async {
                  final error = await state.deleteLabel(label);
                  if (context.mounted) {
                    Navigator.pop(context, false);
                    if (error != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error)));
                    }
                  }
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final hex =
        '#${(selected.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final error = label == null
        ? await state.createLabel(
            title.text.trim(),
            hexColor: hex,
            description: description.text.trim(),
          )
        : await state.updateLabel(
            label,
            title: title.text.trim(),
            hexColor: hex,
            description: description.text.trim(),
          );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Label picker for a task: toggles labels on it via the bulk endpoint.
Future<void> showLabelPicker(
  BuildContext context,
  AppState state,
  VikunjaTask task,
) async {
  final selected = {for (final label in task.labels) label.id};

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        final c = TodoColors.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Labels',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.primaryText,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
              if (state.labels.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Create a label first',
                    style: TextStyle(color: c.secondaryText),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final label in state.labels)
                      CheckboxListTile(
                        value: selected.contains(label.id),
                        activeColor: c.accent,
                        checkColor: c.onAccent,
                        secondary: Icon(
                          Icons.label,
                          color: TodoColors.serverColor(label.hexColor, c),
                        ),
                        title: Text(
                          label.title,
                          style: TextStyle(color: c.primaryText),
                        ),
                        onChanged: (value) => setLocal(() {
                          if (value == true) {
                            selected.add(label.id);
                          } else {
                            selected.remove(label.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  if (confirmed != true) return;
  final labels = state.labels.where((l) => selected.contains(l.id)).toList();
  final error = await state.setTaskLabels(task, labels);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
