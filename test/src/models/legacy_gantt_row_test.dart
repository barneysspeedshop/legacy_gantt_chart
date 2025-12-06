import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';

void main() {
  group('LegacyGanttRow', () {
    test('instantiation', () {
      const row = LegacyGanttRow(id: 'r1', label: 'Row 1');
      expect(row.id, 'r1');
      expect(row.label, 'Row 1');
    });

    test('equality and hashCode', () {
      const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');
      const row2 = LegacyGanttRow(id: 'r1', label: 'Row 1 (different label but same id)');
      const row3 = LegacyGanttRow(id: 'r2', label: 'Row 2');

      // Equality is based on ID only as per implementation
      expect(row1, row2);
      expect(row1.hashCode, row2.hashCode);
      expect(row1, isNot(row3));
    });
  });
}
