import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/src/sync/merkle_tree.dart';

class MockWebSocketClient extends GanttSyncClient {
  String? remoteRootToReturn;
  bool syncCalled = false;

  @override
  Future<String> getMerkleRoot() async => remoteRootToReturn ?? '';

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {
    syncCalled = true;
  }

  @override
  Stream<Operation> get operationStream => const Stream.empty();
  @override
  Future<List<Operation>> getInitialState() async => [];
  @override
  Stream<SyncProgress> get inboundProgress => const Stream.empty();
  @override
  Stream<int> get outboundPendingCount => const Stream.empty();
  @override
  Hlc get currentHlc => Hlc.zero;
  void connect(String tenantId, {Hlc? lastSyncedTimestamp}) {}
  @override
  Future<void> sendOperation(Operation operation) async {}
  @override
  Future<void> sendOperations(List<Operation> operations) async {}
}

void main() {
  group('Merkle Integration', () {
    test('Calculates local root and detects mismatch', () async {
      final task1 = LegacyGanttTask(
        id: 't1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        name: 'Task 1',
      );

      // 1. Calculate Expected Root
      final localHash = task1.contentHash;
      final expectedRoot = MerkleTree.computeRoot([localHash]);

      // 2. Setup Mock Client with DIFFERENT root
      final client = MockWebSocketClient();
      client.remoteRootToReturn = 'DIFFERENT_HASH';

      // 3. Perform Check Logic (Simulation of ViewModel logic)
      final vmData = [task1];
      final currentLocalRoot = MerkleTree.computeRoot(vmData.map((t) => t.contentHash).toList());

      expect(currentLocalRoot, expectedRoot);
      expect(currentLocalRoot, isNot(await client.getMerkleRoot()));

      if (currentLocalRoot != await client.getMerkleRoot()) {
        await client.syncWithMerkle(remoteRoot: await client.getMerkleRoot(), depth: 0);
      }

      expect(client.syncCalled, isTrue);
    });

    test('Calculates local root and verifies match', () async {
      final task1 = LegacyGanttTask(
        id: 't1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        name: 'Task 1',
      );

      final localHash = task1.contentHash;
      final expectedRoot = MerkleTree.computeRoot([localHash]);

      final client = MockWebSocketClient();
      client.remoteRootToReturn = expectedRoot; // MATCHING

      final vmData = [task1];
      final currentLocalRoot = MerkleTree.computeRoot(vmData.map((t) => t.contentHash).toList());

      expect(currentLocalRoot, await client.getMerkleRoot());

      if (currentLocalRoot != await client.getMerkleRoot()) {
        await client.syncWithMerkle(remoteRoot: await client.getMerkleRoot(), depth: 0);
      }

      expect(client.syncCalled, isFalse);
    });
  });
}
