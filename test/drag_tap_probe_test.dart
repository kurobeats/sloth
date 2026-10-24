import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which drag wrapper lets a plain tap through to an InkWell underneath?
Widget _card(
  String label, {
  required bool longPress,
  required VoidCallback onTap,
}) {
  Widget inner = const Text('card');
  final content = InkWell(onTap: onTap, child: inner);
  return Material(
    child: longPress
        ? LongPressDraggable<int>(data: 1, feedback: inner, child: content)
        : Draggable<int>(data: 1, feedback: inner, child: content),
  );
}

/// Full board structure: horizontal board > DragTarget column > vertical list
/// > Material/InkWell > Draggable.
Widget _board({required bool longPress, required VoidCallback onTap}) {
  final card = Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      child: InkWell(
        onTap: onTap,
        child: longPress
            ? LongPressDraggable<int>(
                data: 1,
                feedback: const Text('card'),
                child: const Text('card'),
              )
            : Draggable<int>(
                data: 1,
                feedback: const Text('card'),
                child: const Text('card'),
              ),
      ),
    ),
  );
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 500,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            DragTarget<int>(
              onAcceptWithDetails: (_) {},
              builder: (context, a, b) => SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('To-Do'),
                    Expanded(child: ListView(children: [card])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final longPress in [true, false]) {
    testWidgets(
      'board tap fires with ${longPress ? 'LongPress' : 'Draggable'}',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          _board(longPress: longPress, onTap: () => taps++),
        );
        await tester.tap(find.text('card'));
        await tester.pumpAndSettle();
        expect(taps, 1);
      },
    );
  }

  for (final longPress in [true, false]) {
    testWidgets(
      'tap fires with ${longPress ? 'LongPressDraggable' : 'Draggable'}',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Column(
                  children: [
                    _card('a', longPress: longPress, onTap: () => taps++),
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: const Text('x'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('card'));
        await tester.pumpAndSettle();
        expect(taps, 1);
      },
    );
  }
}
