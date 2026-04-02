import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/work_calendar.dart';

void main() {
  group('WorkCalendar', () {
    const saturday = 6;
    const sunday = 7;

    final calendar = WorkCalendar(
      weekendDays: const {saturday, sunday},
      holidays: {DateTime(2023, 1, 1)}, // Jan 1st is a holiday
    );

    test('isWorkingDay identifies weekends', () {
      expect(calendar.isWorkingDay(DateTime(2023, 1, 2)), isTrue); // Monday
      expect(calendar.isWorkingDay(DateTime(2023, 1, 7)), isFalse); // Saturday
      expect(calendar.isWorkingDay(DateTime(2023, 1, 8)), isFalse); // Sunday
    });

    test('isWorkingDay identifies holidays', () {
      expect(calendar.isWorkingDay(DateTime(2023, 1, 1)), isFalse); // Holiday
    });

    test('addWorkingDays adds days correctly, skipping weekends', () {
      final start = DateTime(2023, 1, 6); // Friday
      // Add 1 working day -> Monday (skip Sat, Sun)
      expect(calendar.addWorkingDays(start, 1), DateTime(2023, 1, 9));

      // Add 0 days
      expect(calendar.addWorkingDays(start, 0), start);
    });

    test('addWorkingDays subtracts days correctly', () {
      final start = DateTime(2023, 1, 9); // Monday
      // Subtract 1 working day -> Friday
      expect(calendar.addWorkingDays(start, -1), DateTime(2023, 1, 6));
    });

    test('getWorkingDuration counts working days between dates', () {
      final start = DateTime(2023, 1, 2); // Monday
      final end = DateTime(2023, 1, 7); // Saturday
      // Mon, Tue, Wed, Thu, Fri = 5 days
      expect(calendar.getWorkingDuration(start, end), 5);

      final endNextWeek = DateTime(2023, 1, 10); // Tuesday next week
      // previous 5 + Mon = 6 days
      expect(calendar.getWorkingDuration(start, endNextWeek), 6);
    });

    test('getWorkingDuration handles start after end', () {
      final start = DateTime(2023, 1, 2);
      final end = DateTime(2023, 1, 7);
      expect(calendar.getWorkingDuration(end, start), -5);
    });

    test('getNonWorkingRanges returns weekend and holiday gaps', () {
      final start = DateTime(2023, 1, 5); // Thursday
      final end = DateTime(2023, 1, 10); // Tuesday

      final ranges = calendar.getNonWorkingRanges(start, end);
      // Weekend: Sat(7) to Mon(9)
      expect(ranges.length, 1);
      expect(ranges[0].$1, DateTime(2023, 1, 7));
      expect(ranges[0].$2, DateTime(2023, 1, 9));
    });

    test('getNonWorkingRanges handles holiday at start', () {
      final start = DateTime(2023, 1, 1); // Holiday
      final end = DateTime(2023, 1, 3); // Tuesday

      final ranges = calendar.getNonWorkingRanges(start, end);
      // Holiday: Jan 1 to Jan 2
      expect(ranges.length, 1);
      expect(ranges[0].$1, DateTime(2023, 1, 1));
      expect(ranges[0].$2, DateTime(2023, 1, 2));
    });

    test('getNonWorkingRanges returns empty for start == end or start > end', () {
      expect(calendar.getNonWorkingRanges(DateTime(2023, 1, 1), DateTime(2023, 1, 1)), isEmpty);
      expect(calendar.getNonWorkingRanges(DateTime(2023, 1, 2), DateTime(2023, 1, 1)), isEmpty);
    });

    test('getNonWorkingRanges clamps ranges correctly', () {
      final start = DateTime(2023, 1, 7, 12); // Saturday Noon
      final end = DateTime(2023, 1, 8, 12); // Sunday Noon

      final ranges = calendar.getNonWorkingRanges(start, end);
      expect(ranges.length, 1);
      expect(ranges[0].$1, start);
      expect(ranges[0].$2, end);
    });
  });
}
