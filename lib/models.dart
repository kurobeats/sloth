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

/// Element-wise list equality, so models with list fields can implement `==`
/// without pulling in a package.
bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Midnight of [t]'s day.
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// Exclusive upper bound of "today" for [now]: tomorrow's midnight.
DateTime endOfToday(DateTime now) => startOfDay(now).add(const Duration(days: 1));

class VikunjaUserSettings {
  const VikunjaUserSettings({
    this.name = '',
    this.language = 'en',
    this.timezone = 'GMT',
    this.weekStart = 0,
    this.defaultProjectId = 0,
    this.discoverableByName = false,
    this.discoverableByEmail = false,
    this.emailRemindersEnabled = false,
    this.overdueRemindersEnabled = false,
    this.overdueRemindersTime = '9:00',
  });

  final String name;
  final String language;
  final String timezone;

  /// 0 = Sunday, 1 = Monday.
  final int weekStart;

  /// 0 means no default project.
  final int defaultProjectId;

  final bool discoverableByName;
  final bool discoverableByEmail;
  final bool emailRemindersEnabled;
  final bool overdueRemindersEnabled;

  /// "H:mm", the format Vikunja stores.
  final String overdueRemindersTime;

  factory VikunjaUserSettings.fromJson(Map<String, dynamic> j) =>
      VikunjaUserSettings(
        name: j['name'] as String? ?? '',
        language: (j['language'] as String?)?.isNotEmpty == true
            ? j['language'] as String
            : 'en',
        timezone: (j['timezone'] as String?)?.isNotEmpty == true
            ? j['timezone'] as String
            : 'GMT',
        weekStart: (j['week_start'] as num?)?.toInt() ?? 0,
        defaultProjectId: (j['default_project_id'] as num?)?.toInt() ?? 0,
        discoverableByName: j['discoverable_by_name'] as bool? ?? false,
        discoverableByEmail: j['discoverable_by_email'] as bool? ?? false,
        emailRemindersEnabled: j['email_reminders_enabled'] as bool? ?? false,
        overdueRemindersEnabled:
            j['overdue_tasks_reminders_enabled'] as bool? ?? false,
        overdueRemindersTime:
            (j['overdue_tasks_reminders_time'] as String?)?.isNotEmpty == true
            ? j['overdue_tasks_reminders_time'] as String
            : '9:00',
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'language': language,
    'timezone': timezone,
    'week_start': weekStart,
    'default_project_id': defaultProjectId,
    'discoverable_by_name': discoverableByName,
    'discoverable_by_email': discoverableByEmail,
    'email_reminders_enabled': emailRemindersEnabled,
    'overdue_tasks_reminders_enabled': overdueRemindersEnabled,
    'overdue_tasks_reminders_time': overdueRemindersTime,
  };

  @override
  bool operator ==(Object other) =>
      other is VikunjaUserSettings &&
      other.name == name &&
      other.language == language &&
      other.timezone == timezone &&
      other.weekStart == weekStart &&
      other.defaultProjectId == defaultProjectId &&
      other.discoverableByName == discoverableByName &&
      other.discoverableByEmail == discoverableByEmail &&
      other.emailRemindersEnabled == emailRemindersEnabled &&
      other.overdueRemindersEnabled == overdueRemindersEnabled &&
      other.overdueRemindersTime == overdueRemindersTime;

  @override
  int get hashCode => Object.hashAll([
    name,
    language,
    timezone,
    weekStart,
    defaultProjectId,
    discoverableByName,
    discoverableByEmail,
    emailRemindersEnabled,
    overdueRemindersEnabled,
    overdueRemindersTime,
  ]);

