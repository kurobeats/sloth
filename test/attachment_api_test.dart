import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';

/// One-shot server answering [status] with a small JSON body.
Future<({String base, Future<void> done})> serve(int status) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final done = server.first.then((req) async {
    await utf8.decodeStream(req);
    req.response
      ..statusCode = status
      ..write(status >= 400 ? '{"message":"nope"}' : '{}');
    await req.response.close();
    await server.close();
  });
  return (base: 'http://127.0.0.1:${server.port}', done: done);
}

void main() {
  test('upload sends one multipart file in the "files" field', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late String received;
    late String type;
    final request = server.first.then((req) async {
      type = req.headers.contentType?.mimeType ?? '';
      received = await utf8.decodeStream(req);
      req.response.statusCode = 200;
      req.response.write('{}');
      await req.response.close();
    });

    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'abc';
    await api.uploadAttachment(3, 'chain-notes.txt', utf8.encode('grease it'));
    await request;
    await server.close();

    expect(type, 'multipart/form-data');
    expect(received, contains('name="files"'));
    expect(received, contains('filename="chain-notes.txt"'));
    expect(received, contains('grease it'));
  });

  test('upload surfaces the server message', () async {
    final server = await serve(400);
    final api = VikunjaApi(baseUrl: server.base)..token = 'abc';

    await expectLater(
      () => api.uploadAttachment(3, 'x.txt', [1, 2, 3]),
      throwsA(
        isA<VikunjaException>().having((e) => e.message, 'message', 'nope'),
      ),
    );
    await server.done;
  });

  test('download returns the raw bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final request = server.first.then((req) async {
      req.response
        ..statusCode = 200
        ..add([1, 2, 3, 4]);
      await req.response.close();
    });
    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'abc';

    final bytes = await api.downloadAttachment(3, 9);
    await request;
    await server.close();

    expect(bytes, [1, 2, 3, 4]);
  });
}
