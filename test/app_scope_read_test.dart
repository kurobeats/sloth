import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/state.dart';

/// `AppScope.of` subscribes the calling widget to every AppState notification.
/// `AppScope.read` is the one-shot accessor for callbacks and lookups: it must
/// not resubscribe, or a data change rebuilds the whole tree.
void main() {
  testWidgets('read() does not subscribe, of() does', (tester) async {
    final state = AppState();
    var readBuilds = 0;
    var ofBuilds = 0;

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Column(
            children: [
              Builder(
                builder: (context) {
                  AppScope.read(context);
                  readBuilds++;
                  return const SizedBox.shrink();
                },
              ),
              Builder(
                builder: (context) {
                  AppScope.of(context);
                  ofBuilds++;
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
    expect(readBuilds, 1);
    expect(ofBuilds, 1);

    state.notifyListeners();
    await tester.pump();

    expect(ofBuilds, 2, reason: 'of() is the listening accessor');
    expect(
      readBuilds,
      1,
      reason: 'read() called in build must not resubscribe the widget',
    );
  });
}
