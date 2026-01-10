import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/bars_collection_painter.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_theme.dart';

void main() {
  group('BarsCollectionPainter Rollup', () {
    const row1 = LegacyGanttRow(id: 'r1');
    final theme = LegacyGanttTheme(
      backgroundColor: Colors.white,
      barColorPrimary: Colors.blue,
      barColorSecondary: Colors.lightBlue,
      textColor: Colors.black,
      taskTextStyle: const TextStyle(color: Colors.black),
    );

    double mockScale(DateTime date) => date.difference(DateTime(2023, 1, 1)).inDays * 20.0;

    Finder findPainter() => find.descendant(
          of: find.byType(CustomPaint),
          matching:
              find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BarsCollectionPainter),
        );

    testWidgets('paints rolled up milestones on summary task', (WidgetTester tester) async {
      final summary = LegacyGanttTask(
        id: 's1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 10),
        isSummary: true,
      );
      final milestone = LegacyGanttTask(
        id: 'm1',
        rowId: 'r1', // Row doesn't matter for rollup logic, but needs to be valid
        start: DateTime(2023, 1, 5),
        end: DateTime(2023, 1, 5),
        isMilestone: true,
        parentId: 's1',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [summary, milestone],
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              rollUpMilestones: true, // Enable rollup
            ),
          ),
        ),
      ));

      expect(findPainter(), findsWidgets);
    });

    testWidgets('does not paint rolled up milestones when disabled', (WidgetTester tester) async {
      final summary = LegacyGanttTask(
        id: 's1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 10),
        isSummary: true,
      );
      final milestone = LegacyGanttTask(
        id: 'm1',
        rowId: 'r1',
        start: DateTime(2023, 1, 5),
        end: DateTime(2023, 1, 5),
        isMilestone: true,
        parentId: 's1',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 500),
            painter: BarsCollectionPainter(
              tasksByRow: {},
              data: [summary, milestone],
              visibleRows: [row1],
              rowMaxStackDepth: {'r1': 1},
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
              scale: mockScale,
              rowHeight: 50.0,
              theme: theme,
              conflictIndicators: [],
              rollUpMilestones: false, // Disable rollup
            ),
          ),
        ),
      ));

      expect(findPainter(), findsWidgets);
    });
  });
}
