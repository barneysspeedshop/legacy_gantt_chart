import 'package:legacy_gantt_chart/src/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hlc', () {
    test('Default format matches requirement', () {
      final ts = DateTime.utc(2023, 10, 27, 10, 0, 0, 123).millisecondsSinceEpoch;
      final hlc = Hlc(millis: ts, counter: 0, nodeId: 'device123');

      // Expected: "2023-10-27T10:00:00.123Z-0000-device123"
      expect(hlc.toString(), '2023-10-27T10:00:00.123Z-0000-device123');
    });

    test('parses legacy integer timestamp correctly', () {
      final hlc = Hlc.parse('1766741365082');
      expect(hlc.millis, 1766741365082);
      expect(hlc.counter, 0);
      expect(hlc.nodeId, 'legacy');
    });

    test('parses correctly', () {
      final hlc = Hlc.parse('2023-10-27T10:00:00.123Z-000A-nodeId');
      expect(hlc.millis, DateTime.utc(2023, 10, 27, 10, 0, 0, 123).millisecondsSinceEpoch);
      expect(hlc.counter, 10);
      expect(hlc.nodeId, 'nodeId');
    });

    test('Comparisons follow milllis, counter, nodeId order', () {
      const t1 = Hlc(millis: 1000, counter: 0, nodeId: 'a');
      const t2 = Hlc(millis: 1000, counter: 0, nodeId: 'b');
      const t3 = Hlc(millis: 1000, counter: 1, nodeId: 'a');
      const t4 = Hlc(millis: 1001, counter: 0, nodeId: 'a');

      expect(t1.compareTo(t2), lessThan(0)); // check nodeId
      expect(t2.compareTo(t1), greaterThan(0));

      expect(t1.compareTo(t3), lessThan(0)); // check counter
      expect(t3.compareTo(t4), lessThan(0)); // check millis

      expect(t1 < t2, isTrue);
      expect(t4 > t3, isTrue);
    });

    test('send() increments logic', () {
      const start = Hlc(millis: 1000, counter: 5, nodeId: 'a');

      // Case 1: Wall time is old (stuck clock or burst of events)
      final next1 = start.send(999);
      expect(next1.millis, 1000);
      expect(next1.counter, 6); // Increment

      // Case 2: Wall time is same
      final next2 = start.send(1000);
      expect(next2.millis, 1000);
      expect(next2.counter, 6); // Increment

      // Case 3: Wall time advanced
      final next3 = start.send(1001);
      expect(next3.millis, 1001);
      expect(next3.counter, 0); // Reset
    });

    test('receive() merges logic', () {
      const local = Hlc(millis: 1000, counter: 5, nodeId: 'local');

      // Case 1: Remote is older (ignore remote time, basically just local send)
      // Wall time also older
      // remote: 900, 0, remote
      // wall: 900
      // max(1000, 900, 900) = 1000. Equal to local. Counter = local + 1
      const remote1 = Hlc(millis: 900, counter: 0, nodeId: 'remote');
      final res1 = local.receive(remote1, 900);
      expect(res1.millis, 1000);
      expect(res1.counter, 6);

      // Case 2: Remote is ahead
      // remote: 1100, 2
      // wall: 1000
      // max(1000, 1100, 1000) = 1100. Equal to remote. Counter = remote + 1
      const remote2 = Hlc(millis: 1100, counter: 2, nodeId: 'remote');
      final res2 = local.receive(remote2, 1000);
      expect(res2.millis, 1100);
      expect(res2.counter, 3);

      // Case 3: Remote and Local Equal (Conflict resolution scenario often)
      // remote: 1000, 7
      // wall: 1000
      // max(1000, 1000, 1000) = 1000. Equal to both. Counter = max(5, 7) + 1 = 8
      const remote3 = Hlc(millis: 1000, counter: 7, nodeId: 'remote');
      final res3 = local.receive(remote3, 1000);
      expect(res3.millis, 1000);
      expect(res3.counter, 8);

      // Case 4: Wall time is ahead of both
      // wall: 1200
      // max = 1200. Equal to neither. Counter = 0
      final res4 = local.receive(remote3, 1200);
      expect(res4.millis, 1200);
      expect(res4.counter, 0);
    });
  });
}
