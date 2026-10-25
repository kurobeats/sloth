import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/screens/account_settings_screen.dart';
import 'package:sloth/state.dart';
import 'package:sloth/todo_theme.dart';

/// A root [Navigator] whose `push` future the test finishes by hand, so the
/// screen can be unmounted before the awaited picker "returns".
class SpyNavigator extends Navigator {
  const SpyNavigator({super.key, required super.onGenerateRoute});

  @override
  NavigatorState createState() => SpyNavigatorState();
}

class SpyNavigatorState extends NavigatorState {
  bool intercept = false;
  Completer<Object?>? pending;

  @override
  Future<T?> push<T extends Object?>(Route<T> route) {
    if (!intercept) return super.push(route);
    final completer = Completer<Object?>();
    pending = completer;
    return completer.future.then((value) => value as T?);
  }
}

void main() {
  testWidgets('a time picker answer landing after the screen closes is dropped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState();
    final navKey = GlobalKey<SpyNavigatorState>();
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: Localizations(
          locale: const Locale('en'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ScaffoldMessenger(
              child: SpyNavigator(
                key: navKey,
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => Theme(
                    data: buildTodoTheme(TodoColors.gruvboxLight),
                    child: const AccountSettingsScreen(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final nav = navKey.currentState!..intercept = true;
    await tester.tap(find.text('Reminder time'));
    await tester.pump();
    expect(nav.pending, isNotNull, reason: 'the time picker was opened');

    // The screen goes away while the picker is still open.
    await tester.pumpWidget(const SizedBox());
    nav.pending!.complete(const TimeOfDay(hour: 8, minute: 30));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
