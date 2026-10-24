import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _state.restore();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      // The whole MaterialApp rebuilds so theme/mode changes repaint at once.
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => MaterialApp(
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
