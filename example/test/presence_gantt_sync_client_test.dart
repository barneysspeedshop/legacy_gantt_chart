import 'dart:async';

import 'package:example/data/local/presence_gantt_sync_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';

class _Client implements GanttSyncClient {
  final incoming = StreamController<Operation>();
  final sent = <Operation>[];
  final List<Operation> initial;

  _Client(this.initial);

  @override
  Stream<Operation> get operationStream => incoming.stream;
  @override
  Future<void> sendOperation(Operation operation) async => sent.add(operation);
  @override
  Future<void> sendOperations(List<Operation> operations) async => sent.addAll(operations);
  @override
  Future<List<Operation>> getInitialState() async => initial;
  @override
  Stream<int> get outboundPendingCount => Stream.value(0);
  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(processed: 0, total: 0));
  @override
  Future<String> getMerkleRoot() async => '';
  @override
  Future<void> syncWithMerkle({required MerkleTree localTree}) async {}
  @override
  Hlc get currentHlc => Hlc.fromIntTimestamp(1);
  @override
  String get actorId => 'test-actor';
}

Operation _operation(String type) =>
    Operation(type: type, data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'peer');

void main() {
  test('chart receives and sends presence without applying or duplicating entity commands', () async {
    final operations = [
      _operation('INSERT_TASK'),
      _operation('UPDATE_TASK'),
      _operation('RESET_DATA'),
      _operation('BATCH_UPDATE'),
      _operation('INSERT_RESOURCE'),
      _operation('DELETE_DEPENDENCY'),
      _operation('CURSOR_MOVE'),
      _operation('GHOST_UPDATE'),
      _operation('PRESENCE_UPDATE'),
    ];
    final inner = _Client(operations);
    final client = PresenceGanttSyncClient(inner);
    final received = client.operationStream.toList();
    operations.forEach(inner.incoming.add);
    await inner.incoming.close();
    expect((await received).map((op) => op.type), ['CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE']);
    expect((await client.getInitialState()).map((op) => op.type), ['CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE']);
    await client.sendOperations(operations);
    await client.sendOperation(_operation('DELETE_TASK'));
    await client.sendOperation(_operation('CURSOR_MOVE'));
    expect(inner.sent.map((op) => op.type), ['CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE', 'CURSOR_MOVE']);
    expect(client.actorId, 'test-actor');
    expect(client.currentHlc, inner.currentHlc);
  });
}
