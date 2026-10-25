import 'package:flutter/material.dart';

import '../todo_theme.dart';
import 'unsaved_changes.dart';

/// The "Add a task" bar pinned to the bottom of the list: hollow circle,
/// hint text and a submit icon.
class EntryBar extends StatefulWidget {
  const EntryBar({
    super.key,
    required this.onSubmit,
    this.projectName,
    this.hint = 'Add a new task…',
    this.enabled = true,
    this.disabledHint,
  });

  /// Resolves to true when the task reached the server. The bar clears the draft
  /// only then, so a rejected add keeps what the user typed.
  final Future<bool> Function(String title) onSubmit;
  final String? projectName;
  final String hint;
  final bool enabled;
  final String? disabledHint;

  @override
  State<EntryBar> createState() => _EntryBarState();
}

class _EntryBarState extends State<EntryBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  /// Whether the bar holds a draft; the back guard follows this.
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncDraft);
  }

  void _syncDraft() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText == _hasText) return;
    _hasText = hasText;
    if (mounted) setState(() {});
  }

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
    var landed = false;
    try {
      landed = await widget.onSubmit(title);
    } catch (_) {
      // The caller surfaces its own error; the text stays for a retry.
    }
    if (mounted) {
      // Only clear once the add landed, so a failed one keeps the draft.
      if (landed) _controller.clear();
      setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final bar = Container(
      decoration: BoxDecoration(
        color: c.primaryBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: c.brightness == Brightness.dark ? 0.5 : 0.08,
            ),
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
              Icon(
                Icons.radio_button_unchecked,
                size: 20,
                color: c.secondaryText,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  style: TextStyle(
                    fontSize: TodoText.big,
                    color: c.primaryText,
                  ),
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _submit(),
                  enabled: widget.enabled,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.enabled
                        ? widget.hint
                        : (widget.disabledHint ?? widget.hint),
                    hintStyle: TextStyle(
                      fontSize: TodoText.big,
                      color: c.secondaryText,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: (_busy || !widget.enabled) ? null : _submit,
                icon: Icon(Icons.arrow_upward_rounded, color: c.accent),
                tooltip: 'Add',
              ),
            ],
          ),
        ),
      ),
    );
    // The bar is the only place a typed task lives before it is added: a back
    // press that leaves the screen would throw it away without a word.
    return UnsavedChangesGuard(
      dirty: _hasText,
      message: 'The task you typed has not been added yet.',
      child: bar,
    );
  }
}
