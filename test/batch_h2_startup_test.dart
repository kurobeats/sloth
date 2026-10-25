import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/main.dart';
import 'package:sloth/models.dart';
import 'package:sloth/notifications_service.dart';
import 'package:sloth/screens/task_detail_screen.dart';
import 'package:sloth/state.dart';

/// Startup: what the widget deep link may open, what the poll waits for, and
/// what the app tears down.
VikunjaApi fakeApi() => VikunjaApi(
  baseUrl: 'https://tasks.example.com',
  client: MockClient((request) async => http.Response('[]', 200)),
);

/// Signed in from the start and never restores: the shell goes straight to the
/// list screen.
class ReadyState extends AppState {
  ReadyState() {
    api = fakeApi();
    user = const VikunjaUser(id: 1, username: 'me');
    restoring = false;
  }

  @override
  Future<void> restore() async {}

  @override
  Future<VikunjaTask?> loadTask(int id) async => null;

  @override
  VikunjaTask? taskById(int id) => null;
}

/// A restore that takes as long as a round trip to a slow server.
class SlowState extends AppState {
  SlowState({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;

  /// How often startup re-read the flag it used to busy-wait on.
  int restoringReads = 0;

  @override
  bool get restoring {
    restoringReads++;
    return super.restoring;
  }

  @override
  Future<void> restore() async {
    await Future<void>.delayed(delay);
    api = fakeApi();
    user = const VikunjaUser(id: 1, username: 'me');
    restoring = false;
    notifyListeners();
  }

  @override
  Future<VikunjaTask?> loadTask(int id) async => null;

  @override
  VikunjaTask? taskById(int id) => null;
}

class CountingNotifications extends NotificationsService {
  CountingNotifications() : super.ready();

  int polls = 0;

  @override
  Future<void> poll(AppState state) async => polls++;
}

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in ['home_widget', 'home_widget/updates']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        return null;
      });
    }
  });

  Future<SlothAppState> pump(
    WidgetTester tester, {
    AppState? state,
    NotificationsService? notifications,
  }) async {
    await tester.pumpWidget(
      SlothApp(state: state, notifications: notifications),
    );
    return tester.state<SlothAppState>(find.byType(SlothApp));
  }

  testWidgets('a widget link with a non-task id opens nothing', (tester) async {
    final app = await pump(tester, state: ReadyState());
    await tester.pump();

    // `push` only completes when the route is popped, so the deliveries are
    // driven without awaiting them.
    unawaited(app.openFromWidget(Uri.parse('sloth://task/0')));
    unawaited(app.openFromWidget(Uri.parse('sloth://task/-5')));
    unawaited(app.openFromWidget(Uri.parse('sloth://task/not-a-number')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TaskDetailScreen), findsNothing);

    unawaited(app.openFromWidget(Uri.parse('sloth://task/42')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TaskDetailScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a widget link that lands before the session is kept', (
    tester,
  ) async {
    final state = SlowState();
    final app = await pump(tester, state: state);
    expect(find.byType(TaskDetailScreen), findsNothing);

    // The tap that started the app arrives while the restore is still running.
    unawaited(app.openFromWidget(Uri.parse('sloth://task/42')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(TaskDetailScreen),
      findsNothing,
      reason: 'the detail screen needs a session to read with',
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(TaskDetailScreen),
      findsOneWidget,
      reason: 'the held link is delivered once the session is up',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('startup waits for the restore and polls exactly once', (
    tester,
  ) async {
    final state = SlowState();
    final notifications = CountingNotifications();
    await pump(tester, state: state, notifications: notifications);

    await tester.pump(const Duration(milliseconds: 100));
    expect(notifications.polls, 0, reason: 'still restoring');
    final reads = state.restoringReads;

    // The rest of the restore: nothing may re-read the flag while it runs.
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      state.restoringReads,
      reads,
      reason: 'startup awaits the ready future, it does not re-read the flag',
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(state.restoring, isFalse);
    expect(notifications.polls, 1, reason: 'the initial poll runs once');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tearing the app down disposes the payload notifier', (
    tester,
  ) async {
    final notifications = NotificationsService.ready();
    final notifier = notifications.tappedPayload;
    await pump(tester, state: ReadyState(), notifications: notifications);
    await tester.pump();

    void listener() {}
    notifier.addListener(listener);
    notifier.removeListener(listener);

    await tester.pumpWidget(const SizedBox());

    expect(() => notifier.addListener(listener), throwsFlutterError);
  });
}
