import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';

void main() {
  group('LegacyGanttRow', () {
    test('instantiation works', () {
      const row = LegacyGanttRow(id: '1', label: 'Row 1');
      expect(row.id, '1');
      expect(row.label, 'Row 1');
    });

    test('equality works based on id', () {
      const row1 = LegacyGanttRow(id: '1', label: 'Row 1');
      const row2 = LegacyGanttRow(id: '1', label: 'Row 1 - Updated'); // Label differs
      const row3 = LegacyGanttRow(id: '2', label: 'Row 2');

      expect(row1, equals(row2)); // Should be equal because only ID matters
      expect(row1, isNot(equals(row3)));
    });

    test('hashCode works', () {
      const row1 = LegacyGanttRow(id: '1', label: 'Row A');
      const row2 = LegacyGanttRow(id: '1', label: 'Row B');

      expect(row1.hashCode, row2.hashCode);
    });
  });
}
