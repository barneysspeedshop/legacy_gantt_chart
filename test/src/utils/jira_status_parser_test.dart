import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  group('JiraStatusParser', () {
    final createdDate = DateTime(2026, 1, 1, 10, 0, 0); // Jan 1, 2026, 10:00 AM

    test('Parses a standard multi-segment string correctly', () {
      // 100ms in first status, 200ms in second, 300ms in third
      const raw = '1_*:*_1_*:*_100_*|*_2_*:*_1_*:*_200_*|*_3_*:*_1_*:*_300';
      final result = JiraStatusParser.parse(raw, createdDate);

      expect(result, isNotNull);
      // Start = created + 100ms
      expect(result!.start, createdDate.add(const Duration(milliseconds: 100)));
      // End = Start + (200 + 300) = Start + 500ms
      expect(result.end, result.start.add(const Duration(milliseconds: 500)));
    });

    test('Handles active tasks (last segment duration is 0)', () {
      const raw = '1_*:*_1_*:*_1000_*|*_2_*:*_1_*:*_0';
      final result = JiraStatusParser.parse(raw, createdDate);

      expect(result, isNotNull);
      expect(result!.start, createdDate.add(const Duration(milliseconds: 1000)));
      // End should be roughly DateTime.now()
      final now = DateTime.now();
      expect(result.end.isAfter(now.subtract(const Duration(seconds: 1))), true);
      expect(result.end.isBefore(now.add(const Duration(seconds: 1))), true);
    });

    test('Handles large 64-bit durations', () {
      // ~85 days in MS
      const int largeDuration = 7347300280;
      final raw = '1_*:*_1_*:*_${largeDuration}_*|*_2_*:*_1_*:*_${largeDuration ~/ 2}';

      final result = JiraStatusParser.parse(raw, createdDate);

      expect(result, isNotNull);
      expect(result!.start, createdDate.add(const Duration(milliseconds: largeDuration)));
      expect(result.end, result.start.add(const Duration(milliseconds: largeDuration ~/ 2)));
    });

    test('Returns null for malformed strings', () {
      expect(JiraStatusParser.parse('', createdDate), isNull);
      expect(JiraStatusParser.parse('invalid', createdDate), isNull);
      expect(JiraStatusParser.parse('1_*:*_1', createdDate), isNull); // Missing duration
      expect(JiraStatusParser.parse('1_*:*_1_*:*_Abc', createdDate), isNull); // Non-numeric
    });

    test('Returns null for null raw string', () {
      expect(JiraStatusParser.parse(null, createdDate), isNull);
    });

    test('should handle Jira default localized timestamp format', () {
      final created = DateTime(2025, 8, 4, 12, 38);
      const raw = '1_*:*_1_*:*_7347300280_*|*_3_*:*_1_*:*_0';
      final result = JiraStatusParser.parse(raw, created);

      expect(result, isNotNull);
      // Row 2 from CSV: Created=Aug 4 2025 12:38 PM, Duration=7347300280 ms (~85 days)
      expect(result!.start, created.add(const Duration(milliseconds: 7347300280)));
    });
  });
}
