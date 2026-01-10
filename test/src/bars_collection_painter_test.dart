import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/bars_collection_painter.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_theme.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_dependency.dart';
import 'package:legacy_gantt_chart/src/models/remote_ghost.dart';

void main() {
  group('BarsCollectionPainter', () {
    // Basic setup data common to most tests
    const row1 = LegacyGanttRow(id: 'r1');
    final task1 = LegacyGanttTask(
      id: 't1',
      rowId: 'r1',
      start: DateTime(2023, 1, 1),
      end: DateTime(2023, 1, 5),
      name: 'Task 1',
    );
    final theme = LegacyGanttTheme(
      backgroundColor: Colors.white,
      barColorPrimary: Colors.blue,
      barColorSecondary: Colors.lightBlue,
      textColor: Colors.black,
      taskTextStyle: const TextStyle(color: Colors.black),
    );

    double mockScale(DateTime date) => date.difference(DateTime(2023, 1, 1)).inDays * 20.0;

    // Helper to find the CustomPaint using our specific painter
    Finder findPainter() => find.descendant(
          of: find.byType(CustomPaint),
          matching:
              find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BarsCollectionPainter),
        );

    test('shouldRepaint returns true when data changes', () {
      final oldPainter = BarsCollectionPainter(
        tasksByRow: {},
        data: [task1],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
        scale: mockScale,
        rowHeight: 30.0,
        theme: theme,
        conflictIndicators: [],
      );

      final newPainter = BarsCollectionPainter(
        tasksByRow: {},
        data: [task1, LegacyGanttTask(id: 't2', rowId: 'r1', start: DateTime.now(), end: DateTime.now())],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
        scale: mockScale,
        rowHeight: 30.0,
        theme: theme,
        conflictIndicators: [],
      );

      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    });

    test('shouldRepaint returns false when nothing changes', () {
      final oldPainter = BarsCollectionPainter(
        tasksByRow: {},
        data: [task1],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
        scale: mockScale,
        rowHeight: 30.0,
        theme: theme,
        conflictIndicators: [],
      );

      final newPainter = BarsCollectionPainter(
        tasksByRow: {},
        data: [task1],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
        scale: mockScale,
        rowHeight: 30.0,
        theme: theme,
        conflictIndicators: [],
      );

      expect(newPainter.shouldRepaint(oldPainter), isFalse);
    });

    testWidgets('paints basic task without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(500, 500),
              painter: BarsCollectionPainter(
                tasksByRow: {},
                data: [task1],
                visibleRows: [row1],
                rowMaxStackDepth: {'r1': 1},
                domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
                scale: mockScale,
                rowHeight: 50.0,
                theme: theme,
                conflictIndicators: [],
              ),
            ),
          ),
        ),
      );

      expect(findPainter(), findsOneWidget);
    });

    testWidgets('paints conflict indicators without error', (WidgetTester tester) async {
      final conflict = LegacyGanttTask(
        id: 'conflict1',
        rowId: 'r1',
        start: DateTime(2023, 1, 2),
        end: DateTime(2023, 1, 3),
        isOverlapIndicator: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(500, 500),
              painter: BarsCollectionPainter(
                tasksByRow: {},
                data: [task1, conflict],
                visibleRows: [row1],
                rowMaxStackDepth: {'r1': 1},
                domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
                scale: mockScale,
                rowHeight: 50.0,
                theme: theme,
                conflictIndicators: [conflict],
              ),
            ),
          ),
        ),
      );

      expect(findPainter(), findsOneWidget);
    });

    testWidgets('paints single dependency without error', (WidgetTester tester) async {
      final task2 = LegacyGanttTask(
        id: 't2',
        rowId: 'r1',
        start: DateTime(2023, 1, 6),
        end: DateTime(2023, 1, 8),
        name: 'Task 2',
      );

      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 't1',
        successorTaskId: 't2',
        type: DependencyType.finishToStart,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(500, 500),
              painter: BarsCollectionPainter(
                tasksByRow: {},
                data: [task1, task2],
                visibleRows: [row1],
                rowMaxStackDepth: {'r1': 1},
                domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
                scale: mockScale,
                rowHeight: 50.0,
                theme: theme,
                conflictIndicators: [],
                dependencies: [dependency],
              ),
            ),
          ),
        ),
      );

      expect(findPainter(), findsOneWidget);
    });

    testWidgets('paints all dependency types without error', (WidgetTester tester) async {
      final task2 = LegacyGanttTask(id: 't2', rowId: 'r1', start: DateTime(2023, 1, 6), end: DateTime(2023, 1, 8));
      final task3 = LegacyGanttTask(id: 't3', rowId: 'r1', start: DateTime(2023, 1, 6), end: DateTime(2023, 1, 8));
      final task4 = LegacyGanttTask(id: 't4', rowId: 'r1', start: DateTime(2023, 1, 6), end: DateTime(2023, 1, 8));
      final task5 = LegacyGanttTask(id: 't5', rowId: 'r1', start: DateTime(2023, 1, 6), end: DateTime(2023, 1, 8));

      final deps = [
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't2', type: DependencyType.startToStart),
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't3', type: DependencyType.finishToFinish),
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't4', type: DependencyType.startToFinish),
        const LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't5', type: DependencyType.contained),
      ];

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(800, 600),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [task1, task2, task3, task4, task5],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 5},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 20)],
          scale: mockScale,
          rowHeight: 40.0,
          theme: theme,
          conflictIndicators: [],
          dependencies: deps,
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints drag and drop ghost bar', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [task1],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          draggedTaskId: 't1',
          ghostTaskStart: DateTime(2023, 1, 3),
          ghostTaskEnd: DateTime(2023, 1, 7),
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints milestones and summaries', (WidgetTester tester) async {
      final milestone = LegacyGanttTask(
          id: 'm1', rowId: 'r1', start: DateTime(2023, 1, 2), end: DateTime(2023, 1, 2), isMilestone: true);
      final summary = LegacyGanttTask(
          id: 's1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 9), isSummary: true);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [milestone, summary],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 2},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints segments and highlights', (WidgetTester tester) async {
      final segmented = LegacyGanttTask(
          id: 'seq1',
          rowId: 'r1',
          start: DateTime(2023, 1, 1),
          end: DateTime(2023, 1, 5),
          segments: [LegacyGanttTaskSegment(start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3))]);
      final highlight = LegacyGanttTask(
          id: 'h1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 8), isTimeRangeHighlight: true);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [segmented, highlight],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 2},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints empty space highlight', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          hoveredRowId: 'r1',
          hoveredDate: DateTime(2023, 1, 2),
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints dependency creation line', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [task1],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          dependencyDragStartTaskId: 't1',
          dependencyDragCurrentPosition: const Offset(100, 100),
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('respects hasCustomTaskBuilder', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [task1],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          hasCustomTaskBuilder: true,
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('respects hasCustomTaskContentBuilder', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [task1],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          hasCustomTaskContentBuilder: true,
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('handles missing tasks in dependencies gracefully', (WidgetTester tester) async {
      const badDep = LegacyGanttTaskDependency(
          predecessorTaskId: 't1', successorTaskId: 'nonExistent', type: DependencyType.finishToStart);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [task1],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          dependencies: [badDep],
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints contained dependency background', (WidgetTester tester) async {
      final parent = LegacyGanttTask(
          id: 'parent', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 10), isSummary: true);
      final child = LegacyGanttTask(id: 'child', rowId: 'r1', start: DateTime(2023, 1, 2), end: DateTime(2023, 1, 5));
      const dep = LegacyGanttTaskDependency(
          predecessorTaskId: 'parent', successorTaskId: 'child', type: DependencyType.contained);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [parent, child],
          visibleRows: [row1, const LegacyGanttRow(id: 'r2')],
          rowMaxStackDepth: {'r1': 1, 'r2': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          dependencies: [dep],
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints row borders when enabled', (WidgetTester tester) async {
      final borderTheme = LegacyGanttTheme(
        showRowBorders: true,
        rowBorderColor: Colors.red,
        backgroundColor: Colors.white,
        barColorPrimary: Colors.blue,
        barColorSecondary: Colors.lightBlue,
        textColor: Colors.black,
        taskTextStyle: const TextStyle(color: Colors.black),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [task1],
              visibleRows: [row1, const LegacyGanttRow(id: 'r2')],
              rowMaxStackDepth: {'r1': 1, 'r2': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: borderTheme,
              conflictIndicators: [],
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints milestone handles correctly when dependency creation enabled', (WidgetTester tester) async {
      final milestone = LegacyGanttTask(
          id: 'm1', rowId: 'r1', start: DateTime(2023, 1, 2), end: DateTime(2023, 1, 2), isMilestone: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [milestone],
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              enableDependencyCreation: true,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('handles conflict indicators for summary tasks', (WidgetTester tester) async {
      final summary = LegacyGanttTask(
          id: 's1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 5), isSummary: true);
      final conflict = LegacyGanttTask(
        id: 'conflict1',
        rowId: 'r1',
        start: DateTime(2023, 1, 3), // Falls within summary
        end: DateTime(2023, 1, 4),
        isOverlapIndicator: true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [
                summary,
                conflict
              ], // Note: conflict indicators are usually separate but painter logic re-checks data for summary conflict
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [conflict],
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('handles conflict indicators obscuring text', (WidgetTester tester) async {
      // This test ensures no error when a task has a conflict, which triggers the logic to skip drawing text
      // coverage for: "if (isInConflict) { continue; }"
      final taskWithConflict = LegacyGanttTask(
          id: 't1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 5), name: 'Conflict Task');
      final conflict = LegacyGanttTask(
          id: 'c1', rowId: 'r1', start: DateTime(2023, 1, 2), end: DateTime(2023, 1, 3), isOverlapIndicator: true);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [taskWithConflict],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [conflict],
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('handles dragged task that does not exist', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [task1],
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              draggedTaskId: 'unknown_task',
              ghostTaskStart: DateTime(2023, 1, 3),
              ghostTaskEnd: DateTime(2023, 1, 7),
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints empty space highlight with plus icon', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomPaint(
        size: const Size(500, 500),
        painter: BarsCollectionPainter(
          tasksByRow: {},
          data: [],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
          scale: mockScale,
          rowHeight: 50.0,
          theme: theme,
          conflictIndicators: [],
          hoveredRowId: 'r1',
          hoveredDate: DateTime(2023, 1, 2),
        ),
      ))));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints complex finishToStart dependency (successor to left)', (WidgetTester tester) async {
      final t1 = LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 5), end: DateTime(2023, 1, 8));
      final t2 = LegacyGanttTask(id: 't2', rowId: 'r2', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3));
      const dep = LegacyGanttTaskDependency(
        predecessorTaskId: 't1',
        successorTaskId: 't2',
        type: DependencyType.finishToStart,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [t1, t2],
              visibleRows: [row1, const LegacyGanttRow(id: 'r2')],
              rowMaxStackDepth: {'r1': 1, 'r2': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              dependencies: [dep],
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints startToStart dependency', (WidgetTester tester) async {
      // Same row coverage
      final t1 = LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3));
      final t2 = LegacyGanttTask(id: 't2', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 4));
      // Different row coverage
      final t3 = LegacyGanttTask(id: 't3', rowId: 'r2', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3));

      final deps = [
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't2', type: DependencyType.startToStart),
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't3', type: DependencyType.startToStart),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [t1, t2, t3],
              visibleRows: [row1, const LegacyGanttRow(id: 'r2')],
              rowMaxStackDepth: {'r1': 2, 'r2': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              dependencies: deps,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints finishToFinish dependency', (WidgetTester tester) async {
      // Same row coverage
      final t1 = LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3));
      final t2 = LegacyGanttTask(id: 't2', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3));
      // Different row coverage
      final t3 = LegacyGanttTask(id: 't3', rowId: 'r2', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3));

      final deps = [
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't2', type: DependencyType.finishToFinish),
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't3', type: DependencyType.finishToFinish),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [t1, t2, t3],
              visibleRows: [row1, const LegacyGanttRow(id: 'r2')],
              rowMaxStackDepth: {'r1': 2, 'r2': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              dependencies: deps,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints startToFinish dependency', (WidgetTester tester) async {
      // Cover branch where endX < midX (successor far left)
      final t1 = LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 5), end: DateTime(2023, 1, 8));
      final t2 =
          LegacyGanttTask(id: 't2', rowId: 'r2', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 2)); // far left
      // Cover branch where endX >= midX (successor right or close)
      final t3 = LegacyGanttTask(id: 't3', rowId: 'r2', start: DateTime(2023, 1, 8), end: DateTime(2023, 1, 9));

      final deps = [
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't2', type: DependencyType.startToFinish),
        const LegacyGanttTaskDependency(
            predecessorTaskId: 't1', successorTaskId: 't3', type: DependencyType.startToFinish),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [t1, t2, t3],
              visibleRows: [row1, const LegacyGanttRow(id: 'r2')],
              rowMaxStackDepth: {'r1': 1, 'r2': 2}, // t2, t3 in r2
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              dependencies: deps,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints task progress', (WidgetTester tester) async {
      final taskWithProgress = LegacyGanttTask(
        id: 't1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 5),
        completion: 0.5,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [taskWithProgress],
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('highlights hovered task for dependency', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [task1],
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              enableDependencyCreation: true,
              hoveredTaskForDependency: 't1',
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });

    testWidgets('paints remote ghost milestone', (WidgetTester tester) async {
      final milestoneTask = LegacyGanttTask(
        id: 'm1',
        rowId: 'r1',
        start: DateTime(2023, 1, 5),
        end: DateTime(2023, 1, 5),
        isMilestone: true,
      );

      final ghost = RemoteGhost(
        userId: 'user2',
        taskId: 'm1',
        start: DateTime(2023, 1, 6),
        end: DateTime(2023, 1, 6),
        lastUpdated: DateTime.now(),
        // other fields optional/defaulted
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [milestoneTask],
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              remoteGhosts: {'user2': ghost},
            ),
          ),
        ),
      ));
      expect(findPainter(), findsWidgets);
    });
  });
}
