import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';

void main() {
  test('LegacyGanttRow equality works correctly', () {
    const row1 = LegacyGanttRow(id: 'r1');
    const row2 = LegacyGanttRow(id: 'r1');
    const row3 = LegacyGanttRow(id: 'r2');

    expect(row1, equals(row2));
    expect(row1.hashCode, equals(row2.hashCode));
    expect(row1, isNot(equals(row3)));
  });
}
