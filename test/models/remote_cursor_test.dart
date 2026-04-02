import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/remote_cursor.dart';

void main() {
  group('RemoteCursor', () {
    test('constructs correctly', () {
      final time = DateTime(2023, 1, 1);
      final lastUpdated = DateTime(2023, 1, 1, 12);
      final cursor = RemoteCursor(
        userId: 'u1',
        time: time,
        rowId: 'r1',
        color: Colors.red,
        lastUpdated: lastUpdated,
      );

      expect(cursor.userId, 'u1');
      expect(cursor.time, time);
      expect(cursor.rowId, 'r1');
      expect(cursor.color, Colors.red);
      expect(cursor.lastUpdated, lastUpdated);
    });
  });
}
