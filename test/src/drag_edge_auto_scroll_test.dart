import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';

void main() {
  const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');

  // 10 days rendered over 4000px of content width => 400px per day.
  final totalStart = DateTime(2023, 1, 1);
  final totalEnd = DateTime(2023, 1, 11);
  const contentWidth = 4000.0;

  final task1 = LegacyGanttTask(
    id: 't1',
    rowId: 'r1',
    start: DateTime(2023, 1, 1, 8),
    end: DateTime(2023, 1, 1, 12),
    name: 'Task 1',
  );

  Duration pixelsToDuration(double pixels) {
    final totalMs = totalEnd.difference(totalStart).inMilliseconds;
    return Duration(milliseconds: (pixels / contentWidth * totalMs).round());
  }

  Future<ScrollController> pumpScrollableViewport(WidgetTester tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: scrollController,
          child: const SizedBox(width: contentWidth, height: 200),
        ),
      ),
    );

    return scrollController;
  }

  LegacyGanttViewModel createViewModel({
    required ScrollController scrollController,
    void Function(LegacyGanttTask, DateTime, DateTime)? onTaskUpdate,
  }) {
    final viewModel = LegacyGanttViewModel(
      conflictIndicators: [],
      data: [task1],
      dependencies: [],
      visibleRows: [row1],
      rowMaxStackDepth: {'r1': 1},
      rowHeight: 50.0,
      enableDragAndDrop: true,
      enableResize: true,
      enableDragEdgeAutoScroll: true,
      totalGridMin: totalStart.millisecondsSinceEpoch.toDouble(),
      totalGridMax: totalEnd.millisecondsSinceEpoch.toDouble(),
      ganttHorizontalScrollController: scrollController,
      onTaskUpdate: onTaskUpdate,
    );
    viewModel.updateLayout(contentWidth, 200);
    return viewModel;
  }

  testWidgets('scrolling during a drag is compensated into the ghost position', (tester) async {
    final scrollController = await pumpScrollableViewport(tester);
    final viewModel = createViewModel(scrollController: scrollController);
    addTearDown(viewModel.dispose);

    viewModel.onPanStart(
      DragStartDetails(globalPosition: const Offset(400, 25), localPosition: const Offset(400, 25)),
      overrideTask: task1,
      overridePart: TaskPart.body,
    );

    // Pointer moves 100px to the right: ghost follows by 100px worth of time.
    viewModel.onPanUpdate(DragUpdateDetails(
      globalPosition: const Offset(500, 25),
      localPosition: const Offset(500, 25),
    ));
    expect(viewModel.ghostTaskStart, task1.start.add(pixelsToDuration(100)));

    // The viewport scrolls 200px underneath the stationary pointer (e.g. a
    // second finger on a tablet): the ghost must advance by those 200px too.
    scrollController.jumpTo(200);
    viewModel.onPanUpdate(DragUpdateDetails(
      globalPosition: const Offset(500, 25),
      localPosition: const Offset(700, 25),
    ));
    expect(viewModel.ghostTaskStart, task1.start.add(pixelsToDuration(300)));

    viewModel.onPanEnd(DragEndDetails());
  });

  testWidgets('dragging into the edge zone auto-scrolls and moves the task beyond the viewport', (tester) async {
    final scrollController = await pumpScrollableViewport(tester);

    final updates = <(LegacyGanttTask, DateTime, DateTime)>[];
    final viewModel = createViewModel(
      scrollController: scrollController,
      onTaskUpdate: (task, newStart, newEnd) => updates.add((task, newStart, newEnd)),
    );
    addTearDown(viewModel.dispose);

    viewModel.onPanStart(
      DragStartDetails(globalPosition: const Offset(400, 25), localPosition: const Offset(400, 25)),
      overrideTask: task1,
      overridePart: TaskPart.body,
    );

    // Pointer moves into the right edge zone (viewport is 800px wide).
    viewModel.onPanUpdate(DragUpdateDetails(
      globalPosition: const Offset(780, 25),
      localPosition: const Offset(780, 25),
    ));
    final ghostBeforeAutoScroll = viewModel.ghostTaskStart!;

    // Holding the pointer there lets the auto-scroll timer take over.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(scrollController.offset, greaterThan(100));
    expect(viewModel.ghostTaskStart!.isAfter(ghostBeforeAutoScroll), isTrue);

    // The ghost advanced by exactly the pointer delta plus the scrolled offset.
    expect(
      viewModel.ghostTaskStart,
      task1.start.add(pixelsToDuration(380 + scrollController.offset)),
    );

    final offsetAfterDrag = scrollController.offset;
    viewModel.onPanEnd(DragEndDetails());

    expect(updates, hasLength(1));
    expect(updates.single.$2, task1.start.add(pixelsToDuration(380 + offsetAfterDrag)));

    // The timer must be stopped after the drag ends: no further scrolling.
    await tester.pump(const Duration(milliseconds: 160));
    expect(scrollController.offset, offsetAfterDrag);
  });
}
