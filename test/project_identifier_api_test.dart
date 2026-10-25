import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';
import 'package:sloth/models.dart';

/// Vikunja clears a project's identifier when the update body leaves the key
/// out. The app used to omit it whenever the field was empty, so saving a
/// project (or just toggling Favorite) silently wiped the identifier.
void main() {
  test('an update that does not manage the identifier keeps it', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? sent;
    final done = () async {
      await for (final req in server) {
        sent = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({'id': 3, 'title': 'Home', 'identifier': 'HOME'}),
        );
        await req.response.close();
      }
    }();

    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'tk';
    await api.updateProject(
      const VikunjaProject(id: 3, title: 'Home', identifier: 'HOME'),
      title: 'Maison',
    );
    api.close();
    await server.close();
    await done;

    expect(sent?['identifier'], 'HOME');
    expect(sent?['title'], 'Maison');
  });

  test('an explicit empty identifier clears it', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? sent;
    final done = () async {
      await for (final req in server) {
        sent = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'id': 3, 'title': 'Home'}));
        await req.response.close();
      }
    }();

    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'tk';
    await api.updateProject(
      const VikunjaProject(id: 3, title: 'Home', identifier: 'HOME'),
      title: 'Home',
      identifier: '',
    );
    api.close();
    await server.close();
    await done;

    expect(sent?['identifier'], '');
  });
}
