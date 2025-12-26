import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:example/view_models/gantt_view_model.dart';

class MockGanttSyncClient implements GanttSyncClient {
  final _controller = StreamController<Operation>.broadcast();

  @override
  Stream<Operation> get operationStream => _controller.stream;

  void emit(Operation op) => _controller.add(op);

  @override
  Future<List<Operation>> getInitialState() async => [];

  @override
  Stream<SyncProgress> get inboundProgress => const Stream.empty();

  void connect(String tenantId, {Hlc? lastSyncedTimestamp}) {}

  @override
  Hlc get currentHlc => Hlc.fromDate(DateTime.now(), 'mock');

  @override
  Stream<int> get outboundPendingCount => const Stream.empty();

  @override
  Future<void> sendOperation(Operation operation) async {}

  @override
  Future<void> sendOperations(List<Operation> operations) async {}
  Future<void> dispose() async => _controller.close();
}

void main() {
  test('GanttViewModel processes operations sequentially', () async {
    final viewModel = GanttViewModel();
    final mockClient = MockGanttSyncClient();

    // Inject mocks
    viewModel.loginFunction = ({required uri, required username, required password}) async => 'dummy_token';

    // syncClientFactory expects: GanttSyncClient Function({required Uri uri, required String authToken})
    viewModel.syncClientFactory = ({required uri, required authToken}) => mockClient;

    // Connect
    await viewModel.connectSync(
      uri: 'ws://localhost',
      tenantId: 'test_tenant',
      username: 'user',
      password: 'pw',
    );

    final ops = List.generate(
        50,
        (i) => Operation(
              type: 'INSERT_TASK',
              data: {'id': 'task_$i', 'name': 'Task $i', 'rowId': 'row_1', 'start_date': 0, 'end_date': 1000},
              timestamp: Hlc.fromIntTimestamp(i),
              actorId: 'test',
            ));

    ops.forEach(mockClient.emit);

    // Wait for processing
    await Future.delayed(const Duration(milliseconds: 500));

    // If no exceptions thrown and test finishes, pass.
  });
}
