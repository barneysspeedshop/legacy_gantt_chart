import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/sync/hlc.dart';

void main() {
  group('Hlc UTC Standardization', () {
    test('Hlc.fromDate should always use UTC', () {
      final localDate = DateTime(2025, 12, 26, 15, 0); // Local 3 PM
      final hlc = Hlc.fromDate(localDate, 'node1');

      expect(hlc.millis, equals(localDate.toUtc().millisecondsSinceEpoch));
    });

    test('Hlc.parse should handle timestamps with and without Z suffix correctly as UTC', () {
      const isoWithZ = '2025-12-26T20:00:00.000Z';
      const isoWithoutZ = '2025-12-26T20:00:00.000';

      final hlc1 = Hlc.parse('$isoWithZ-0000-node1');
      final hlc2 = Hlc.parse('$isoWithoutZ-0000-node1');

      expect(hlc1.millis, equals(hlc2.millis));
      expect(DateTime.fromMillisecondsSinceEpoch(hlc1.millis, isUtc: true).year, equals(2025));
    });

    test('Hlc.parse should handle legacy int timestamps', () {
      const millis = 1735243200000;
      final hlc = Hlc.parse(millis.toString());
      expect(hlc.millis, equals(millis));
      expect(hlc.nodeId, equals('legacy'));
    });

    test('Hlc.toString should always include Z and be consistent', () {
      const hlc = Hlc(millis: 1735243200000, counter: 1, nodeId: 'testNode');
      final str = hlc.toString();
      expect(str, contains('Z-0001-testNode'));
      expect(Hlc.parse(str), equals(hlc));
    });
  });
}
