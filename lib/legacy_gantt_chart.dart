/// A Flutter package for displaying Gantt charts.
library;

export 'src/legacy_gantt_chart_widget.dart';
export 'src/models/legacy_gantt_task.dart';
export 'src/models/legacy_gantt_theme.dart';
export 'src/models/legacy_gantt_row.dart';
export 'src/utils/legacy_gantt_conflict_detector.dart';
export 'src/legacy_gantt_view_model.dart';
export 'src/models/legacy_gantt_dependency.dart';
export 'src/legacy_gantt_controller.dart';
export 'src/sync/gantt_sync_client.dart';
export 'package:legacy_timeline_scrubber/legacy_timeline_scrubber.dart'
    hide LegacyGanttTask, LegacyGanttTheme, LegacyGanttTaskSegment;