  VikunjaUserSettings copyWith({
    String? name,
    String? language,
    String? timezone,
    int? weekStart,
    int? defaultProjectId,
    bool? discoverableByName,
    bool? discoverableByEmail,
    bool? emailRemindersEnabled,
    bool? overdueRemindersEnabled,
    String? overdueRemindersTime,
  }) => VikunjaUserSettings(
    name: name ?? this.name,
    language: language ?? this.language,
    timezone: timezone ?? this.timezone,
    weekStart: weekStart ?? this.weekStart,
    defaultProjectId: defaultProjectId ?? this.defaultProjectId,
    discoverableByName: discoverableByName ?? this.discoverableByName,
    discoverableByEmail: discoverableByEmail ?? this.discoverableByEmail,
    emailRemindersEnabled: emailRemindersEnabled ?? this.emailRemindersEnabled,
    overdueRemindersEnabled:
        overdueRemindersEnabled ?? this.overdueRemindersEnabled,
    overdueRemindersTime: overdueRemindersTime ?? this.overdueRemindersTime,
  );
}

class VikunjaUser {
  const VikunjaUser({
    required this.id,
    required this.username,
    this.name,
    this.email,
    this.isAdmin = false,
    this.settings,
  });

  final int id;
  final String username;
  final String? name;
  final String? email;
  final bool isAdmin;
  final VikunjaUserSettings? settings;

  String get displayName => name ?? username;

  /// Splits a display name into words for [initials]. `static final` so the
  /// pattern is compiled once, not once per avatar per rebuild.
  static final RegExp initialsSeparator = RegExp(r'\s+');

  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(initialsSeparator);
    if (parts.length == 1) return parts.first.characters(1);
    return parts.first.characters(1) + parts.last.characters(1);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'name': name ?? '',
    'email': email ?? '',
    'is_admin': isAdmin,
    if (settings != null) 'settings': settings!.toJson(),
  };

  factory VikunjaUser.fromJson(Map<String, dynamic> j) => VikunjaUser(
    id: j['id'] as int,
    username: j['username'] as String? ?? '',
    name: _str(j['name']),
    email: _str(j['email']),
    isAdmin: j['is_admin'] as bool? ?? false,
    settings: j['settings'] is Map<String, dynamic>
        ? VikunjaUserSettings.fromJson(j['settings'] as Map<String, dynamic>)
        : null,
  );

  @override
  bool operator ==(Object other) =>
      other is VikunjaUser &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.email == email &&
      other.isAdmin == isAdmin &&
      other.settings == settings;

  @override
  int get hashCode => Object.hash(id, username, name, email, isAdmin, settings);
}

extension on String {
  String characters(int n) =>
      substring(0, length < n ? length : n).toUpperCase();
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'hex_color': hexColor,
  };

  @override
  bool operator ==(Object other) =>
      other is VikunjaLabel &&
      other.id == id &&
      other.title == title &&
      other.hexColor == hexColor;

  @override
  int get hashCode => Object.hash(id, title, hexColor);
}

class VikunjaReminder {
  const VikunjaReminder({required this.reminder});

  final DateTime reminder;

  factory VikunjaReminder.fromJson(Map<String, dynamic> j) =>
      VikunjaReminder(reminder: _date(j['reminder']) ?? DateTime(2001));

  Map<String, dynamic> toJson() => {
    'reminder': reminder.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is VikunjaReminder && other.reminder == reminder;

  @override
  int get hashCode => reminder.hashCode;
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
  bool get isKanban => viewKind == 'kanban';

  factory VikunjaView.fromJson(Map<String, dynamic> j) => VikunjaView(
    id: j['id'] as int? ?? 0,
    title: j['title'] as String? ?? '',
    viewKind: j['view_kind'] as String? ?? 'list',
  );

  @override
  bool operator ==(Object other) =>
      other is VikunjaView &&
      other.id == id &&
      other.title == title &&
      other.viewKind == viewKind;

  @override
  int get hashCode => Object.hash(id, title, viewKind);
}

/// A kanban column. Vikunja returns these with their tasks embedded from
/// `GET /projects/{id}/views/{kanbanView}/tasks`.
class VikunjaBucket {
  const VikunjaBucket({
    required this.id,
    required this.title,
    this.tasks = const [],
  });

