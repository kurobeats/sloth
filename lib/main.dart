import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'notifications_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/task_detail_screen.dart';
import 'state.dart';
import 'todo_theme.dart';

void main() => runApp(const SlothApp());

class SlothApp extends StatefulWidget {
  const SlothApp({super.key});

  @override
  State<SlothApp> createState() => _SlothAppState();
}

class _SlothAppState extends State<SlothApp> {
  final AppState _state = AppState();
  final _navigator = GlobalKey<NavigatorState>();
  final _notifications = NotificationsService();
  StreamSubscription<Uri?>? _widgetClicks;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _notifications.tappedPayload.addListener(_openFromNotification);
    _state.restore();
    _widgetClicks = HomeWidget.widgetClicked.listen(_openFromWidget);
    _startNotificationPolling();
    // A tap that started the app arrives once the first frame is up.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _notifications.tappedPayload.removeListener(_openFromNotification);
    _widgetClicks?.cancel();
    _state.dispose();
    super.dispose();
  }

  /// Poll `/notifications` while the app runs: Vikunja has no push, so a
  /// status-bar notification can only follow a fetch.
  void _startNotificationPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(minutes: 10), (_) => _pollNow());
    _pollNow();
  }

  Future<void> _pollNow() async {
    for (var i = 0; i < 40 && (_state.restoring || !_state.isSignedIn); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_state.restoring && !_state.isSignedIn) return;
    }
    if (!mounted || !_state.isSignedIn) return;
    await _notifications.init();
    await _notifications.poll(_state);
  }

  /// A status-bar notification carries `task:<id>`.
  Future<void> _openFromNotification() async {
    final payload = _notifications.tappedPayload.value;
    _notifications.tappedPayload.value = null;
    final id = int.tryParse((payload ?? '').split(':').last);
    if (payload == null || id == null || !mounted || !_state.isSignedIn) return;
    await _navigator.currentState?.push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)),
    );
  }

  /// Widget rows deep link to `sloth://task/<id>`; the header sends no task and
  /// just opens the app.
  Future<void> _openFromWidget(Uri? uri) async {
    final segments = uri?.pathSegments ?? const <String>[];
    if (uri == null || uri.scheme != 'sloth' || uri.host != 'task') return;
    final id = int.tryParse(segments.isEmpty ? '' : segments.last);
    if (id == null) return;
    // Wait for the session, so the detail screen has an account to read with.
    for (var i = 0; i < 40 && _state.restoring; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || !_state.isSignedIn) return;
    await _navigator.currentState?.push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      // The whole MaterialApp rebuilds so theme/mode changes repaint at once.
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigator,
          title: 'Sloth',
          debugShowCheckedModeBanner: false,
          theme: buildTodoTheme(_state.lightTheme),
          darkTheme: buildTodoTheme(_state.darkTheme),
          themeMode: _state.themeMode,
          home: _state.restoring
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _state.isSignedIn
              ? const HomeScreen()
              : const LoginScreen(),
        ),
      ),
    );
  }
}
