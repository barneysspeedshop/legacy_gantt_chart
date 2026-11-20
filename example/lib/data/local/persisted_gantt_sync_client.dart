import 'package:legacy_gantt_chart/offline_sync.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';

import 'protocol_state_store.dart';

/// Records local operations because the server does not echo them to the sender.
class PersistedGanttSyncClient extends OfflineGanttSyncClient {
  final ProtocolStateStore Function() protocolState;

  PersistedGanttSyncClient(super.db, {required this.protocolState});

  @override
  Future<void> persistOperations(List<Operation> operations) async {
    final commit = await protocolState().applyOperations(operations, local: true, enqueue: true);
    final clock = commit.state.latestClock;
    if (clock != null) observeClock(clock);
  }
}