  final int id;
  final String title;
  final List<VikunjaTask> tasks;

  factory VikunjaBucket.fromJson(Map<String, dynamic> j) => VikunjaBucket(
    id: j['id'] as int? ?? 0,
    title: j['title'] as String? ?? '',
    tasks: (j['tasks'] as List? ?? const [])
        .map((e) => VikunjaTask.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is VikunjaBucket &&
      other.id == id &&
      other.title == title &&
      _listEq(other.tasks, tasks);

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(tasks));
}

class VikunjaProject {
  const VikunjaProject({
    required this.id,
    required this.title,
    this.description,
    this.hexColor = '',
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
    return (list.isNotEmpty
            ? list.first
            : (views.isNotEmpty ? views.first : null))
        ?.id;
  }

  /// Kanban view, when the project has one.
  int? get kanbanViewId {
    for (final v in views) {
      if (v.isKanban) return v.id;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description ?? '',
    'hex_color': hexColor,
    'is_favorite': isFavorite,
    'is_archived': isArchived,
    'position': position,
    'views': [
      for (final v in views)
        {'id': v.id, 'title': v.title, 'view_kind': v.viewKind},
    ],
  };

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

  @override
  bool operator ==(Object other) =>
      other is VikunjaProject &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.hexColor == hexColor &&
      other.isFavorite == isFavorite &&
      other.isArchived == isArchived &&
      other.position == position &&
      _listEq(other.views, views);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    hexColor,
    isFavorite,
    isArchived,
    position,
    Object.hashAll(views),
  );

  VikunjaProject copyWith({
    String? title,
    String? description,
    String? hexColor,
    bool? isFavorite,
    bool? isArchived,
    List<VikunjaView>? views,
    double? position,
  }) => VikunjaProject(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    hexColor: hexColor ?? this.hexColor,
    isFavorite: isFavorite ?? this.isFavorite,
    isArchived: isArchived ?? this.isArchived,
    views: views ?? this.views,
    position: position ?? this.position,
  );
}

class VikunjaTask {
  // Fields stay mutable on purpose: `AppState.mutate` hands a copy to a
  // `void Function(VikunjaTask)` callback that every screen mutates in place.
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
    this.relatedTasks,
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
  final Map<String, dynamic>? relatedTasks;

  List<VikunjaRelation> get relations => parseRelations(relatedTasks);

  bool get isOverdue => isOverdueAt(DateTime.now());

  /// [isOverdue] against an explicit clock, so a caller (or a test) is not
  /// tied to the wall clock.
  bool isOverdueAt(DateTime now) =>
      !done && dueDate != null && dueDate!.isBefore(now);

  /// True when the deadline falls before [cutoff]. Done state is the caller's
  /// business: the completed list needs the same date predicate.
  bool isDueBy(DateTime cutoff) => dueDate != null && dueDate!.isBefore(cutoff);

  bool get isDueToday => isDueTodayAt(DateTime.now());

  /// [isDueToday] against an explicit clock. Day comparison only, so it stays
  /// correct across DST changes.
  bool isDueTodayAt(DateTime now) {
    final due = dueDate;
    if (due == null) return false;
    return due.year == now.year && due.month == now.month && due.day == now.day;
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
    relatedTasks: j['related_tasks'] is Map<String, dynamic>
        ? j['related_tasks'] as Map<String, dynamic>
        : null,
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

  /// Body for POST /tasks/{id}. The server replaces the task wholesale, so
  /// every stored field has to be sent — an omitted due_date is cleared.
  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'title': title,
    'description': description ?? '',
    'done': done,
    if (doneAt != null) 'done_at': doneAt!.toUtc().toIso8601String(),
    'due_date':
        dueDate?.toUtc().toIso8601String() ?? DateTime.utc(1).toIso8601String(),
    'start_date':
        startDate?.toUtc().toIso8601String() ??
        DateTime.utc(1).toIso8601String(),
    'end_date':
        endDate?.toUtc().toIso8601String() ?? DateTime.utc(1).toIso8601String(),
    'priority': priority,
    'is_favorite': isFavorite,
    'percent_done': percentDone,
    'repeat_after': repeatAfter,
    'repeat_mode': repeatMode,
    'labels': labels
        .map((l) => {'id': l.id, 'title': l.title, 'hex_color': l.hexColor})
        .toList(),
    'assignees': assignees
        .map((u) => {'id': u.id, 'username': u.username})
        .toList(),
    'reminders': reminders.map((r) => r.toJson()).toList(),
  };

