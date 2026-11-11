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
    final draft = await showDialog<_LabelDraft>(
      context: context,
      builder: (_) => _LabelDialog(state: state, label: label),
    );
    if (draft == null || label == null && draft.title.isEmpty) return;
    final error = label == null
        ? await state.createLabel(
            draft.title,
            hexColor: draft.hexColor,
            description: draft.description,
          )
        : await state.updateLabel(
            label,
            title: draft.title,
            hexColor: draft.hexColor,
            description: draft.description,
          );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// What the dialog returns: the trimmed fields and the picked colour.
class _LabelDraft {
  const _LabelDraft(this.title, this.description, this.hexColor);

  final String title;
  final String description;
  final String hexColor;
}

/// Create or edit a label. Owns its controllers so they die with the dialog.
class _LabelDialog extends StatefulWidget {
  const _LabelDialog({required this.state, this.label});

  final AppState state;
  final VikunjaLabel? label;

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;

  /// Null until a swatch is tapped; the initial colour follows the theme.
  Color? _picked;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.label?.title ?? '');
    _description = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final hex = TodoColors.toHex(
      _picked ?? _initialColour(TodoColors.of(context)),
    );
    Navigator.pop(
      context,
      _LabelDraft(_title.text.trim(), _description.text.trim(), hex),
    );
  }

  Color _initialColour(TodoColors c) {
    final label = widget.label;
    if (label == null || label.hexColor.isEmpty) {
      return TodoColors.swatches(c).first;
    }
    return TodoColors.serverColor(label.hexColor, c);
  }

  Future<void> _delete(AppState state) async {
    final label = widget.label!;
    final error = await state.deleteLabel(label);
    if (!mounted) return;
    Navigator.pop(context);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final c = TodoColors.of(context);
    final swatches = TodoColors.swatches(c);
    final selected = _picked ?? _initialColour(c);

    return AlertDialog(
      title: Text(label == null ? 'New label' : 'Edit label'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              autofocus: label == null,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final swatch in swatches)
                  GestureDetector(
                    onTap: () => setState(() => _picked = swatch),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: swatch == selected
                              ? c.primaryText
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
            onPressed: () => _delete(widget.state),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(label == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// Opens the create dialog from inside the task label picker and leaves the
/// new label ticked, so Apply attaches it to the task without extra taps.
Future<void> _createLabel(
  BuildContext context,
  AppState state,
  Set<int> selected,
  void Function(void Function()) setLocal,
) async {
  final before = {for (final label in state.labels) label.id};
  final draft = await showDialog<_LabelDraft>(
    context: context,
    builder: (_) => _LabelDialog(state: state, label: null),
  );
  if (draft == null || draft.title.isEmpty) return;
  final error = await state.createLabel(
    draft.title,
    hexColor: draft.hexColor,
    description: draft.description,
  );
  if (error != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    return;
  }
  // createLabel appends to state.labels; tick everything that is new.
  setLocal(
    () => selected.addAll([
      for (final label in state.labels)
        if (!before.contains(label.id)) label.id,
    ]),
  );
}

/// Label picker for a task: toggles labels on it via the bulk endpoint.
Future<void> showLabelPicker(
  BuildContext context,
  AppState state,
  VikunjaTask task,
) async {
  final selected = {for (final label in task.labels) label.id};

  // Creating a label notifies [state], so the sheet must listen or the new
  // label would only appear after it is closed and reopened.
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
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
                      ListTile(
                        leading: Icon(Icons.add, color: c.accent),
                        title: Text(
                          'New label',
                          style: TextStyle(color: c.accent),
                        ),
                        onTap: () =>
                            _createLabel(context, state, selected, setLocal),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  if (confirmed != true) return;
  final labels = state.labels.where((l) => selected.contains(l.id)).toList();
  final error = await state.setTaskLabels(task, labels);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
