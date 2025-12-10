import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/remote_ghost.dart';

void main() {
  group('RemoteGhost', () {
    test('instantiates correctly with required fields', () {
      final now = DateTime.now();
      final ghost = RemoteGhost(
        userId: 'user-1',
        lastUpdated: now,
      );

      expect(ghost.userId, 'user-1');
      expect(ghost.lastUpdated, now);
      expect(ghost.taskId, ''); // Default value
      expect(ghost.start, null);
      expect(ghost.end, null);
      expect(ghost.viewportStart, null);
      expect(ghost.viewportEnd, null);
      expect(ghost.verticalScrollOffset, null);
      expect(ghost.userName, null);
      expect(ghost.userColor, null);
    });

    test('instantiates correctly with all fields', () {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 1));
      final end = now.add(const Duration(days: 1));
      final viewportStart = now.subtract(const Duration(hours: 1));
      final viewportEnd = now.add(const Duration(hours: 1));

      final ghost = RemoteGhost(
        userId: 'user-2',
        taskId: 'task-123',
        lastUpdated: now,
        start: start,
        end: end,
        viewportStart: viewportStart,
        viewportEnd: viewportEnd,
        verticalScrollOffset: 150.0,
        userName: 'Alice',
        userColor: '#FF5733',
      );

      expect(ghost.userId, 'user-2');
      expect(ghost.taskId, 'task-123');
      expect(ghost.lastUpdated, now);
      expect(ghost.start, start);
      expect(ghost.end, end);
      expect(ghost.viewportStart, viewportStart);
      expect(ghost.viewportEnd, viewportEnd);
      expect(ghost.verticalScrollOffset, 150.0);
      expect(ghost.userColor, '#FF5733');
    });

    test('supports value equality', () {
      final now = DateTime.now();
      final ghost1 = RemoteGhost(userId: 'u1', lastUpdated: now, verticalScrollOffset: 10.0);
      final ghost2 = RemoteGhost(userId: 'u1', lastUpdated: now, verticalScrollOffset: 10.0);
      final ghost3 = RemoteGhost(userId: 'u1', lastUpdated: now, verticalScrollOffset: 20.0);

      expect(ghost1, equals(ghost2));
      expect(ghost1 == ghost2, isTrue);
      expect(ghost1.hashCode, ghost2.hashCode);

      expect(ghost1, isNot(equals(ghost3)));
      expect(ghost1 == ghost3, isFalse);
    });
  });
}