  /// A detached copy. Null means "keep": the callers that need a real null
  /// (clearing a due date) go through `mutate`, whose callback assigns.
  VikunjaTask copyWith({
    String? title,
    String? description,
    bool? done,
    DateTime? doneAt,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
    int? priority,
    bool? isFavorite,
    double? percentDone,
    List<VikunjaLabel>? labels,
    List<VikunjaUser>? assignees,
    List<VikunjaReminder>? reminders,
    int? repeatAfter,
    int? repeatMode,
  }) => VikunjaTask(
    id: id,
    projectId: projectId,
    title: title ?? this.title,
    description: description ?? this.description,
    done: done ?? this.done,
    doneAt: doneAt ?? this.doneAt,
    dueDate: dueDate ?? this.dueDate,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    priority: priority ?? this.priority,
    isFavorite: isFavorite ?? this.isFavorite,
    percentDone: percentDone ?? this.percentDone,
    labels: labels ?? this.labels,
    assignees: assignees ?? this.assignees,
    reminders: reminders ?? this.reminders,
    repeatAfter: repeatAfter ?? this.repeatAfter,
    repeatMode: repeatMode ?? this.repeatMode,
    hexColor: hexColor,
    identifier: identifier,
    created: created,
    updated: updated,
    position: position,
    commentCount: commentCount,
    relatedTasks: relatedTasks,
  );

  /// Value equality over the fields the app reads. `relatedTasks` is the raw
  /// server payload of a single-task fetch, so it is left out: two tasks that
  /// differ only in relations still compare equal.
  @override
  bool operator ==(Object other) =>
      other is VikunjaTask &&
      other.id == id &&
      other.projectId == projectId &&
      other.title == title &&
      other.description == description &&
      other.done == done &&
      other.doneAt == doneAt &&
      other.dueDate == dueDate &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.priority == priority &&
      other.isFavorite == isFavorite &&
      other.percentDone == percentDone &&
      other.repeatAfter == repeatAfter &&
      other.repeatMode == repeatMode &&
      other.hexColor == hexColor &&
      other.identifier == identifier &&
      other.created == created &&
      other.updated == updated &&
      other.position == position &&
      other.commentCount == commentCount &&
      _listEq(other.labels, labels) &&
      _listEq(other.assignees, assignees) &&
      _listEq(other.reminders, reminders);

  @override
  int get hashCode => Object.hashAll([
    id,
    projectId,
    title,
    description,
    done,
    doneAt,
    dueDate,
    startDate,
    endDate,
    priority,
    isFavorite,
    percentDone,
    repeatAfter,
    repeatMode,
    hexColor,
    identifier,
    created,
    updated,
    position,
    commentCount,
  ]);
}

/// Open tasks due today or earlier, earliest deadline first. The single
/// definition the Due Today smart list and the home screen widget share.
List<VikunjaTask> dueBefore(Iterable<VikunjaTask> tasks, DateTime cutoff) =>
    tasks.where((t) => !t.done && t.isDueBy(cutoff)).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

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

  @override
  bool operator ==(Object other) =>
      other is VikunjaComment &&
      other.id == id &&
      other.comment == comment &&
      other.author == author &&
      other.created == created;

