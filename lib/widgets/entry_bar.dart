import 'package:flutter/material.dart';

import '../todo_theme.dart';

/// The "Add a task" bar pinned to the bottom of the list: hollow circle,
/// hint text and a submit icon.
class EntryBar extends StatefulWidget {
  const EntryBar({
    super.key,
    required this.onSubmit,
    this.projectName,
    this.hint = 'Add a new task…',
  });

  final Future<void> Function(String title) onSubmit;
  final String? projectName;
  final String hint;

  @override
  State<EntryBar> createState() => _EntryBarState();
}

class _EntryBarState extends State<EntryBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    _controller.clear();
    await widget.onSubmit(title);
    if (mounted) {
      setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.primaryBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.brightness == Brightness.dark ? 0.5 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Icon(Icons.radio_button_unchecked,
                  size: 20, color: c.secondaryText),
              const SizedBox(width: 20),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  style: TextStyle(fontSize: TodoText.big, color: c.primaryText),
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      fontSize: TodoText.big,
                      color: c.secondaryText,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : _submit,
                icon: Icon(Icons.arrow_upward_rounded, color: c.accent),
                tooltip: 'Add',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
