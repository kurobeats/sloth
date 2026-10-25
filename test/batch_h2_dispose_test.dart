import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';
import 'package:sloth/state.dart';

/// A request that was already in flight when the app state went away must not
/// touch the listener list afterwards: `ChangeNotifier` throws when it is
/// notified after `dispose()`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a refresh that lands after dispose completes without notifying',
    () async {
      final gate = Completer<void>();
      final state = AppState();
      state.api = VikunjaApi(
        baseUrl: 'https://tasks.example.com',
        client: MockClient((request) async {
          await gate.future;
          if (request.url.path.endsWith('/tasks')) {
            return http.Response(
              jsonEncode([
                {'id': 1, 'project_id': 1, 'title': 'Late answer'},
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      state.user = const VikunjaUser(id: 1, username: 'me');

      final refreshing = state.refresh();
      // The screen (and the state behind it) goes away mid-request.
      state.dispose();
      gate.complete();

      await expectLater(refreshing, completes);
    },
  );
}