  @override
  int get hashCode => Object.hash(id, comment, author, created);
}

/// Vikunja permissions: 0 read, 1 write, 2 admin.
String permissionLabel(int permission) => switch (permission) {
  2 => 'Admin',
  1 => 'Write',
  _ => 'Read',
};

class VikunjaTeamMember {
  const VikunjaTeamMember({
    required this.id,
    required this.username,
    this.name,
    this.email,
    this.admin = false,
  });

  final int id;
  final String username;
  final String? name;
  final String? email;
  final bool admin;

  String get displayName => (name == null || name!.isEmpty) ? username : name!;

  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(VikunjaUser.initialsSeparator);
    if (parts.length == 1) {
      return source.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory VikunjaTeamMember.fromJson(Map<String, dynamic> j) =>
      VikunjaTeamMember(
        id: j['id'] as int? ?? 0,
        username: j['username'] as String? ?? '',
        name: _str(j['name']),
        email: _str(j['email']),
        admin: j['admin'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is VikunjaTeamMember &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.email == email &&
      other.admin == admin;

  @override
  int get hashCode => Object.hash(id, username, name, email, admin);
}

class VikunjaTeam {
  const VikunjaTeam({
    required this.id,
    required this.name,
    this.description,
    this.members = const [],
    this.isPublic = false,
  });

  final int id;
  final String name;
  final String? description;
  final List<VikunjaTeamMember> members;
  final bool isPublic;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description ?? '',
    'is_public': isPublic,
    'members': [
      for (final m in members)
        {
          'id': m.id,
          'username': m.username,
          'name': m.name ?? '',
          'email': m.email ?? '',
          'admin': m.admin,
        },
    ],
  };

  factory VikunjaTeam.fromJson(Map<String, dynamic> j) => VikunjaTeam(
    id: j['id'] as int? ?? 0,
    name: j['name'] as String? ?? '',
    description: _str(j['description']),
    isPublic: j['is_public'] as bool? ?? false,
    members: (j['members'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VikunjaTeamMember.fromJson)
        .toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is VikunjaTeam &&
      other.id == id &&
      other.name == name &&
      other.description == description &&
      other.isPublic == isPublic &&
      _listEq(other.members, members);

  @override
  int get hashCode =>
      Object.hash(id, name, description, isPublic, Object.hashAll(members));
}

/// A project shared with a user or a team.
class VikunjaProjectShare {
  const VikunjaProjectShare({
    required this.displayName,
    required this.permission,
    this.teamId,
    this.userId,
    this.username,
  });

  final String displayName;
  final int permission;
  final int? teamId;
  final int? userId;
  final String? username;

  bool get isTeam => teamId != null;

  factory VikunjaProjectShare.fromTeam(Map<String, dynamic> j) =>
      VikunjaProjectShare(
        displayName: j['name'] as String? ?? 'Team',
        permission: (j['permission'] as num?)?.toInt() ?? 0,
        teamId: j['id'] as int?,
      );

  factory VikunjaProjectShare.fromUser(Map<String, dynamic> j) {
    final name = _str(j['name']);
    final username = _str(j['username']);
    return VikunjaProjectShare(
      displayName: (name == null || name.isEmpty) ? (username ?? 'User') : name,
      permission: (j['permission'] as num?)?.toInt() ?? 0,
      userId: j['id'] as int?,
      username: username,
    );
  }
}

class VikunjaLinkShare {
  const VikunjaLinkShare({
    required this.id,
    required this.hash,
    required this.name,
    required this.permission,
    this.hasPassword = false,
  });

  final int id;
  final String hash;
  final String name;
  final int permission;
  final bool hasPassword;

  factory VikunjaLinkShare.fromJson(Map<String, dynamic> j) => VikunjaLinkShare(
    id: j['id'] as int? ?? 0,
    hash: j['hash'] as String? ?? '',
    name: (j['name'] as String?)?.trim().isNotEmpty == true
        ? j['name'] as String
        : 'Shared link',
    permission: (j['permission'] as num?)?.toInt() ?? 0,
    hasPassword: (_str(j['password']) ?? '').isNotEmpty,
  );
}

/// A Vikunja notification. The payload shape depends on [name]; the fields
/// below cover the ones the app shows.
class VikunjaNotification {
  const VikunjaNotification({
    required this.id,
    required this.name,
    this.created,
    this.readAt,
    this.doer,
    this.taskId,
    this.taskTitle,
    this.projectTitle,
    this.commentText,
    this.teamTitle,
  });

  final int id;
  final String name;
  final DateTime? created;
  final DateTime? readAt;
  final String? doer;
  final int? taskId;
  final String? taskTitle;
  final String? projectTitle;
  final String? commentText;
  final String? teamTitle;

  /// Vikunja writes a zero timestamp for "not read yet".
  bool get isRead => readAt != null && readAt!.year > 1;

  /// Headline: what happened, to what.
  String get title {
    final who = doer ?? 'Someone';
    switch (name) {
      case 'task.assigned':
        return '$who assigned you $taskTitle'.trim();
      case 'task.comment':
        return '$who commented on $taskTitle'.trim();
      case 'task.overdue':
        return '$taskTitle is overdue';
      case 'task.deleted':
        return '$who deleted $taskTitle'.trim();
      case 'task.mention':
        return '$who mentioned you on $taskTitle'.trim();
      case 'team.member.added':
        return 'You were added to ${teamTitle ?? 'a team'}';
      case 'project.shared':
        return '${projectTitle ?? 'A project'} was shared with you';
      default:
        return name;
    }
  }

  /// Second line: the comment body, otherwise the project.
  String? get subtitle {
    if (commentText != null && commentText!.isNotEmpty) return commentText;
    if (projectTitle != null && projectTitle!.isNotEmpty) return projectTitle;
    if (teamTitle != null && teamTitle!.isNotEmpty) {
      return doer == null ? teamTitle : 'Added by $doer';
    }
    return null;
  }

  factory VikunjaNotification.fromJson(Map<String, dynamic> j) {
    final payload = j['notification'] is Map<String, dynamic>
        ? j['notification'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String? text(String key) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) return value;
      return null;
    }

    Map<String, dynamic> nested(String key) =>
        payload[key] is Map<String, dynamic>
        ? payload[key] as Map<String, dynamic>
        : const <String, dynamic>{};

    final doer = nested('doer');
    final task = nested('task');
    final project = nested('project');
    final team = nested('team');
    final comment = nested('comment');

    return VikunjaNotification(
      id: j['id'] as int? ?? 0,
      name: j['name'] as String? ?? '',
      created: _date(j['created']),
      readAt: _date(j['read_at']),
      doer: (doer['name'] as String?) ?? text('doer'),
      taskId: (task['id'] as num?)?.toInt(),
      taskTitle: task['title'] as String?,
      projectTitle: project['title'] as String?,
      commentText: comment['comment'] as String?,
      teamTitle: team['title'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VikunjaNotification &&
      other.id == id &&
      other.name == name &&
      other.created == created &&
      other.readAt == readAt &&
      other.doer == doer &&
      other.taskId == taskId &&
      other.taskTitle == taskTitle &&
      other.projectTitle == projectTitle &&
      other.commentText == commentText &&
      other.teamTitle == teamTitle;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    created,
    readAt,
    doer,
    taskId,
    taskTitle,
    projectTitle,
    commentText,
    teamTitle,
  ]);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created': created?.toUtc().toIso8601String(),
    'read_at': readAt?.toUtc().toIso8601String(),
    'notification': {
      'doer': {'name': doer},
      'task': {'id': taskId, 'title': taskTitle},
      'project': {'title': projectTitle},
      'comment': {'comment': commentText},
      'team': {'title': teamTitle},
    },
  };
}

class VikunjaAttachment {
  const VikunjaAttachment({
    required this.id,
    required this.taskId,
    required this.name,
    required this.size,
    this.mime,
    this.created,
  });

  final int id;
  final int taskId;
  final String name;
  final int size;
  final String? mime;
  final DateTime? created;

  String get readableSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory VikunjaAttachment.fromJson(Map<String, dynamic> j) {
    final file = j['file'] is Map<String, dynamic>
        ? j['file'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return VikunjaAttachment(
      id: j['id'] as int? ?? 0,
      taskId: j['task_id'] as int? ?? 0,
      name: (file['name'] as String?) ?? 'attachment',
      size: (file['size'] as num?)?.toInt() ?? 0,
      mime: _str(file['mime']),
      created: _date(j['created']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VikunjaAttachment &&
      other.id == id &&
      other.taskId == taskId &&
      other.name == name &&
      other.size == size &&
      other.mime == mime &&
      other.created == created;

  @override
  int get hashCode => Object.hash(id, taskId, name, size, mime, created);
}

/// Vikunja relation kinds, as used by /tasks/{id}/relations.
class VikunjaRelation {
  const VikunjaRelation({
    required this.kind,
    required this.taskId,
    required this.title,
    required this.done,
  });

  /// The server's relation kind name, e.g. `subtask` or `related`. Vikunja
  /// accepts and returns these names; older builds used numbers, which
  /// [_kindFromKey] maps onto the same names.
  final String kind;
  final int taskId;
  final String title;
  final bool done;

  @override
  bool operator ==(Object other) =>
      other is VikunjaRelation &&
      other.kind == kind &&
      other.taskId == taskId &&
      other.title == title &&
      other.done == done;

  @override
  int get hashCode => Object.hash(kind, taskId, title, done);

  static const subtask = 'subtask';
  static const parentTask = 'parenttask';
  static const related = 'related';
  static const duplicateOf = 'duplicateof';

  static String label(String kind) => switch (kind) {
    subtask => 'Subtask',
    parentTask => 'Parent task',
    related => 'Related',
    duplicateOf => 'Duplicate of',
    'duplicates' => 'Duplicates',
    'blocking' => 'Blocking',
    'blocked' => 'Blocked by',
    'precedes' => 'Precedes',
    'follows' => 'Follows',
    'copiedfrom' => 'Copied from',
    'copiedto' => 'Copied to',
    _ => 'Relation',
  };

  static const selectableKinds = [subtask, parentTask, related, duplicateOf];

  /// `other_task_id` style keys come back as names on current servers and as
  /// 1..11 numbers on old ones.
  static String _kindFromKey(String key) {
    const byNumber = {
      '1': subtask,
      '2': parentTask,
      '3': related,
      '4': duplicateOf,
      '5': 'duplicates',
      '6': 'blocking',
      '7': 'blocked',
      '8': 'precedes',
      '9': 'follows',
      '10': 'copiedfrom',
      '11': 'copiedto',
    };
    final mapped = byNumber[key];
    if (mapped != null) return mapped;
    return key.toLowerCase();
  }
}

List<VikunjaRelation> parseRelations(Map<String, dynamic>? relatedTasks) {
  if (relatedTasks == null) return const [];
  final out = <VikunjaRelation>[];
  for (final entry in relatedTasks.entries) {
    final kind = VikunjaRelation._kindFromKey(entry.key);
    for (final task in (entry.value as List? ?? const [])) {
      if (task is! Map<String, dynamic>) continue;
      out.add(
        VikunjaRelation(
          kind: kind,
          taskId: (task['id'] as num?)?.toInt() ?? 0,
          title: task['title'] as String? ?? '',
          done: task['done'] as bool? ?? false,
        ),
      );
    }
  }
  return out;
}
