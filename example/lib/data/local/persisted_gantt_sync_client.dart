import 'package:legacy_gantt_chart/offline_sync.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:synchronized/synchronized.dart';

import 'protocol_state_store.dart';

/// Records local operations because the server does not echo them to the sender.
class PersistedGanttSyncClient extends OfflineGanttSyncClient {
  final ProtocolStateStore Function() protocolState;
  final Future<void> Function()? settleIncoming;
  final Future<void> Function(ProtocolStateStore)? enqueueCanonicalRepair;
  final _merkleRepairLock = Lock();

  PersistedGanttSyncClient(super.db, {required this.protocolState, this.settleIncoming, this.enqueueCanonicalRepair});

  @override
  Future<List<Map<String, Object?>>> loadPendingOperations() => protocolState().loadPendingOperations();

  @override
  Future<void> persistOperations(List<Operation> operations) async {
    final commit = await protocolState().applyOperations(operations, local: true, enqueue: true);
    final clock = commit.state.latestClock;
    if (clock != null) observeClock(clock);
  }

  @override
  Future<void> syncWithMerkle({required MerkleTree localTree}) => _merkleRepairLock.synchronized(() async {
    await ready;
    final state = protocolState();
    final generation = connectionGeneration;
    for (var attempt = 0; attempt < 3; attempt++) {
      _requireConnected(state, generation);
      await settleIncoming?.call();
      final remoteRoot = await getMerkleRoot();
      _requireConnected(state, generation);
      await settleIncoming?.call();
      final freshTree = await state.computeMerkleTree();
      _requireConnected(state, generation);
      if (freshTree.root.hash == remoteRoot) return;

      // Requeue accepted records with their original clocks, even when their
      // original socket handoff succeeded but never reached server storage.
      _requireConnected(state, generation);
      if (enqueueCanonicalRepair case final enqueue?) {
        await enqueue(state);
      } else {
        await state.enqueueRepair();
      }
      _requireConnected(state, generation);
      await flushPending();
      _requireConnected(state, generation);
      if (await state.hasPendingOperations()) {
        throw StateError('Merkle repair could not hand off the durable outbox.');
      }
      final pullTree = await state.computeMerkleTree();
      _requireConnected(state, generation);
      await super.syncWithMerkle(localTree: pullTree);
      await settleIncoming?.call();
    }
    _requireConnected(state, generation);
    final remoteRoot = await getMerkleRoot();
    await settleIncoming?.call();
    final localRoot = (await state.computeMerkleTree()).root.hash;
    _requireConnected(state, generation);
    if (localRoot != remoteRoot) {
      throw StateError('Merkle repair did not converge after three attempts.');
    }
    _requireConnected(state, generation);
  });

  void _requireConnected(ProtocolStateStore state, int generation) {
    if (!isConnected || generation != connectionGeneration || !identical(state, protocolState())) {
      throw StateError('Merkle repair requires an active connection.');
    }
  }
}
