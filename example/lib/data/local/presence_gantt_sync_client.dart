import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';

/// The example owns entity state; its chart receives only ephemeral presence.
class PresenceGanttSyncClient implements GanttSyncClient {
  final GanttSyncClient inner;

  PresenceGanttSyncClient(this.inner);

  static bool _isPresence(Operation operation) =>
      const {'CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE'}.contains(operation.type);

  @override
  Stream<Operation> get operationStream => inner.operationStream.where(_isPresence);

  @override
  Future<void> sendOperation(Operation operation) async {
    if (_isPresence(operation)) await inner.sendOperation(operation);
  }

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    final presence = operations.where(_isPresence).toList();
    if (presence.isNotEmpty) await inner.sendOperations(presence);
  }

  @override
  Future<List<Operation>> getInitialState() async => (await inner.getInitialState()).where(_isPresence).toList();

  @override
  Stream<int> get outboundPendingCount => inner.outboundPendingCount;

  @override
  Stream<SyncProgress> get inboundProgress => inner.inboundProgress;

  @override
  Future<String> getMerkleRoot() => inner.getMerkleRoot();

  @override
  Future<void> syncWithMerkle({required MerkleTree localTree}) => inner.syncWithMerkle(localTree: localTree);

  @override
  Hlc get currentHlc => inner.currentHlc;

  @override
  String get actorId => inner.actorId;
}
