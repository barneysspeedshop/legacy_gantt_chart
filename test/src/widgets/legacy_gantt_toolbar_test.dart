import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  group('LegacyGanttToolbar', () {
    late LegacyGanttController controller;
    late LegacyGanttTheme theme;

    setUp(() {
      controller = LegacyGanttController(
        initialVisibleStartDate: DateTime(2023, 1, 1),
        initialVisibleEndDate: DateTime(2023, 1, 7),
      );
      theme = LegacyGanttTheme.fromTheme(ThemeData.light());
    });

    testWidgets('renders all tool buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LegacyGanttToolbar(
              controller: controller,
              theme: theme,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.open_with), findsOneWidget); // Move
      expect(find.byIcon(Icons.select_all), findsOneWidget); // Select
      expect(find.byIcon(Icons.edit), findsOneWidget); // Draw
      expect(find.byIcon(Icons.account_tree), findsOneWidget); // Link
    });

    testWidgets('initial tool selection is correct', (tester) async {
      // Default tool is usually move (index 0)
      controller.setTool(GanttTool.move);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LegacyGanttToolbar(
              controller: controller,
              theme: theme,
            ),
          ),
        ),
      );

      final toggleButtons = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(toggleButtons.isSelected[0], isTrue); // Move
      expect(toggleButtons.isSelected[1], isFalse); // Select
      expect(toggleButtons.isSelected[2], isFalse); // Draw
      expect(toggleButtons.isSelected[3], isFalse); // Link
    });

    testWidgets('tapping buttons updates controller tool', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LegacyGanttToolbar(
              controller: controller,
              theme: theme,
            ),
          ),
        ),
      );

      // Tap Select Tool (Index 1)
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();
      expect(controller.currentTool, GanttTool.select);

      // Tap Draw Tool (Index 2)
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      expect(controller.currentTool, GanttTool.draw);

      // Tap Link Tool (Index 3)
      await tester.tap(find.byIcon(Icons.account_tree));
      await tester.pump();
      expect(controller.currentTool, GanttTool.drawDependencies);

      // Tap Move Tool (Index 0)
      await tester.tap(find.byIcon(Icons.open_with));
      await tester.pump();
      expect(controller.currentTool, GanttTool.move);
    });

    testWidgets('selection text appears when tasks are selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LegacyGanttToolbar(
              controller: controller,
              theme: theme,
            ),
          ),
        ),
      );

      expect(find.textContaining('selected'), findsNothing);

      // Select tasks
      controller.setSelectedTaskIds({'task1'});
      await tester.pump();

      expect(find.text('1 tasks selected'), findsOneWidget);

      controller.setSelectedTaskIds({'task1', 'task2'});

      await tester.pump();

      expect(find.text('2 tasks selected'), findsOneWidget);

      controller.clearSelection();
      await tester.pump();

      expect(find.textContaining('selected'), findsNothing);
    });
  });
}
