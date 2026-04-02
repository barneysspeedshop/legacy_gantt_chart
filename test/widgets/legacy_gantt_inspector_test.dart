import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/src/widgets/legacy_gantt_inspector.dart';

class MockCausalIntegrityAudit extends Mock implements CausalIntegrityAudit {}

class MockOperation extends Mock implements Operation {}

class MockConflictAnalysis extends Mock implements ConflictAnalysis {}

class MockHlc extends Mock implements Hlc {}

void main() {
  late MockCausalIntegrityAudit mockAudit;
  late LegacyGanttTask testTask;

  setUpAll(() {
    registerFallbackValue(MockOperation());
  });

  setUp(() {
    mockAudit = MockCausalIntegrityAudit();
    testTask = LegacyGanttTask(
      id: 'task-1',
      rowId: 'row-1',
      start: DateTime(2024, 1, 1),
      end: DateTime(2024, 1, 2),
      name: 'Test Task',
    );

    // Default mock behavior
    when(() => mockAudit.getHistoryForTask(any())).thenReturn([]);
  });

  Widget createWidgetUnderTest(LegacyGanttTask task) => MaterialApp(
        home: Scaffold(
          body: LegacyGanttInspector(
            taskId: task.id,
            task: task,
            auditEngine: mockAudit,
          ),
        ),
      );

  group('LegacyGanttInspector - Tabs & Navigation', () {
    testWidgets('renders all tabs and can switch between them', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testTask));

      expect(find.textContaining('Causal Integrity Inspector'), findsOneWidget);
      expect(find.text('Current Provenance'), findsOneWidget);
      expect(find.text('Session History'), findsOneWidget);
      expect(find.text('Causal Graph'), findsOneWidget);

      // Verify Provenance is initial tab
      expect(find.text('Global State'), findsOneWidget);

      // Switch to History
      await tester.tap(find.text('Session History'));
      await tester.pumpAndSettle();
      expect(find.text('No session history recorded for this task.'), findsOneWidget);

      // Switch to Causal Graph
      await tester.tap(find.text('Causal Graph'));
      await tester.pumpAndSettle();
      expect(find.text('Not enough history to visualize causal graph.'), findsOneWidget);
    });

    testWidgets('close button pops the navigator', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LegacyGanttInspector(
                        taskId: testTask.id,
                        task: testTask,
                        auditEngine: mockAudit,
                      ),
                    ));
                  },
                  child: const Text('Open'),
                )),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(LegacyGanttInspector), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(LegacyGanttInspector), findsNothing);
    });
  });

  group('Tab 1: Provenance', () {
    testWidgets('displays field-level provenance when available', (tester) async {
      final taskWithProvenance = testTask.copyWith(
        fieldTimestamps: {
          'start': Hlc.parse('2024-01-01T00:00:00.000Z-0001-node1'),
          'end': Hlc.parse('2024-01-01T01:00:00.000Z-0002-node2'),
        },
      );

      await tester.pumpWidget(createWidgetUnderTest(taskWithProvenance));

      expect(find.text('start'), findsOneWidget);
      expect(find.text('end'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
      expect(find.text('node1'), findsOneWidget);
      expect(find.text('node2'), findsOneWidget);
    });

    testWidgets('shows empty state for provenance', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testTask));
      expect(find.textContaining('No field-level provenance data available'), findsOneWidget);
    });
  });

  group('Tab 2: Session History', () {
    testWidgets('displays operations history', (tester) async {
      final mockOp = MockOperation();
      final mockHlcVal = Hlc.parse('2024-01-01T12:00:00.000Z-0001-node1');

      when(() => mockOp.type).thenReturn('UPDATE');
      when(() => mockOp.timestamp).thenReturn(mockHlcVal);
      when(() => mockOp.actorId).thenReturn('node1');
      when(() => mockOp.data).thenReturn({'name': 'New Name'});

      when(() => mockAudit.getHistoryForTask('task-1')).thenReturn([mockOp]);

      await tester.pumpWidget(createWidgetUnderTest(testTask));
      await tester.tap(find.text('Session History'));
      await tester.pumpAndSettle();

      expect(find.text('UPDATE'), findsOneWidget);
      expect(find.textContaining('node1'), findsOneWidget);

      // Expand tile
      await tester.tap(find.text('UPDATE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('New Name'), findsOneWidget);
    });
  });

  group('Tab 3: Causal Graph', () {
    testWidgets('shows causal graph with conflict resolution', (tester) async {
      final op1 = MockOperation();
      final op2 = MockOperation();
      final hlc1 = Hlc.parse('2024-01-01T00:00:00.000Z-0001-node1');
      final hlc2 = Hlc.parse('2024-01-01T00:00:01.000Z-0002-node2');

      when(() => op1.type).thenReturn('UPDATE');
      when(() => op1.timestamp).thenReturn(hlc1);
      when(() => op1.actorId).thenReturn('node1');
      when(() => op1.data).thenReturn({'start': 1000});

      when(() => op2.type).thenReturn('UPDATE');
      when(() => op2.timestamp).thenReturn(hlc2);
      when(() => op2.actorId).thenReturn('node2');
      when(() => op2.data).thenReturn({'start': 2000});

      when(() => mockAudit.getHistoryForTask('task-1')).thenReturn([op1, op2]);

      final mockAnalysis = MockConflictAnalysis();
      when(() => mockAnalysis.winner).thenReturn(op2);
      when(() => mockAnalysis.reason).thenReturn('Higher timestamp wins');

      when(() => mockAudit.analyzeConflict(op1, op2, 'start')).thenReturn(mockAnalysis);

      await tester.pumpWidget(createWidgetUnderTest(testTask));
      await tester.tap(find.text('Causal Graph'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Comparing'), findsOneWidget);
      expect(find.textContaining('Winner: Incoming (Op B)'), findsOneWidget);
      expect(find.textContaining('Higher timestamp wins'), findsOneWidget);
    });
  });
}
