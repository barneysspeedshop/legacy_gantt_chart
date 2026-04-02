import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/resource_bucket.dart';

void main() {
  group('ResourceBucket', () {
    final date = DateTime(2023, 1, 1);

    test('constructs correctly', () {
      final bucket = ResourceBucket(date: date, resourceId: 'r1', totalLoad: 0.5);
      expect(bucket.date, date);
      expect(bucket.resourceId, 'r1');
      expect(bucket.totalLoad, 0.5);
    });

    test('isOverAllocated returns true when totalLoad > 1.0', () {
      expect(ResourceBucket(date: date, resourceId: 'r1', totalLoad: 0.5).isOverAllocated, isFalse);
      expect(ResourceBucket(date: date, resourceId: 'r1', totalLoad: 1.0).isOverAllocated, isFalse);
      expect(ResourceBucket(date: date, resourceId: 'r1', totalLoad: 1.1).isOverAllocated, isTrue);
    });

    test('supports equality and hashCode', () {
      final b1 = ResourceBucket(date: date, resourceId: 'r1', totalLoad: 0.5);
      final b2 = ResourceBucket(date: date, resourceId: 'r1', totalLoad: 0.5);
      final b3 = ResourceBucket(date: date, resourceId: 'r2', totalLoad: 0.5);

      expect(b1, equals(b2));
      expect(b1.hashCode, equals(b2.hashCode));
      expect(b1, isNot(equals(b3)));
    });

    test('copyWith works correctly', () {
      final original = ResourceBucket(date: date, resourceId: 'r1', totalLoad: 0.5);
      final updated = original.copyWith(totalLoad: 0.8, resourceId: 'r2');

      expect(updated.date, date);
      expect(updated.totalLoad, 0.8);
      expect(updated.resourceId, 'r2');
      expect(original.totalLoad, 0.5);
    });
  });
}
