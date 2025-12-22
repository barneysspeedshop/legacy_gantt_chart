import 'package:flutter_test/flutter_test.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:mocktail/mocktail.dart';

class MockGanttSyncClient extends Mock implements GanttSyncClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GanttViewModel Optimization', () {
    late GanttViewModel viewModel;
    late MockGanttSyncClient mockSyncClient;

    setUp(() {
      viewModel = GanttViewModel();
      mockSyncClient = MockGanttSyncClient();
      viewModel.setSyncClient(mockSyncClient);
    });

    test('optimizeSchedule sends OPTIMIZE_SCHEDULE operation', () async {
      // Arrange
      registerFallbackValue(Operation(type: 'dummy', data: {}, timestamp: 0, actorId: 'dummy'));
      when(() => mockSyncClient.sendOperation(any())).thenAnswer((_) async {});

      // Act
      await viewModel.optimizeSchedule();

      // Assert
      final captured = verify(() => mockSyncClient.sendOperation(captureAny())).captured;
      expect(captured.length, 1);
      final op = captured.first as Operation;
      expect(op.type, 'OPTIMIZE_SCHEDULE');
      expect(op.actorId, 'local-user');
    });
  });
}
