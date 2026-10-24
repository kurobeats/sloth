/// Vikunja API models (v2.x). Only the fields this app reads or writes.
///
/// Vikunja serialises unset dates as the zero time ("0001-01-01T00:00:00Z"),
/// so every date goes through [_date] which turns that into null.
library;

DateTime? _date(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s)?.toLocal();
  if (parsed == null || parsed.year <= 1) return null;
  return parsed;
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

String _hex(dynamic v) {
  final s = (_str(v) ?? '').trim();
  if (s.isEmpty) return '';
  return s.startsWith('#') ? s : '#$s';
}

class VikunjaUser {
  const VikunjaUser({
    required this.id,
    required this.username,
    this.name,
    this.email,
  });

  final int id;
  final String username;
  final String? name;
  final String? email;

  String get displayName => name ?? username;

  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters(1);
    return parts.first.characters(1) + parts.last.characters(1);
  }

  factory VikunjaUser.fromJson(Map<String, dynamic> j) => VikunjaUser(
    id: j['id'] as int,
    username: j['username'] as String? ?? '',
    name: _str(j['name']),
    email: _str(j['email']),
  );
}

extension on String {
  String characters(int n) => substring(0, length < n ? length : n).toUpperCase();
}

class VikunjaLabel {
  const VikunjaLabel({
    required this.id,
    required this.title,
    required this.hexColor,
  });

  final int id;
  final String title;
  final String hexColor;

  factory VikunjaLabel.fromJson(Map<String, dynamic> j) => VikunjaLabel(
    id: j['id'] as int? ?? 0,
    title: j['title'] as String? ?? '',
    hexColor: _hex(j['hex_color']),
  );
}

class VikunjaReminder {
  const VikunjaReminder({required this.reminder});

  final DateTime reminder;

  factory VikunjaReminder.fromJson(Map<String, dynamic> j) =>
      VikunjaReminder(reminder: _date(j['reminder']) ?? DateTime(2001));

  Map<String, dynamic> toJson() => {'reminder': reminder.toUtc().toIso8601String()};
}

class VikunjaView {
  const VikunjaView({
    required this.id,
    required this.title,
    required this.viewKind,
  });

  final int id;
  final String title;
  final String viewKind;

  bool get isList => viewKind == 'list';

  factory VikunjaView.fromJson(Map<String, dynamic> j) => VikunjaView(
    id: j['id'] as int? ?? 0,
    title: j['title'] as String? ?? '',
    viewKind: j['view_kind'] as String? ?? 'list',
  );
}

class VikunjaProject {
  const VikunjaProject({
    required this.id,
    required this.title,
    this.description,
    this.hexColor = '#1174E4',
    this.isFavorite = false,
    this.isArchived = false,
    this.views = const [],
    this.position = 0,
  });

  final int id;
  final String title;
  final String? description;
  final String hexColor;
  final bool isFavorite;
  final bool isArchived;
  final List<VikunjaView> views;
  final double position;

  /// Preferred view for plain task listing.
  int? get listViewId {
    final list = views.where((v) => v.isList).toList();
    return (list.isNotEmpty ? list.first : (views.isNotEmpty ? views.first : null))
        ?.id;
  }

