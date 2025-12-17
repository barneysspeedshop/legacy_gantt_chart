import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/work_calendar.dart';

void main() {
  group('WorkCalendar', () {
    test('isWorkingDay correctly identifies weekends', () {
      const calendar = WorkCalendar(weekendDays: {DateTime.saturday, DateTime.sunday});
      final friday = DateTime(2023, 10, 27);
      final saturday = DateTime(2023, 10, 28);
      final sunday = DateTime(2023, 10, 29);
      final monday = DateTime(2023, 10, 30);

      expect(calendar.isWorkingDay(friday), isTrue);
      expect(calendar.isWorkingDay(saturday), isFalse);
      expect(calendar.isWorkingDay(sunday), isFalse);
      expect(calendar.isWorkingDay(monday), isTrue);
    });

    test('isWorkingDay correctly identifies holidays', () {
      final holiday = DateTime(2023, 12, 25);
      final calendar = WorkCalendar(holidays: {holiday});

      expect(calendar.isWorkingDay(holiday), isFalse);
      expect(calendar.isWorkingDay(DateTime(2023, 12, 26)), isTrue);
    });

    test('addWorkingDays adds days skipping weekends', () {
      const calendar = WorkCalendar();
      final friday = DateTime(2023, 10, 27); // Friday

      // Add 1 working day -> Monday
      final nextDay = calendar.addWorkingDays(friday, 1);
      expect(nextDay.weekday, DateTime.monday);
      expect(nextDay, DateTime(2023, 10, 30));

      // Add 2 working days -> Tuesday
      final tuesday = calendar.addWorkingDays(friday, 2);
      expect(tuesday.weekday, DateTime.tuesday);
      expect(tuesday, DateTime(2023, 10, 31));
    });

    test('getWorkingDuration calculates days excluding weekends', () {
      const calendar = WorkCalendar();
      final friday = DateTime(2023, 10, 27);
      final nextTuesday = DateTime(2023, 10, 31);

      // Fri (1), Sat (0), Sun (0), Mon (1), Tue (0 - exclusive end) = 2 days?
      // getWorkingDuration is start inclusive, end exclusive?
      // Fri -> Mon is 1 day (Fri).
      // Fri -> Tue is 2 days (Fri, Mon).

      final duration = calendar.getWorkingDuration(friday, nextTuesday);
      expect(duration, 2);
    });
  });
}
