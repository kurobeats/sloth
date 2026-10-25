import 'package:intl/intl.dart';

/// Date/repeat formatting helpers.
///
/// Relative labels ("Today", "Tomorrow", "Yesterday") then a short date
/// ("Mon 3 Nov"), widening to include the year when it differs.
class TodoFormat {
  /// Whole days between two calendar dates. Comparing local midnights drifts by
  /// an hour across a DST change, which is enough for `inDays` to round a
  /// "tomorrow" down to "today"; UTC has no such days.
  static int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

  // One DateFormat per pattern: constructing one parses the skeleton, and every
  // task row formats at least one date per rebuild.
  static final DateFormat _weekday = DateFormat('EEEE');
  static final DateFormat _shortDate = DateFormat('EEE d MMM');
  static final DateFormat _shortDateYear = DateFormat('EEE d MMM y');
  static final DateFormat _weekdayShort = DateFormat('EEE');
  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMM y');
  static final DateFormat _time = DateFormat.Hm();
  static final DateFormat _weekdayDayMonth = DateFormat('EEEE d MMM');

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String dueLabel(DateTime due, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = _daysBetween(due, n);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > 1 && diff < 7) return _weekday.format(due);
    if (due.year == n.year) return _shortDate.format(due);
    return _shortDateYear.format(due);
  }

  /// Compact "Today", "Mon", "3 Nov" used inside the task metadata row.
  static String metadataLabel(DateTime due, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = _daysBetween(due, n);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > -7 && diff < 7) return _weekdayShort.format(due);
    return due.year == n.year
        ? _dayMonth.format(due)
        : _dayMonthYear.format(due);
  }

  static String withTime(DateTime due) =>
      '${metadataLabel(due)}, ${_time.format(due)}';

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
      d == null ? '' : 'Created ${_dayMonthYear.format(d)}';

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
    final diff = _daysBetween(day, DateTime.now());
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return _weekdayDayMonth.format(day);
  }
}