  factory VikunjaProject.fromJson(Map<String, dynamic> j) => VikunjaProject(
    id: j['id'] as int,
    title: j['title'] as String? ?? '',
    description: _str(j['description']),
    hexColor: _hex(j['hex_color']),
    isFavorite: j['is_favorite'] as bool? ?? false,
    isArchived: j['is_archived'] as bool? ?? false,
    position: (j['position'] as num?)?.toDouble() ?? 0,
    views: (j['views'] as List? ?? const [])
        .map((e) => VikunjaView.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class VikunjaTask {
  VikunjaTask({
    required this.id,
    required this.projectId,
    required this.title,
    this.description,
    this.done = false,
    this.doneAt,
    this.dueDate,
    this.startDate,
    this.endDate,
    this.priority = 0,
    this.isFavorite = false,
    this.percentDone = 0,
    this.labels = const [],
    this.assignees = const [],
    this.reminders = const [],
    this.repeatAfter = 0,
    this.repeatMode = 0,
    this.hexColor,
    this.identifier,
    this.created,
    this.updated,
    this.position = 0,
    this.commentCount = 0,
  });

  final int id;
  final int projectId;
  String title;
  String? description;
  bool done;
  DateTime? doneAt;
  DateTime? dueDate;
  DateTime? startDate;
  DateTime? endDate;
  int priority;
  bool isFavorite;
  double percentDone;
  List<VikunjaLabel> labels;
  List<VikunjaUser> assignees;
  List<VikunjaReminder> reminders;
  int repeatAfter;
  int repeatMode;
  final String? hexColor;
  final String? identifier;
  final DateTime? created;
  final DateTime? updated;
  final double position;
  final int commentCount;

  bool get isOverdue =>
      !done && dueDate != null && dueDate!.isBefore(DateTime.now());

  bool get isDueToday {
    if (dueDate == null) return false;
    final n = DateTime.now();
    return dueDate!.year == n.year &&
        dueDate!.month == n.month &&
        dueDate!.day == n.day;
  }

  String get shortIdentifier => identifier ?? '';

  factory VikunjaTask.fromJson(Map<String, dynamic> j) => VikunjaTask(
    id: j['id'] as int? ?? 0,
    projectId: j['project_id'] as int? ?? 0,
    title: j['title'] as String? ?? '',
    description: _str(j['description']),
    done: j['done'] as bool? ?? false,
    doneAt: _date(j['done_at']),
    dueDate: _date(j['due_date']),
    startDate: _date(j['start_date']),
    endDate: _date(j['end_date']),
    priority: (j['priority'] as num?)?.toInt() ?? 0,
    isFavorite: j['is_favorite'] as bool? ?? false,
    percentDone: (j['percent_done'] as num?)?.toDouble() ?? 0,
    repeatAfter: (j['repeat_after'] as num?)?.toInt() ?? 0,
    repeatMode: (j['repeat_mode'] as num?)?.toInt() ?? 0,
    hexColor: _str(j['hex_color']),
    identifier: _str(j['identifier']),
    created: _date(j['created']),
    updated: _date(j['updated']),
    position: (j['position'] as num?)?.toDouble() ?? 0,
    commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
    labels: (j['labels'] as List? ?? const [])
        .map((e) => VikunjaLabel.fromJson(e as Map<String, dynamic>))
        .toList(),
    assignees: (j['assignees'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VikunjaUser.fromJson)
        .toList(),
    reminders: (j['reminders'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VikunjaReminder.fromJson)
        .toList(),
  );

  /// Body for POST /tasks/{id}: the server treats absent fields as unchanged,
  /// but nested collections are replaced wholesale when present.
  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'title': title,
    'description': description ?? '',
    'done': done,
    if (doneAt != null) 'done_at': doneAt!.toUtc().toIso8601String(),
    'due_date': dueDate?.toUtc().toIso8601String() ?? DateTime.utc(1).toIso8601String(),
    'start_date': startDate?.toUtc().toIso8601String() ?? DateTime.utc(1).toIso8601String(),
    'end_date': endDate?.toUtc().toIso8601String() ?? DateTime.utc(1).toIso8601String(),
    'priority': priority,
    'is_favorite': isFavorite,
    'percent_done': percentDone,
    'repeat_after': repeatAfter,
    'repeat_mode': repeatMode,
    'labels': labels.map((l) => {'id': l.id, 'title': l.title, 'hex_color': l.hexColor}).toList(),
    'assignees': assignees.map((u) => {'id': u.id, 'username': u.username}).toList(),
    'reminders': reminders.map((r) => r.toJson()).toList(),
  };
}

class VikunjaComment {
  const VikunjaComment({
    required this.id,
    required this.comment,
    required this.author,
    this.created,
  });

  final int id;
  final String comment;
  final VikunjaUser? author;
  final DateTime? created;

  factory VikunjaComment.fromJson(Map<String, dynamic> j) => VikunjaComment(
    id: j['id'] as int? ?? 0,
    comment: j['comment'] as String? ?? '',
    author: j['author'] is Map<String, dynamic>
        ? VikunjaUser.fromJson(j['author'] as Map<String, dynamic>)
        : null,
    created: _date(j['created']),
  );
}
