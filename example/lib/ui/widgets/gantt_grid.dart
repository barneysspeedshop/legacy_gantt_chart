import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import '../gantt_grid_data.dart';

class GanttGrid extends StatelessWidget {
  final List<GanttGridData> gridData;
  final List<LegacyGanttRow> visibleGanttRows;
  final Map<String, int> rowMaxStackDepth;
  final ScrollController scrollController;
  final Function(String) onToggleExpansion;
  final bool isDarkMode;
  final VoidCallback onAddContact;
  final Function(String parentId) onAddLineItem;
  final Function(String parentId, bool isSummary) onSetParentTaskType;
  final Function(String parentId) onEditParentTask;
  final Function(String parentId) onEditDependentTasks;
  final VoidCallback onEditAllParentTasks;
  final Function(String rowId) onDeleteRow;
  final List<LegacyGanttTask> ganttTasks;
  final double rowHeight;
  final double headerHeight;

  const GanttGrid({
    super.key,
    required this.gridData,
    required this.visibleGanttRows,
    required this.rowMaxStackDepth,
    required this.scrollController,
    required this.onToggleExpansion,
    required this.isDarkMode,
    required this.onAddContact,
    required this.onAddLineItem,
    required this.onSetParentTaskType,
    required this.onEditParentTask,
    required this.onEditDependentTasks,
    required this.onEditAllParentTasks,
    required this.onDeleteRow,
    required this.ganttTasks,
    this.rowHeight = 27.0,
    this.headerHeight = 27.0,
  });

  @override
  Widget build(BuildContext context) {
    // For performance, create a lookup map to quickly find grid data by ID.
    // This avoids searching the list inside the ListView.builder.
    final Map<String, GanttGridData> dataMap = {};
    for (final parent in gridData) {
      dataMap[parent.id] = parent;
      for (final child in parent.children) {
        dataMap[child.id] = child;
      }
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        color: isDarkMode ? Colors.grey[850] : Colors.white,
      ),
      child: Column(
        children: [
          _buildGridHeader(isDarkMode),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: visibleGanttRows.length,
              itemBuilder: (context, index) {
                final data = dataMap[visibleGanttRows[index].id];

                if (data == null) {
                  return const SizedBox.shrink();
                }
                return _buildGridRow(data, isDarkMode);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridHeader(bool isDarkMode) => Container(
        height: headerHeight,
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[700] : Colors.grey[200],
          border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
        ),
        child: Row(
          children: [
            Expanded(flex: 2, child: _buildHeaderCell('Name')),
            Expanded(flex: 1, child: _buildHeaderCell('Completed %')),
            SizedBox(
              width: 48 + 48, // Space for two icons to align with parent rows
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.person_add),
                      tooltip: 'Add Contact',
                      onPressed: onAddContact,
                      iconSize: 20,
                      splashRadius: 20,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                    IconButton(
                      icon: Icon(Icons.edit, color: isDarkMode ? Colors.white70 : Colors.black54),
                      tooltip: 'Edit All Parent Tasks',
                      onPressed: onEditAllParentTasks,
                      iconSize: 20,
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildGridRow(GanttGridData data, bool isDarkMode) {
    final int stackDepth = rowMaxStackDepth[data.id] ?? 1;
    final double dynamicRowHeight = rowHeight * stackDepth;
    return Container(
      height: dynamicRowHeight,
      decoration: BoxDecoration(
        color: data.isParent ? (isDarkMode ? Colors.grey[800] : Colors.grey[100]) : null,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.topLeft,
              child: _buildTreeCell(data),
            ),
          ),
          Expanded(
            flex: 1,
            child: _buildCompletionCell(data.completion),
          ),
          SizedBox(
            width: 48,
            child: data.isParent
                ? _buildActionCell(IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add Line Item',
                    onPressed: () => onAddLineItem(data.id)))
                : _buildActionCell(IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete Row',
                    onPressed: () => onDeleteRow(data.id))),
          ),
          SizedBox(
            width: 48,
            child: data.isParent
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: 'Options',
                    onSelected: (value) {
                      if (value == 'make_summary') {
                        onSetParentTaskType(data.id, true);
                      } else if (value == 'make_regular') {
                        onSetParentTaskType(data.id, false);
                      } else if (value == 'edit_task') {
                        onEditParentTask(data.id);
                      } else if (value == 'edit_dependent_tasks') {
                        onEditDependentTasks(data.id);
                      } else if (value == 'delete_row') {
                        onDeleteRow(data.id);
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      final bool isCurrentlySummary = ganttTasks.any((t) => t.rowId == data.id && t.isSummary);
                      return <PopupMenuEntry<String>>[
                        if (isCurrentlySummary)
                          const PopupMenuItem<String>(value: 'edit_task', child: Text('Edit Task')),
                        if (!isCurrentlySummary)
                          const PopupMenuItem<String>(value: 'make_summary', child: Text('Make Summary'))
                        else
                          const PopupMenuItem<String>(value: 'make_regular', child: Text('Make Regular')),
                        if (data.children.isNotEmpty)
                          const PopupMenuItem<String>(
                              value: 'edit_dependent_tasks', child: Text('Edit Dependent Tasks')),
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(value: 'delete_row', child: Text('Delete Row')),
                      ];
                    },
                    splashRadius: 20,
                  )
                : ganttTasks.any((t) => t.rowId == data.id && !t.isTimeRangeHighlight)
                    ? _buildActionCell(IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit Task...',
                        onPressed: () => onEditParentTask(data.id),
                      ))
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _buildCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Text(text, overflow: TextOverflow.ellipsis),
      );

  Widget _buildTreeCell(GanttGridData data) => GestureDetector(
        onTap: data.isParent ? () => onToggleExpansion(data.id) : null,
        child: SizedBox(
          height: rowHeight,
          child: Container(
            color: Colors.transparent,
            padding: EdgeInsets.only(left: data.isParent ? 8.0 : 28.0, right: 8.0),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                if (data.isParent) Icon(data.isExpanded ? Icons.expand_more : Icons.chevron_right, size: 20),
                if (data.isParent) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    data.name,
                    style: TextStyle(fontWeight: data.isParent ? FontWeight.bold : FontWeight.normal),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildCompletionCell(double? completion) {
    if (completion == null) {
      return _buildCell('');
    }

    final percentage = (completion * 100).clamp(0, 100);
    final percentageText = '${percentage.toStringAsFixed(0)}%';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
      child: Stack(
        children: [
          // Background bar and black text
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                percentageText,
                style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // Foreground bar and white text, clipped to the completion percentage
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: completion,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(percentageText,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCell(IconButton iconButton) => IconButton(
        icon: iconButton.icon,
        tooltip: iconButton.tooltip,
        onPressed: iconButton.onPressed,
        iconSize: 18,
        splashRadius: 18,
        color: Colors.grey.shade600,
      );
}
