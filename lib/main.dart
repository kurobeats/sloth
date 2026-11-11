import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'home_widget_sync.dart';
import 'notifications_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/task_detail_screen.dart';
import 'state.dart';
import 'todo_theme.dart';

void main() => runApp(const SlothApp());

class SlothApp extends StatefulWidget {
  const SlothApp({super.key, this.state, this.notifications});

  /// Test seams: the app otherwise builds its own state and notification
  /// service, and a widget test has neither a session nor a plugin channel.
  final AppState? state;
  final NotificationsService? notifications;

  @override
  State<SlothApp> createState() => SlothAppState();
}

class SlothAppState extends State<SlothApp> with WidgetsBindingObserver {
  static const _shareChannel = MethodChannel('sloth/share');

  /// ACTION_SEND text/plain arrives as "title\nURL"; the add-a-task bar is
  /// single-line, so the shared text becomes one collapsed draft title.
  static final _whitespace = RegExp(r'\s+');
  late final AppState _state = widget.state ?? AppState();
  final _navigator = GlobalKey<NavigatorState>();
  late final NotificationsService _notifications =
      widget.notifications ?? NotificationsService();
  StreamSubscription<Uri?>? _widgetClicks;
  Timer? _poll;
  Future<void>? _pollInFlight;

  /// A widget deep link that arrived before the session was up.
  Uri? _pendingWidgetLink;

  /// The foreground poll timer; null while the app is backgrounded.
  @visibleForTesting
  Timer? get pollTimer => _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifications.tappedPayload.addListener(_openFromNotification);
    // The splash is driven by `AppState.shell`; nothing here has to wait.
    unawaited(_state.restore());
    _widgetClicks = HomeWidget.widgetClicked.listen(openFromWidget);
    _startNotificationPolling();
    // A completed or rescheduled task must not leave its reminder armed until
    // the next poll; arming needs no network, so a change re-arms straight away.
    _state.onTasksChanged = () => unawaited(
      _notifications.rescheduleReminders(
        _state.allTasksForWidget,
        activeScheme(_state),
        _state.clock(),
      ),
    );
    // A tap that started the app arrives once the first frame is up.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(openFromWidget);
    // A share that started the app is only on the platform side once the
    // engine is up, so ask after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_takeSharedText());
    });
  }

  /// Text shared into Sloth from another app (Firefox's share sheet and
  /// friends): ask Android for it, hold it until the session is up, then let
  /// the home screen drop it into the add-a-task bar. Runs on start and on
  /// every resume, so a share into a backgrounded app is picked up too.
  @visibleForTesting
  Future<void> takeSharedText() => _takeSharedText();

  Future<void> _takeSharedText() async {
    String? text;
    try {
      text = await _shareChannel.invokeMethod<String>('getSharedText');
    } on MissingPluginException {
      // Tests run on other platforms: no channel to ask.
      return;
    } on PlatformException catch (_) {
      // A failing engine exchange is a missing share, not an app error.
      return;
    }
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _state.ready;
    if (!mounted || !_state.isSignedIn) return;
    _state.sharedDraft.value = text.trim().replaceAll(_whitespace, ' ');
    _state.newTaskRequests.value++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _notifications.tappedPayload.removeListener(_openFromNotification);
    _notifications.dispose();
    _widgetClicks?.cancel();
    _state.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Vikunja has no push, so the poll is the only source: it costs battery and
    // a request per ten minutes while backgrounded, and the OS may kill the
    // timer anyway. Stop it there, bring it back on resume.
    switch (state) {
      case AppLifecycleState.resumed:
        if (_poll == null) _startNotificationPolling();
        // A share that woke the app from the background lands here.
        unawaited(_takeSharedText());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _poll?.cancel();
        _poll = null;
      case AppLifecycleState.inactive:
        // A pulled-down shade or an incoming call: not backgrounded.
        break;
    }
  }

  /// Poll `/notifications` while the app runs: Vikunja has no push, so a
  /// status-bar notification can only follow a fetch.
  void _startNotificationPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(minutes: 10), (_) => _pollNow());
    _pollNow();
  }

  /// One poll at a time: the foreground timer and the resume handler can both
  /// ask for one, and two of them would read the same feed twice.
  Future<void> _pollNow() =>
      _pollInFlight ??= _runPoll().whenComplete(() => _pollInFlight = null);

  Future<void> _runPoll() async {
    // The restore takes as long as the server takes. Wait on it instead of
    // re-reading its flag every 100 ms.
    await _state.ready;
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

  /// Widget rows deep link to `sloth://task/<id>`, the widget's plus button to
  /// `sloth://new`, and the header sends no target and just opens the app.
  /// Wired to the widget-click stream and the launch intent; tests drive it
  /// directly.
  Future<void> openFromWidget(Uri? uri) async {
    final segments = uri?.pathSegments ?? const <String>[];
    if (uri == null || uri.scheme != 'sloth') return;
    if (uri.host == 'new') {
      if (!_state.isSignedIn) {
        // Held like a task link: the plus tap started the app, so dropping it
        // would lose the bar it asked for.
        _pendingWidgetLink = uri;
        await _state.ready;
        if (!mounted || !_state.isSignedIn || _pendingWidgetLink != uri) return;
        _pendingWidgetLink = null;
      }
      _state.newTaskRequests.value++;
      return;
    }
    if (uri.host != 'task') return;
    // Task ids are positive row ids: 0 and negatives address no task.
    final id = int.tryParse(segments.isEmpty ? '' : segments.last);
    if (id == null || id <= 0) return;
    if (!_state.isSignedIn) {
      // Tapped before the restore finished. Dropping the link loses the tap
      // that started the app, so hold it and deliver it once the session is up.
      _pendingWidgetLink = uri;
      await _state.ready;
      if (!mounted || !_state.isSignedIn || _pendingWidgetLink != uri) return;
      _pendingWidgetLink = null;
    }
    await _navigator.currentState?.push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      // Only the appearance and the session drive the MaterialApp: rebuilding it
      // for a data notification would rebuild the navigator and the route on
      // screen. `AppScope` still repaints the widgets that read task data.
      child: ValueListenableBuilder<AppShell>(
        valueListenable: _state.shell,
        builder: (context, shell, _) => MaterialApp(
          navigatorKey: _navigator,
          title: 'Sloth',
          debugShowCheckedModeBanner: false,
          theme: buildTodoTheme(shell.lightTheme),
          darkTheme: buildTodoTheme(shell.darkTheme),
          themeMode: shell.themeMode,
          home: shell.restoring
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : shell.signedIn
              ? const HomeScreen()
              : const LoginScreen(),
        ),
      ),
    );
  }
}
