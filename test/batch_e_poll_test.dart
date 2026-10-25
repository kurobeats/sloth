import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/main.dart';

/// The ten-minute notification poll has to survive a background/foreground
/// cycle without running in the background.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in ['home_widget', 'home_widget/updates']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        return null;
      });
    }
  });

  testWidgets('the poll stops in the background and restarts on resume', (
    tester,
  ) async {
    await tester.pumpWidget(const SlothApp());
    await tester.pump(const Duration(milliseconds: 300));

    final state = tester.state<SlothAppState>(find.byType(SlothApp));
    expect(state.pollTimer?.isActive, isTrue, reason: 'foreground: polling');

    // Android walks resumed -> inactive -> hidden -> paused.
    for (final step in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(step);
    }
    await tester.pump();
    expect(
      state.pollTimer?.isActive ?? false,
      isFalse,
      reason: 'a backgrounded app must not poll every ten minutes',
    );

    for (final step in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(step);
    }
    await tester.pump();
    expect(state.pollTimer?.isActive, isTrue, reason: 'the timer comes back');

    // Lets the poll's own "wait for the session" delay run out.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
  });
}
