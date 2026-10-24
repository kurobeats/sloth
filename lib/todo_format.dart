import 'package:intl/intl.dart';

/// Date/repeat formatting helpers.
///
/// Relative labels ("Today", "Tomorrow", "Yesterday") then a short date
/// ("Mon 3 Nov"), widening to include the year when it differs.
class TodoFormat {
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String dueLabel(DateTime due, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(due.year, due.month, due.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > 1 && diff < 7) return DateFormat('EEEE').format(due);
    if (due.year == n.year) return DateFormat('EEE d MMM').format(due);
    return DateFormat('EEE d MMM y').format(due);
  }

  /// Compact "Today", "Mon", "3 Nov" used inside the task metadata row.
  static String metadataLabel(DateTime due, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = DateTime(due.year, due.month, due.day)
        .difference(DateTime(n.year, n.month, n.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > -7 && diff < 7) return DateFormat('EEE').format(due);
    return due.year == n.year
        ? DateFormat('d MMM').format(due)
        : DateFormat('d MMM y').format(due);
  }

  static String withTime(DateTime due) =>
      '${metadataLabel(due)}, ${DateFormat.Hm().format(due)}';

  /// Repeat labels use Vikunja's wording: "Every Day", "Every Week",
  /// "Every 30 Days", "Monthly".
  static String repeat(int seconds) {
    if (seconds <= 0) return '';
    const day = 86400;
    if (seconds == day) return 'Every Day';
    if (seconds == day * 7) return 'Every Week';
    if (seconds == day * 30) return 'Every 30 Days';
    if (seconds == day * 365) return 'Yearly';
    if (seconds % (day * 7) == 0) return 'Every ${seconds ~/ (day * 7)} Weeks';
    if (seconds % day == 0) return 'Every ${seconds ~/ day} Days';
    if (seconds % 3600 == 0) return 'Every ${seconds ~/ 3600} Hours';
    return 'Every ${seconds ~/ 60} Minutes';
  }

  /// Vikunja priorities (0-5).
  static String priority(int p) => switch (p) {
    1 => 'Low',
    2 => 'Medium',
    3 => 'High',
    4 => 'Urgent',
    5 => 'DO NOW',
    _ => 'Unset',
  };

  static String created(DateTime? d) =>
      d == null ? '' : 'Created ${DateFormat('d MMM y').format(d)}';

  /// Groups tasks by day (for the Planned view). Tasks without a due date go
  /// into a trailing "No date" bucket keyed by null.
  static List<({DateTime? day, List<T> tasks})> groupByDay<T>(
    List<T> tasks,
    DateTime? Function(T) dueOf,
  ) {
    final buckets = <String, ({DateTime? day, List<T> tasks})>{};
    final noDate = <T>[];
    for (final t in tasks) {
      final due = dueOf(t);
      if (due == null) {
        noDate.add(t);
        continue;
      }
      final day = DateTime(due.year, due.month, due.day);
      final key = day.toIso8601String();
      final existing = buckets[key];
      if (existing == null) {
        buckets[key] = (day: day, tasks: [t]);
      } else {
        existing.tasks.add(t);
      }
    }
    final ordered = buckets.values.toList()
      ..sort((a, b) => a.day!.compareTo(b.day!));
    if (noDate.isNotEmpty) ordered.add((day: null, tasks: noDate));
    return ordered;
  }

  static String groupHeader(DateTime? day) {
    if (day == null) return 'No due date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 0) return DateFormat('EEEE d MMM').format(day);
    return DateFormat('EEEE d MMM').format(day);
  }
}
