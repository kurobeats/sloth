import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models.dart';

class VikunjaException implements Exception {
  VikunjaException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin Vikunja REST client.
///
/// Auth is JWT bearer (POST /login). Base URL is normalised the same way the
/// official app does it: no trailing slash and no /api/v1 suffix.
class VikunjaApi {
  VikunjaApi({
    required String baseUrl,
    bool allowSelfSigned = false,
    http.Client? client,
  }) : baseUrl = _normalize(baseUrl),
       allowSelfSigned = allowSelfSigned,
       _client = client ?? _defaultClient(baseUrl, allowSelfSigned);

  final String baseUrl;
  final http.Client _client;
  final bool allowSelfSigned;

  String? token;

  /// Self-hosted instances often use a private CA (e.g. Caddy's internal
  /// authority). Certificate errors are accepted only for the configured host,
  /// and only when the user opted in for that server.
  static http.Client _defaultClient(String baseUrl, bool allowSelfSigned) {
    if (!allowSelfSigned) return http.Client();
    final inner = HttpClient()
      ..connectionTimeout = _timeout
      ..badCertificateCallback =
          (cert, host, port) => certHostAllowed(baseUrl, host);
    return IOClient(inner);
  }

  /// True only when [host] is the configured server's host.
  static bool certHostAllowed(String baseUrl, String host) {
    final configured = Uri.tryParse(baseUrl)?.host;
    return configured != null && configured == host;
  }

  static const _timeout = Duration(seconds: 20);
  static const _userAgent = 'Sloth/1.0 (+https://github.com/kurobeats/sloth)';

  static String _normalize(String raw) {
    var b = raw.replaceAll(RegExp(r'\s'), '');
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/api/v1')) {
      b = b.substring(0, b.length - '/api/v1'.length);
    }
    if (!b.contains('://')) b = 'https://$b';
    return b;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = query?.map((k, v) => MapEntry(k, v.toString()));
    return Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: q);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'User-Agent': _userAgent,
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? query, Object? body}) async {
    final req = http.Request(method, _uri(path, query))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    try {
      final streamed = await _client.send(req).timeout(_timeout);
      final res = await http.Response.fromStream(streamed);
      final text = utf8.decode(res.bodyBytes);
      dynamic decoded;
      if (text.isNotEmpty) {
        try {
          decoded = jsonDecode(text);
        } catch (_) {
          decoded = text;
        }
      }
      if (res.statusCode >= 400) {
        final msg = decoded is Map && decoded['message'] is String
            ? decoded['message'] as String
            : 'Request failed (${res.statusCode})';
        throw VikunjaException(res.statusCode, msg);
      }
      return decoded;
    } on TimeoutException {
      throw VikunjaException(0, 'Server did not respond in time');
    } on SocketException catch (e) {
      throw VikunjaException(0, 'Cannot reach $baseUrl (${e.message})');
    } on HandshakeException catch (e) {
      throw VikunjaException(
        0,
        e.message.contains('CERTIFICATE_VERIFY_FAILED')
            ? 'TLS certificate not trusted. If this server uses a self-signed '
                'certificate, enable "Allow self-signed certificate" and retry.'
            : 'TLS handshake failed: ${e.message}',
      );
    }
  }

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, dynamic>? query,
    int perPage = 50,
  }) async {
    final out = <T>[];
    var page = 1;
    while (true) {
      final batch = await _send('GET', path, query: {
        ...?query,
        'page': page,
        'per_page': perPage,
      });
      if (batch is! List) break;
      out.addAll(batch.whereType<Map<String, dynamic>>().map(parse));
      if (batch.length < perPage) break;
      page++;
      if (page > 40) break; // shortcut: 2000-item ceiling, paginate further if a user ever needs it
    }
    return out;
  }

  /// Public server info, used to validate a URL before login.
  Future<Map<String, dynamic>> info() async {
    final res = await _send('GET', '/info');
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  Future<String> login(String username, String password) async {
    final res = await _send('POST', '/login',
        body: {'username': username, 'password': password});
    final t = res is Map ? res['token'] as String? : null;
    if (t == null || t.isEmpty) {
      throw VikunjaException(401, 'Login did not return a token');
    }
    token = t;
    return t;
  }

  /// The user's avatar image, or null when they have not uploaded one.
  /// Vikunja serves it at /avatar/{username} (the OpenAPI doc's
  /// /{username}/avatar path is out of date).
  Future<Uint8List?> avatar(String username, {int size = 128}) async {
    final req = http.Request(
      'GET',
      _uri('/avatar/${Uri.encodeComponent(username)}', {'size': size}),
    )..headers.addAll(_headers);
    try {
      final res = await _client.send(req).timeout(_timeout);
      final bytes = await res.stream.toBytes();
      if (res.statusCode >= 400 || bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null; // fall back to initials
    }
  }

  Future<VikunjaUser> currentUser() async {
    final res = await _send('GET', '/user');
    return VikunjaUser.fromJson(res as Map<String, dynamic>);
  }

  Future<List<VikunjaProject>> projects() =>
      _list('/projects', VikunjaProject.fromJson, query: {'is_archived': false});

  Future<VikunjaProject> project(int id) async {
    final res = await _send('GET', '/projects/$id');
    return VikunjaProject.fromJson(res as Map<String, dynamic>);
  }

  Future<List<VikunjaLabel>> labels() => _list('/labels', VikunjaLabel.fromJson);

  /// Tasks from every project the user can read.
  Future<List<VikunjaTask>> allTasks({
    String? filter,
    String? sortBy = 'due_date',
    String? orderBy = 'asc',
    String? search,
  }) =>
      _list('/tasks', VikunjaTask.fromJson, query: {
        if (filter != null) 'filter': filter,
        if (search != null) 's': search,
        'sort_by': sortBy ?? 'due_date',
        'order_by': orderBy ?? 'asc',
      });

  Future<List<VikunjaTask>> projectTasks(int projectId, int viewId,
          {String? filter}) =>
      _list('/projects/$projectId/views/$viewId/tasks', VikunjaTask.fromJson,
          query: {
            if (filter != null) 'filter': filter,
            'sort_by': 'position',
            'order_by': 'asc',
          });

  Future<VikunjaTask> task(int id) async {
    final res = await _send('GET', '/tasks/$id');
    return VikunjaTask.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaTask> createTask(int projectId, Map<String, dynamic> body) async {
    final res = await _send('PUT', '/projects/$projectId/tasks', body: body);
    return VikunjaTask.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaTask> updateTask(VikunjaTask task) async {
    final res = await _send('POST', '/tasks/${task.id}', body: task.toJson());
    return VikunjaTask.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteTask(int id) => _send('DELETE', '/tasks/$id');

  Future<List<VikunjaComment>> comments(int taskId) =>
      _list('/tasks/$taskId/comments', VikunjaComment.fromJson);

  Future<VikunjaComment> addComment(int taskId, String comment) async {
    final res = await _send('PUT', '/tasks/$taskId/comments',
        body: {'comment': comment});
    return VikunjaComment.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaProject> createProject(String title, {String? hexColor}) async {
    final res = await _send('PUT', '/projects', body: {
      'title': title,
      if (hexColor != null) 'hex_color': hexColor,
    });
    return VikunjaProject.fromJson(res as Map<String, dynamic>);
  }

  void close() => _client.close();
}
