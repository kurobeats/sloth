import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';

/// Downloads are bounded and every socket failure reaches the caller as a
/// VikunjaException, like the rest of the client.
void main() {
  test('a body over the transfer cap is rejected, not buffered', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((req) async {
        req.response.statusCode = 200;
        final chunk = List<int>.filled(1024 * 1024, 7);
        try {
          for (
            var i = 0;
            i <= VikunjaApi.maxTransferBytes ~/ chunk.length;
            i++
          ) {
            req.response.add(chunk);
            await req.response.flush();
          }
          await req.response.close();
        } catch (_) {
          // The client hung up once it hit the cap.
        }
      }),
    );
    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'abc';

    await expectLater(
      () => api.downloadAttachment(3, 9),
      throwsA(isA<VikunjaException>()),
    );
    api.close();
    await server.close(force: true);
  });

  test('an oversized content-length is refused up front', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((req) async {
        req.response.statusCode = 200;
        req.response.contentLength = VikunjaApi.maxTransferBytes + 1;
        req.response.add([1, 2, 3]);
        try {
          await req.response.close();
        } catch (_) {}
      }),
    );
    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'abc';

    await expectLater(
      () => api.downloadAttachment(3, 9),
      throwsA(isA<VikunjaException>()),
    );
    api.close();
    await server.close(force: true);
  });

  test('a connection dropped mid-download is a VikunjaException', () async {
    // A raw socket, so the headers can promise a body that never arrives in
    // full: HttpServer refuses to detach after writing headers.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      final socket = await server.first;
      socket.listen((_) {});
      socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n');
      socket.add([1, 2, 3]);
      await socket.flush();
      socket.destroy();
    }());
    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'abc';

    await expectLater(
      () => api.downloadAttachment(3, 9),
      throwsA(isA<VikunjaException>()),
    );
    api.close();
    await server.close();
  });

  test('a connection dropped mid-upload is a VikunjaException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((req) async {
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.destroy();
      }),
    );
    final api = VikunjaApi(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 'abc';

    await expectLater(
      () => api.uploadAttachment(
        3,
        'notes.txt',
        List<int>.filled(1024 * 1024, 65),
      ),
      throwsA(isA<VikunjaException>()),
    );
    api.close();
    await server.close(force: true);
  });
}
