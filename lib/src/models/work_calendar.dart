import 'package:flutter/foundation.dart';

/// Defines the working schedule for the Gantt chart.
///
/// This class helps calculating durations and end dates by skipping non-working days
/// (weekends and holidays).
@immutable
class WorkCalendar {
  /// The set of days of the week that are considered weekends (non-working).
  ///
  /// 1 = Monday, 7 = Sunday.
  /// Defaults to [DateTime.saturday, DateTime.sunday].
  final Set<int> weekendDays;

  /// A set of specific dates that are holidays (non-working).
  ///
  /// These dates should be normalized to midnight (00:00:00).
  final Set<DateTime> holidays;

  const WorkCalendar({
    this.weekendDays = const {DateTime.saturday, DateTime.sunday},
    this.holidays = const {},
  });

  /// Returns true if the given [date] is a working day.
  bool isWorkingDay(DateTime date) {
    if (weekendDays.contains(date.weekday)) return false;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    if (holidays.contains(normalizedDate)) return false;
    return true;
  }

  /// Adds [workingDays] to [start], skipping non-working days.
  ///
  /// If [start] typically falls on a non-working day, the count starts from the
  /// next working day?
  /// Standard behavior:
  /// If start is non-working, we might want to start counting from the next working day,
  /// OR we treat 'start' as the anchor.
  /// Let's assume [start] is inclusive if it's a working day.
  DateTime addWorkingDays(DateTime start, int workingDays) {
    if (workingDays == 0) return start;

    DateTime current = start;
    int daysAdded = 0;
    int direction = workingDays > 0 ? 1 : -1;
    int absDays = workingDays.abs();

    while (daysAdded < absDays) {
      current = current.add(Duration(days: direction));
      if (isWorkingDay(current)) {
        daysAdded++;
      }
    }
    return current;
  }

  /// Calculates the number of working days between [start] and [end].
  ///
  /// The range is inclusive of [start] and exclusive of [end], or inclusive/inclusive?
  /// Standard duration: end - start.
  /// For Gantt charts, usually start=Monday, end=Monday (1 week) might be 5 days.
  /// Let's treat it as the number of 24h chunks that fall on working days?
  /// Or simple day counting.
  /// Let's go with: Count working days from start (inclusive) to end (exclusive).
  int getWorkingDuration(DateTime start, DateTime end) {
    if (start.isAfter(end)) return -getWorkingDuration(end, start);

    int count = 0;
    DateTime current = DateTime(start.year, start.month, start.day);
    DateTime endDate = DateTime(end.year, end.month, end.day); // Normalize

    while (current.isBefore(endDate)) {
      if (isWorkingDay(current)) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count;
  }

  /// Returns a list of [start, end) ranges representing non-working periods between [start] and [end].
  ///
  /// The input [start] and [end] are used to clamp the returned ranges.
  List<(DateTime, DateTime)> getNonWorkingRanges(DateTime start, DateTime end) {
    if (start.isAfter(end) || start == end) return [];

    final ranges = <(DateTime, DateTime)>[];
    DateTime? nonWorkingStart;
    DateTime iterDay = DateTime(start.year, start.month, start.day);

    while (iterDay.isBefore(end)) {
      final isWorking = isWorkingDay(iterDay);

      if (!isWorking) {
        nonWorkingStart ??= iterDay.isBefore(start) ? start : iterDay;
      } else {
        if (nonWorkingStart != null) {
          ranges.add((nonWorkingStart, iterDay));
          nonWorkingStart = null;
        }
      }

      iterDay = iterDay.add(const Duration(days: 1));
    }

    if (nonWorkingStart != null) {
      ranges.add((nonWorkingStart, end));
    }

    final clampedRanges = <(DateTime, DateTime)>[];
    for (final r in ranges) {
      DateTime s = r.$1;
      DateTime e = r.$2;

      if (e.isAfter(end)) e = end;

      if (s.isBefore(e)) {
        clampedRanges.add((s, e));
      }
    }

    return clampedRanges;
  }
}
