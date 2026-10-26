import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Guards a route that holds text the user has not committed yet: the system
/// back gesture asks before it throws the draft away.
///
/// The first back press with something to lose asks; confirming (the Discard
/// button, or a second back press after staying) leaves, and cancelling keeps
/// the screen and the text. With nothing to lose ([dirty] false) back leaves
/// immediately, exactly as before.
///
/// The guard registers with the enclosing [ModalRoute] wherever it sits, so a
/// text field can carry its own guard without the screen having to pass state
/// up. On the root route there is no route to pop: leaving means the app goes
/// away, which is what the back button would have done anyway.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.message = 'Your changes have not been saved yet.',
    this.onDiscard,
    this.onLeave,
  });

  final bool dirty;
  final Widget child;
  final String message;

  /// Called when the user confirms leaving without the draft, before the route
  /// goes: a screen that would otherwise flush the text on the way out can drop
  /// it instead.
  final VoidCallback? onDiscard;

  /// Takes over leaving the root route: the list screen turns a discarded draft
  /// into "back to Due Today", the way a plain back press does. Without it the
  /// root route closes the app.
  final Future<void> Function()? onLeave;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  /// Already asked once and the user chose to stay: the next back press
  /// confirms, so nobody is trapped behind a dialog they keep dismissing.
  bool _warned = false;

  /// Set while the leave is under way: asking the route to pop re-enters this
  /// guard's callback, which must not ask again.
  bool _leaving = false;

  Future<void> _onBack() async {
    if (_warned) {
      await _leave();
      return;
    }
    _warned = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(widget.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    widget.onDiscard?.call();
    final navigator = Navigator.of(context);
    if (widget.onLeave != null) {
      await widget.onLeave!();
    } else if (navigator.canPop()) {
      navigator.pop();
    } else {
      // The list screen is the root route: back there closes the app.
      await SystemNavigator.pop();
    }
    _leaving = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.dirty,
      onPopInvokedWithResult: (didPop, _) {
        // A route refuses a pop as a whole: another guard on the same route can
        // be the one saying no, and a clean bar has nothing to ask about.
        if (didPop || _leaving || !widget.dirty) return;
        _onBack();
      },
      child: widget.child,
    );
  }
}
