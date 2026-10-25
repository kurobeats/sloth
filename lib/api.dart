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
      ..badCertificateCallback = (cert, host, port) =>
          certHostAllowed(baseUrl, host);
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

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
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
    } on http.ClientException catch (e) {
      throw VikunjaException(
        0,
        'Cannot reach $baseUrl (${e.message}). Edits are disabled offline.',
      );
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
      final batch = await _send(
        'GET',
        path,
        query: {...?query, 'page': page, 'per_page': perPage},
      );
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
    final res = await _send(
      'POST',
      '/login',
      body: {'username': username, 'password': password},
    );
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

  /// Saves the user's general settings and returns the refreshed user.
  Future<VikunjaUser> saveUserSettings(VikunjaUserSettings settings) async {
    await _send('POST', '/user/settings/general', body: settings.toJson());
    return currentUser();
  }

  Future<List<VikunjaProject>> projects() => _list(
    '/projects',
    VikunjaProject.fromJson,
    query: {'is_archived': false},
  );

  Future<VikunjaProject> project(int id) async {
    final res = await _send('GET', '/projects/$id');
    return VikunjaProject.fromJson(res as Map<String, dynamic>);
  }

  Future<List<VikunjaLabel>> labels() =>
      _list('/labels', VikunjaLabel.fromJson);

  Future<VikunjaLabel> createLabel(
    String title, {
    String hexColor = '',
    String description = '',
  }) async {
    final res = await _send(
      'PUT',
      '/labels',
      body: {'title': title, 'hex_color': hexColor, 'description': description},
    );
    return VikunjaLabel.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaLabel> updateLabel(
    VikunjaLabel label, {
    required String title,
    String? hexColor,
    String? description,
  }) async {
    final res = await _send(
      'PUT',
      '/labels/${label.id}',
      body: {
        'id': label.id,
        'title': title,
        'hex_color': hexColor ?? label.hexColor,
        'description': ?description,
      },
    );
    return VikunjaLabel.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteLabel(int id) => _send('DELETE', '/labels/$id');

  /// Replaces the task's labels in one call.
  Future<void> setTaskLabels(int taskId, List<VikunjaLabel> labels) => _send(
    'POST',
    '/tasks/$taskId/labels/bulk',
    body: {
      'labels': [
        for (final label in labels)
          {'id': label.id, 'title': label.title, 'hex_color': label.hexColor},
      ],
    },
  );

  /// Tasks from every project the user can read.
  Future<List<VikunjaTask>> allTasks({
    String? filter,
    String? sortBy = 'due_date',
    String? orderBy = 'asc',
    String? search,
  }) => _list(
    '/tasks',
    VikunjaTask.fromJson,
    query: {
      'filter': ?filter,
      's': ?search,
      'sort_by': sortBy ?? 'due_date',
      'order_by': orderBy ?? 'asc',
    },
  );

  Future<List<VikunjaTask>> projectTasks(
    int projectId,
    int viewId, {
    String? filter,
  }) => _list(
    '/projects/$projectId/views/$viewId/tasks',
    VikunjaTask.fromJson,
    query: {
      'filter': ?filter,
      'sort_by': 'position',
      'order_by': 'asc',
    },
  );

  Future<VikunjaTask> task(int id) async {
    final res = await _send('GET', '/tasks/$id');
    return VikunjaTask.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaTask> createTask(
    int projectId,
    Map<String, dynamic> body,
  ) async {
    final res = await _send('PUT', '/projects/$projectId/tasks', body: body);
    return VikunjaTask.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaTask> updateTask(VikunjaTask task) async {
    final res = await _send('POST', '/tasks/${task.id}', body: task.toJson());
    return VikunjaTask.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteTask(int id) => _send('DELETE', '/tasks/$id');

  /// Kanban columns with their tasks, from the kanban view.
  Future<List<VikunjaBucket>> board(int projectId, int viewId) =>
      _list('/projects/$projectId/views/$viewId/tasks', VikunjaBucket.fromJson);

  Future<void> moveToBucket(
    int projectId,
    int viewId,
    int bucketId,
    int taskId,
  ) => _send(
    'POST',
    '/projects/$projectId/views/$viewId/buckets/$bucketId/tasks',
    body: {'task_id': taskId, 'bucket_id': bucketId},
  );

  Future<List<VikunjaComment>> comments(int taskId) =>
      _list('/tasks/$taskId/comments', VikunjaComment.fromJson);

  Future<void> deleteComment(int taskId, int commentId) =>
      _send('DELETE', '/tasks/$taskId/comments/$commentId');

  Future<void> addAssignee(int taskId, int userId) =>
      _send('PUT', '/tasks/$taskId/assignees', body: {'user_id': userId});

  Future<void> removeAssignee(int taskId, int userId) =>
      _send('DELETE', '/tasks/$taskId/assignees/$userId');

  Future<List<VikunjaAttachment>> attachments(int taskId) async {
    final res = await _send(
      'GET',
      '/tasks/$taskId/attachments',
      query: {'per_page': 50},
    );
    if (res is! List) return const [];
    return res
        .whereType<Map<String, dynamic>>()
        .map(VikunjaAttachment.fromJson)
        .toList();
  }

  /// Uploads one file as a multipart attachment.
  Future<List<VikunjaNotification>> notifications() =>
      _list('/notifications', VikunjaNotification.fromJson);

  /// Marks one notification read (or unread) — `{read: bool}`.
  Future<void> markNotificationRead(int id, {bool read = true}) =>
      _send('POST', '/notifications/$id', body: {'read': read});

  Future<void> uploadAttachment(
    int taskId,
    String filename,
    List<int> bytes,
  ) async {
    final request =
        http.MultipartRequest('PUT', _uri('/tasks/$taskId/attachments'))
          ..headers.addAll({
            'Authorization': 'Bearer ${token ?? ''}',
            'User-Agent': _userAgent,
          });
    request.files.add(
      http.MultipartFile.fromBytes('files', bytes, filename: filename),
    );
    final streamed = await _client.send(request).timeout(_timeout * 6);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) {
      throw VikunjaException(
        res.statusCode,
        _messageFrom(res.bodyBytes) ?? 'Upload failed (${res.statusCode})',
      );
    }
  }

  Future<Uint8List> downloadAttachment(int taskId, int attachmentId) async {
    final req = http.Request(
      'GET',
      _uri('/tasks/$taskId/attachments/$attachmentId'),
    )..headers.addAll(_headers);
    final res = await _client.send(req).timeout(_timeout * 4);
    final bytes = await res.stream.toBytes();
    if (res.statusCode >= 400) {
      throw VikunjaException(
        res.statusCode,
        'Download failed (${res.statusCode})',
      );
    }
    return bytes;
  }

  Future<void> deleteAttachment(int taskId, int attachmentId) =>
      _send('DELETE', '/tasks/$taskId/attachments/$attachmentId');

  /// Relations are returned on the task itself, grouped by relation kind.
  Future<VikunjaTask> taskWithRelations(int id) async {
    final res = await _send('GET', '/tasks/$id');
    return VikunjaTask.fromJson(res as Map<String, dynamic>);
  }

  Future<void> addRelation(int taskId, int otherTaskId, String relationKind) =>
      _send(
        'PUT',
        '/tasks/$taskId/relations',
        body: {'other_task_id': otherTaskId, 'relation_kind': relationKind},
      );

  Future<void> removeRelation(
    int taskId,
    String relationKind,
    int otherTaskId,
  ) => _send('DELETE', '/tasks/$taskId/relations/$relationKind/$otherTaskId');

  String? _messageFrom(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  Future<VikunjaComment> addComment(int taskId, String comment) async {
    final res = await _send(
      'PUT',
      '/tasks/$taskId/comments',
      body: {'comment': comment},
    );
    return VikunjaComment.fromJson(res as Map<String, dynamic>);
  }

  // ------------------------------------------------------------- teams -----

  Future<List<VikunjaTeam>> teams({String? search}) => _list(
    '/teams',
    VikunjaTeam.fromJson,
    query: {if (search != null && search.isNotEmpty) 's': search},
  );

  Future<VikunjaTeam> team(int id) async {
    final res = await _send('GET', '/teams/$id');
    return VikunjaTeam.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaTeam> createTeam(String name, {String? description}) async {
    final res = await _send(
      'PUT',
      '/teams',
      body: {
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
      },
    );
    return VikunjaTeam.fromJson(res as Map<String, dynamic>);
  }

  Future<VikunjaTeam> updateTeam(
    int id, {
    required String name,
    String? description,
  }) async {
    final res = await _send(
      'POST',
      '/teams/$id',
      body: {'id': id, 'name': name, 'description': description ?? ''},
    );
    return VikunjaTeam.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteTeam(int id) => _send('DELETE', '/teams/$id');

  /// Vikunja returns a team's members on the team itself; there is no
  /// GET on /teams/{id}/members.
  Future<List<VikunjaTeamMember>> teamMembers(int teamId) async {
    final team = await this.team(teamId);
    return team.members;
  }

  /// Adds an existing user to a team. Vikunja validates on `username`; the
  /// returned member id is the membership id, not the user id.
  Future<void> addTeamMember(
    int teamId,
    String username, {
    bool admin = false,
  }) => _send(
    'PUT',
    '/teams/$teamId/members',
    body: {'username': username, 'admin': admin},
  );

  Future<void> removeTeamMember(int teamId, String username) => _send(
    'DELETE',
    '/teams/$teamId/members/${Uri.encodeComponent(username)}',
  );

  Future<void> toggleTeamMemberAdmin(int teamId, String username) => _send(
    'POST',
    '/teams/$teamId/members/${Uri.encodeComponent(username)}/admin',
  );

  // --------------------------------------------------------- project shares --

  Future<List<VikunjaProjectShare>> projectTeams(int projectId) async {
    final res = await _send(
      'GET',
      '/projects/$projectId/teams',
      query: {'per_page': 50},
    );
    if (res is! List) return const [];
    return res
        .whereType<Map<String, dynamic>>()
        .map(VikunjaProjectShare.fromTeam)
        .toList();
  }

  Future<List<VikunjaProjectShare>> projectUsers(int projectId) async {
    final res = await _send(
      'GET',
      '/projects/$projectId/users',
      query: {'per_page': 50},
    );
    if (res is! List) return const [];
    return res
        .whereType<Map<String, dynamic>>()
        .map(VikunjaProjectShare.fromUser)
        .toList();
  }

  Future<void> addProjectTeam(int projectId, int teamId, int permission) =>
      _send(
        'PUT',
        '/projects/$projectId/teams',
        body: {'team_id': teamId, 'permission': permission},
      );

  Future<void> updateProjectTeam(int projectId, int teamId, int permission) =>
      _send(
        'POST',
        '/projects/$projectId/teams/$teamId',
        body: {'team_id': teamId, 'permission': permission},
      );

  Future<void> removeProjectTeam(int projectId, int teamId) =>
      _send('DELETE', '/projects/$projectId/teams/$teamId');

  Future<void> addProjectUser(int projectId, int userId, int permission) =>
      _send(
        'PUT',
        '/projects/$projectId/users',
        body: {'user_id': userId, 'permission': permission},
      );

  Future<void> updateProjectUser(int projectId, int userId, int permission) =>
      _send(
        'POST',
        '/projects/$projectId/users/$userId',
        body: {'user_id': userId, 'permission': permission},
      );

  Future<void> removeProjectUser(int projectId, int userId) =>
      _send('DELETE', '/projects/$projectId/users/$userId');

  Future<List<VikunjaLinkShare>> linkShares(int projectId) async {
    final res = await _send('GET', '/projects/$projectId/shares');
    if (res is! List) return const [];
    return res
        .whereType<Map<String, dynamic>>()
        .map(VikunjaLinkShare.fromJson)
        .toList();
  }

  Future<VikunjaLinkShare> createLinkShare(
    int projectId, {
    required String name,
    required int permission,
    String? password,
  }) async {
    final res = await _send(
      'PUT',
      '/projects/$projectId/shares',
      body: {
        'name': name,
        'permission': permission,
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );
    return VikunjaLinkShare.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteLinkShare(int projectId, int shareId) =>
      _send('DELETE', '/projects/$projectId/shares/$shareId');

  Future<List<VikunjaUser>> users(String query) async {
    final res = await _send('GET', '/users', query: {'s': query});
    if (res is! List) return const [];
    return res
        .whereType<Map<String, dynamic>>()
        .map(VikunjaUser.fromJson)
        .toList();
  }

  Future<VikunjaProject> updateProject(
    VikunjaProject project, {
    String? title,
    String? description,
    String? hexColor,
    String? identifier,
    bool? isFavorite,
    bool? isArchived,
  }) async {
    final res = await _send(
      'POST',
      '/projects/${project.id}',
      body: {
        'id': project.id,
        'title': title ?? project.title,
        'description': description ?? project.description ?? '',
        'hex_color': hexColor ?? project.hexColor,
        'identifier': ?identifier,
        'is_favorite': isFavorite ?? project.isFavorite,
        'is_archived': isArchived ?? project.isArchived,
      },
    );
    return VikunjaProject.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteProject(int id) => _send('DELETE', '/projects/$id');

  Future<String?> frontendUrl() async {
    final info = await this.info();
    final url = info['frontend_url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  Future<VikunjaProject> createProject(String title, {String? hexColor}) async {
    final res = await _send(
      'PUT',
      '/projects',
      body: {'title': title, 'hex_color': ?hexColor},
    );
    return VikunjaProject.fromJson(res as Map<String, dynamic>);
  }

  void close() => _client.close();
}
