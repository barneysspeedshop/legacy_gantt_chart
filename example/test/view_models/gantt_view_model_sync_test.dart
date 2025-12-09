// import 'dart:async';

// import 'package:flutter_test/flutter_test.dart';
// import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
// // ignore: avoid_relative_lib_imports
// import '../../lib/sync/websocket_gantt_sync_client.dart';
// // ignore: avoid_relative_lib_imports
// import '../../lib/view_models/gantt_view_model.dart';

// class FakeSyncClient implements WebSocketGanttSyncClient {
//   final _operationController = StreamController<Operation>.broadcast();
//   final _connectionStateController = StreamController<bool>.broadcast();
//   final List<Operation> sentOperations = [];
//   bool isConnected = false;
//   bool isDisposed = false;

//   @override
//   Stream<Operation> get operationStream => _operationController.stream;

//   @override
//   Stream<bool> get connectionStateStream => _connectionStateController.stream;

//   @override
//   Future<void> connect(String tenantId) async {
//     isConnected = true;
//     _connectionStateController.add(true);
//   }

//   @override
//   Future<void> sendOperation(Operation op) async {
//     sentOperations.add(op);
//   }

//   @override
//   Future<void> dispose() async {
//     isDisposed = true;
//     _operationController.close();
//     _connectionStateController.close();
//   }

//   // Helper to simulate connection drop
//   void simulateConnectionDrop() {
//     _connectionStateController.add(false);
//   }

//   // Implement other members as needed (stubs)
//   @override
//   dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
// }

// void main() {
//   TestWidgetsFlutterBinding.ensureInitialized();

//   group('GanttViewModel Sync Integration', () {
//     late GanttViewModel viewModel;
//     late FakeSyncClient fakeClient;

//     setUp(() {
//       viewModel = GanttViewModel(useLocalDatabase: false); // Use memory mode
//       fakeClient = FakeSyncClient();

//       // Inject factories
//       viewModel.loginFunction = ({required uri, required username, required password}) async {
//         if (username == 'valid') return 'fake_token';
//         throw Exception('Invalid credentials');
//       };

//       viewModel.syncClientFactory = ({required uri, required authToken}) => fakeClient;

//       // Ensure no database calls are made
//       // viewModel.seedLocalDatabase();
//     });

//     test('connectSync success', () async {
//       await viewModel.connectSync(
//         uri: 'http://localhost:8080',
//         tenantId: 'tenant1',
//         username: 'valid',
//         password: 'password',
//       );

//       expect(viewModel.isSyncConnected, isTrue);
//       expect(fakeClient.isConnected, isTrue);
//     });

//     test('connectSync failure', () async {
//       await expectLater(
//         viewModel.connectSync(
//           uri: 'http://localhost:8080',
//           tenantId: 'tenant1',
//           username: 'invalid', // Will throw exception
//           password: 'password',
//         ),
//         throwsException,
//       );

//       expect(viewModel.isSyncConnected, isFalse);
//     });

//     test('detects connection drop', () async {
//       await viewModel.connectSync(
//         uri: 'http://localhost:8080',
//         tenantId: 'tenant1',
//         username: 'valid',
//         password: 'password',
//       );

//       expect(viewModel.isSyncConnected, isTrue);

//       // Simulate drop
//       fakeClient.simulateConnectionDrop();

//       // Wait for stream to propogate
//       await Future.delayed(Duration.zero);

//       expect(viewModel.isSyncConnected, isFalse);
//     });

//     test('disconnectSync', () async {
//       await viewModel.connectSync(
//         uri: 'http://localhost:8080',
//         tenantId: 'tenant1',
//         username: 'valid',
//         password: 'password',
//       );

//       viewModel.disconnectSync();

//       expect(viewModel.isSyncConnected, isFalse);
//       expect(fakeClient.isDisposed, isTrue);
//     });

//     // Note: To test handleTaskUpdate sending operations, we need to ensure the task exists.
//     // Since seedLocalDatabase populates data asynchronously or via method, we need to ensure it's ready.
//     // However, in mock mode, it uses _apiResponse.

//     test('handleTaskUpdate sends operation when connected', () async {
//       await viewModel.connectSync(
//         uri: 'http://localhost:8080',
//         tenantId: 'tenant1',
//         username: 'valid',
//         password: 'password',
//       );

//       // Create a dummy task
//       final task = LegacyGanttTask(
//         id: 'task1',
//         rowId: 'row1',
//         start: DateTime(2023, 1, 1),
//         end: DateTime(2023, 1, 2),
//         name: 'Test Task',
//       );

//       // We assume the task exists or we treat it as an update.
//       // handleTaskUpdate logic might check existence.
//       // But let's check if sendOperation is called regardless of local existence logic
//       // (The code shows it sends BEFORE checking local db/mock mode branches, actually it's inside the method).

//       // Let's look at the code:
//       // if (_syncClient != null && _isSyncConnected) { _syncClient!.sendOperation(...) }
//       // So it should send it.

//       viewModel.handleTaskUpdate(
//         task,
//         DateTime(2023, 1, 3), // new start
//         DateTime(2023, 1, 4), // new end
//       );

//       expect(fakeClient.sentOperations, hasLength(1));
//       final op = fakeClient.sentOperations.first;
//       expect(op.type, 'UPDATE');
//       expect(op.data['id'], 'task1');
//       expect(op.data['start_date'], DateTime(2023, 1, 3).millisecondsSinceEpoch);
//     });
//   });
// }
