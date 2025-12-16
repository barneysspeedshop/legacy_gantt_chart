import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_controller.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_theme.dart';

/// A toolbar that provides controls for the Gantt chart, such as switching
/// between the Move and Select tools.
class LegacyGanttToolbar extends StatelessWidget {
  /// The controller that manages the Gantt chart state.
  final LegacyGanttController controller;

  /// The theme used to style the toolbar.
  final LegacyGanttTheme theme;

  const LegacyGanttToolbar({
    super.key,
    required this.controller,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: theme.backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => ToggleButtons(
                isSelected: [
                  controller.currentTool == GanttTool.move,
                  controller.currentTool == GanttTool.select,
                  controller.currentTool == GanttTool.draw,
                  controller.currentTool == GanttTool.drawDependencies,
                ],
                onPressed: (index) {
                  if (index == 0) {
                    controller.setTool(GanttTool.move);
                  } else if (index == 1) {
                    controller.setTool(GanttTool.select);
                  } else if (index == 2) {
                    controller.setTool(GanttTool.draw);
                  } else {
                    controller.setTool(GanttTool.drawDependencies);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                children: const [
                  Tooltip(message: 'Move Tool', child: Icon(Icons.open_with)),
                  Tooltip(message: 'Select Tool (Box Selection)', child: Icon(Icons.select_all)),
                  Tooltip(message: 'Draw Tool (Create Task)', child: Icon(Icons.edit)),
                  Tooltip(message: 'Link Tool (Draw Dependencies)', child: Icon(Icons.account_tree)),
                ],
              ),
            ),
            const Spacer(),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                if (controller.selectedTaskIds.isNotEmpty) {
                  return Text('${controller.selectedTaskIds.length} tasks selected');
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      );
}
