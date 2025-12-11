// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import '../lib/view_models/gantt_view_model.dart';
import '../lib/data/local/gantt_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// NOTE: run this test from `legacy_gantt_chart/example` directory using `flutter test`

void main() {
  test('Simulate Cold Start and Connect Race', () async {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Reset DB to ensure cold start
    await GanttDb.reset();

    // Create ViewModel (simulates app start)
    // using in-memory DB for test speed/isolation
    GanttDb.overridePath = ':memory:';

    final viewModel = GanttViewModel(useLocalDatabase: true);

    // Mock Login
    viewModel.loginFunction =
        ({required Uri uri, required String username, required String password}) async => 'mock_token';

    // Inject mock client
    viewModel.syncClientFactory = ({Uri? uri, String? authToken}) => MockWebSocketClient();

    await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'test', username: 'u', password: 'p');

    // wait for async ops
    await Future.delayed(const Duration(seconds: 1));

    // Access tasks - verify the task from "server" exists and has correct data
    expect(viewModel.ganttTasks.any((t) => t.id == 't1'), true, reason: 'Task t1 should be present after sync');
    final task = viewModel.ganttTasks.firstWhere((t) => t.id == 't1');
    expect(task.rowId, 'r1', reason: 'Task should have correct rowId from sync');
    expect(task.color?.toARGB32(), 0xFFFF0000, reason: 'Task should have correct color from sync');
  });
}

class MockWebSocketClient extends WebSocketGanttSyncClient {
  MockWebSocketClient() : super(uri: Uri.parse('ws://mock'), authToken: 'token');

  final _mockOpController = StreamController<Operation>.broadcast();

  @override
  Stream<Operation> get operationStream => _mockOpController.stream;

  @override
  void connect(String tenantId) {
    // Emulate immediate server response
    Future.microtask(() {
      print('MockClient: Sending UPDATE_TASK');
      _mockOpController.add(Operation(
          type: 'UPDATE_TASK',
          data: {
            'data': {
              'id': 't1',
              'name': 'Remote Task',
              'start_date': 0,
              'end_date': 1000,
              'rowId': 'r1', // Simulate corrected server payload
              'color': '#FF0000',
            }
          },
          timestamp: 1,
          actorId: 'server'));
    });
  }

  @override
  Future<void> sendOperation(Operation operation) async {
    // No-op for mock
  }
}
