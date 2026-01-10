import 'package:intl/intl.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import '../data/local/local_gantt_repository.dart';
import 'package:uuid/uuid.dart';

class CsvImportMapping {
  final int? nameColumnIndex;
  final int? startColumnIndex;
  final int? endColumnIndex;
  final int? resourceColumnIndex;
  final int? progressColumnIndex;
  final String? closedStatusValue;
  final int? keyColumnIndex;
  final int? parentColumnIndex;
  final String? openStatusValue;

  const CsvImportMapping({
    this.nameColumnIndex,
    this.startColumnIndex,
    this.endColumnIndex,
    this.resourceColumnIndex,
    this.progressColumnIndex,
    this.closedStatusValue,
    this.keyColumnIndex,
    this.parentColumnIndex,
    this.openStatusValue,
  });
}

class CsvImporter {
  static const _uuid = Uuid();

  /// Parses a list of CSV rows into [LegacyGanttTask]s based on the provided [mapping].
  ///
  /// [rows] should exclude the header row if it exists.
  /// [headerRow] is optional, used for context if needed (not strictly used here yet).
  static ({List<LegacyGanttTask> tasks, List<LocalResource> resources}) convertRowsToTasks(
    List<List<dynamic>> rows,
    CsvImportMapping mapping, {
    List<LegacyGanttTask> existingTasks = const [],
    List<LocalResource> existingResources = const [],
  }) {
    print('Importing CSV with mapping: name=${mapping.nameColumnIndex}, res=${mapping.resourceColumnIndex}');

    // --- Pass 1: Build Key -> Name map for lookups ---
    final keyToNameMap = <String, String>{};
    if (mapping.keyColumnIndex != null && mapping.nameColumnIndex != null) {
      for (final row in rows) {
        if (row.length > mapping.keyColumnIndex! && row.length > mapping.nameColumnIndex!) {
          final key = row[mapping.keyColumnIndex!].toString().trim();
          final name = row[mapping.nameColumnIndex!].toString().trim();
          if (key.isNotEmpty && name.isNotEmpty) {
            keyToNameMap[key] = name;
          }
        }
      }
    }

    final tasks = <LegacyGanttTask>[];
    final resources = <LocalResource>[];
    final resourceMap = <String, String>{}; // Assignee Name -> Assignee Resource ID

    // Pre-populate resource map from existing resources
    for (final res in existingResources) {
      if (res.name != null && res.name!.isNotEmpty) {
        resourceMap[res.name!] = res.id;
      }
    }

    // Pre-populate task map from existing tasks (OriginalID -> TaskID)
    final existingTaskKeyMap = <String, String>{};
    for (final t in existingTasks) {
      if (t.originalId != null) {
        existingTaskKeyMap[t.originalId!] = t.id;
      }
    }

    // Map: AssigneeID -> { Key -> RowID }
    // Used to track if a specific Issue Key (e.g. TWR-341) already has a row under a specific Assignee.
    final assigneeKeyToRowMap = <String, Map<String, String>>{};

    // Create a default row/assignee for tasks that don't have a resource
    final defaultResourceId = _uuid.v4();
    // ignore: unused_local_variable
    bool defaultResourceUsed = false;

    // Helper to get/create Assignee Resource
    String getAssigneeId(String? name) {
      String safeName;
      String idToUse;

      if (name == null || name.trim().isEmpty) {
        safeName = 'Unassigned';
        idToUse = defaultResourceId;
        defaultResourceUsed = true;
      } else {
        safeName = name.trim();
        idToUse = resourceMap[safeName] ?? _uuid.v4();
      }

      if (!resourceMap.containsKey(safeName)) {
        resourceMap[safeName] = idToUse;
        resources.add(LocalResource(id: idToUse, name: safeName, parentId: null, isExpanded: true));
        assigneeKeyToRowMap[idToUse] = {};
      } else {
        // Ensure map exists even for pre-existing resources
        if (!assigneeKeyToRowMap.containsKey(idToUse)) {
          assigneeKeyToRowMap[idToUse] = {};
        }
      }
      return resourceMap[safeName]!;
    }

    for (final row in rows) {
      if (row.isEmpty) continue;

      // Extract basic data
      String? name;
      if (mapping.nameColumnIndex != null && mapping.nameColumnIndex! < row.length) {
        name = row[mapping.nameColumnIndex!].toString();
      }

      // If no name, skip or use default? Let's skip empty names.
      if (name == null || name.trim().isEmpty) continue;

      String? key;
      if (mapping.keyColumnIndex != null && mapping.keyColumnIndex! < row.length) {
        key = row[mapping.keyColumnIndex!].toString().trim();
        if (key.isEmpty) key = null;
      }

      DateTime? start;
      DateTime? baselineStart;
      if (mapping.startColumnIndex != null && mapping.startColumnIndex! < row.length) {
        final val = row[mapping.startColumnIndex!].toString();
        final parsed = parseDateRange(val);
        start = parsed?.start;
        baselineStart = parsed?.originalStart;
      }

      DateTime? end;
      DateTime? baselineEnd;
      if (mapping.endColumnIndex != null && mapping.endColumnIndex! < row.length) {
        final val = row[mapping.endColumnIndex!].toString();
        final parsed = parseDateRange(val);
        // For end date, we want the END of the period.
        // If the user provided a range text in the "End" column (e.g. "Apr 2026"),
        // usually that implies the task finishes at the end of that period.
        // Our parseDateRange returns start/end of the parsed period.
        // If we strictly follow the plan:
        // "Task Start/End will use the EARLIEST implied dates".
        // BUT for the "End Date" column, "earliest implied date" might mean the start of the specific month?
        // Actually, if a task ends in "Nov 2025", usually it means it covers November.
        // But if we want "Float", we want the Optimized Schedule vs the Baseline.
        // Optimized End: end of the *first* unit in the range?
        // Baseline End: end of the *full* range.

        end = parsed?.end; // This is the end of the *first* parsed component if it was a range like Jan-Mar
        baselineEnd = parsed?.originalEnd; // This is the end of the *full* range
      }

      // Ensure end is after start
      if (start != null && end != null && end.isBefore(start)) {
        end = start.add(const Duration(days: 1));
      }

      bool datesValid = start != null && end != null;

      // DEBUG: Trace date parsing for specific row
      if (key == 'TWR-193') {
        print('DEBUG TWR-193:');
        print('  StartColIndex: ${mapping.startColumnIndex}, EndColIndex: ${mapping.endColumnIndex}');
        if (mapping.startColumnIndex != null) print('  Raw Start Val: "${row[mapping.startColumnIndex!]}"');
        if (mapping.endColumnIndex != null) print('  Raw End Val: "${row[mapping.endColumnIndex!]}"');
        print('  Parsed Start: $start');
        print('  Parsed End: $end');
        print('  datesValid: $datesValid');
      }

      // Progress & Status Logic
      double completion = 0.0;
      bool isOpenStatus = false;
      if (mapping.progressColumnIndex != null && mapping.progressColumnIndex! < row.length) {
        final progressVal = row[mapping.progressColumnIndex!].toString().trim();
        completion = parseProgress(progressVal);

        // Check for "Closed" status mapping
        if (mapping.closedStatusValue != null && mapping.closedStatusValue!.isNotEmpty) {
          if (progressVal.toLowerCase() == mapping.closedStatusValue!.toLowerCase().trim()) {
            completion = 1.0;
          }
        }

        // Check for "Open" status mapping
        if (mapping.openStatusValue != null && mapping.openStatusValue!.isNotEmpty) {
          if (progressVal.toLowerCase() == mapping.openStatusValue!.toLowerCase().trim()) {
            isOpenStatus = true;
          }
        }
      }

      // Filtering Logic:
      // - If dates are valid -> Keep.
      // - If dates invalid:
      //   - If "Open" status is defined AND this row matches -> Keep (empty row).
      //   - If "Open" status is NOT defined -> Keep (legacy behavior: empty row).
      //   - If "Open" status IS defined but this row does NOT match -> Skip row?
      //     "when a status is open... still populate a row" implies others might not.
      //     Let's enforce: If openStatusValue is set, we ONLY keep invalid-date rows if they match isOpenStatus.

      bool shouldKeepRow = datesValid;
      if (!datesValid) {
        if (mapping.openStatusValue != null && mapping.openStatusValue!.isNotEmpty) {
          shouldKeepRow = isOpenStatus;
        } else {
          shouldKeepRow = true; // Default behavior
        }
      }

      if (!shouldKeepRow) continue;

      String? parentKey;
      if (mapping.parentColumnIndex != null && mapping.parentColumnIndex! < row.length) {
        parentKey = row[mapping.parentColumnIndex!].toString().trim();
        if (parentKey.isEmpty) parentKey = null;
      }

      String? assigneeName;
      if (mapping.resourceColumnIndex != null && mapping.resourceColumnIndex! < row.length) {
        assigneeName = row[mapping.resourceColumnIndex!].toString().trim();
        if (assigneeName.isEmpty) assigneeName = null;
      }

      // 1. Get/Create Assignee Resource ID
      final assigneeId = getAssigneeId(assigneeName);

      // 2. Identify Parent Row ID for *THIS* Task
      // It is either the Assignee (default) or a Virtual Parent Row inside that Assignee
      String parentRowId = assigneeId;

      if (parentKey != null) {
        final assigneeRowMap = assigneeKeyToRowMap[assigneeId]!;

        // Ensure Virtual Parent Row exists under this assignee
        if (!assigneeRowMap.containsKey(parentKey)) {
          final virtId = _uuid.v4();
          final virtName = keyToNameMap[parentKey] ?? parentKey;

          resources.add(LocalResource(id: virtId, name: virtName, parentId: assigneeId, isExpanded: true));
          assigneeRowMap[parentKey] = virtId;
        }
        parentRowId = assigneeRowMap[parentKey]!;
      }

      // 3. Determine Row ID for *THIS* Task
      String taskRowId;
      final assigneeRowMap = assigneeKeyToRowMap[assigneeId]!;

      if (key != null && assigneeRowMap.containsKey(key)) {
        // This task (Key) was already created as a Virtual Parent under this assignee.
        // Reuse it, but update it with real details if we have them (like name)
        taskRowId = assigneeRowMap[key]!;

        final existingIdx = resources.indexWhere((r) => r.id == taskRowId);
        if (existingIdx != -1) {
          resources[existingIdx] = resources[existingIdx].copyWith(name: name, parentId: parentRowId);
        }
      } else {
        // Create New Row
        taskRowId = _uuid.v4();
        // If we found an existing task for this Key, we might want to try to find its existing Row ID?
        // But Row ID is linked to the Resource/Assignee.
        // If the assignee changed, the Row ID *should* change (it moves to a new parent).
        // So generating a new Row ID is correct IF it's a new row under this assignee.
        // However, if we are updating an existing task, we want to know its *current* row ID if we wanted to reuse it?
        // Actually, LegacyGanttTask contains rowId.

        if (key != null) {
          assigneeRowMap[key] = taskRowId;
        }

        resources.add(LocalResource(id: taskRowId, name: name, parentId: parentRowId, isExpanded: true));
      }

      // DEBUG LOGGING for Hierarchy
      if (key == 'TWR-193' || key == 'TWR-386') {
        print('DEBUG HIERARCHY for $key:');
        print('  Assignee: $assigneeName (ID: $assigneeId)');
        print('  ParentKey: $parentKey');
        print('  Resolved ParentRowID: $parentRowId');
        print('  This RowID: $taskRowId');
        print('  Is ParentRow == AssigneeRow? ${parentRowId == assigneeId}');
      }

      if (start != null && end != null) {
        String taskId = _uuid.v4();

        // Try to reuse existing task ID if we have a Key match
        if (key != null && existingTaskKeyMap.containsKey(key)) {
          taskId = existingTaskKeyMap[key]!;
        }

        tasks.add(LegacyGanttTask(
          id: taskId,
          rowId: taskRowId,
          start: start,
          end: end,
          name: name,
          completion: completion,
          resourceId: assigneeName,
          baselineStart: baselineStart != start ? baselineStart : null,
          baselineEnd: baselineEnd != end ? baselineEnd : null,
          originalId: key,
        ));
      }
    }

    return (tasks: tasks, resources: resources);
  }

  /// Streams chunks of tasks and resources parsed from the provided CSV rows.
  static Stream<({List<LegacyGanttTask> tasks, List<LocalResource> resources})> streamConvertRowsToTasks(
    List<List<dynamic>> rows,
    CsvImportMapping mapping, {
    List<({String id, String? originalId})> existingTaskKeys = const [],
    List<({String id, String? name})> existingResourceNames = const [],
    int chunkSize = 200,
  }) async* {
    // --- Pass 1: Build Key -> Name map for lookups (Fast) ---
    final keyToNameMap = <String, String>{};
    if (mapping.keyColumnIndex != null && mapping.nameColumnIndex != null) {
      for (final row in rows) {
        if (row.length > mapping.keyColumnIndex! && row.length > mapping.nameColumnIndex!) {
          final key = row[mapping.keyColumnIndex!].toString().trim();
          final name = row[mapping.nameColumnIndex!].toString().trim();
          if (key.isNotEmpty && name.isNotEmpty) {
            keyToNameMap[key] = name;
          }
        }
      }
    }

    final chunkTasks = <LegacyGanttTask>[];
    final chunkResources = <LocalResource>[];

    final resourceMap = <String, String>{}; // Assignee Name -> Assignee Resource ID

    for (final res in existingResourceNames) {
      if (res.name != null && res.name!.isNotEmpty) {
        resourceMap[res.name!] = res.id;
      }
    }

    final existingTaskKeyMap = <String, String>{};
    for (final t in existingTaskKeys) {
      if (t.originalId != null) {
        existingTaskKeyMap[t.originalId!] = t.id;
      }
    }

    final assigneeKeyToRowMap = <String, Map<String, String>>{};

    // Default Resource setup
    final defaultResourceId = _uuid.v4();
    // ignore: unused_local_variable
    bool defaultResourceUsed = false;

    String getAssigneeId(String? name) {
      String safeName;
      String idToUse;

      if (name == null || name.trim().isEmpty) {
        safeName = 'Unassigned';
        idToUse = defaultResourceId;
        defaultResourceUsed = true;
      } else {
        safeName = name.trim();
        idToUse = resourceMap[safeName] ?? _uuid.v4();
      }

      if (!resourceMap.containsKey(safeName)) {
        resourceMap[safeName] = idToUse;
        assigneeKeyToRowMap[idToUse] = {};

        // Add to chunk
        chunkResources.add(LocalResource(id: idToUse, name: safeName, parentId: null, isExpanded: true));
      } else {
        if (!assigneeKeyToRowMap.containsKey(idToUse)) {
          assigneeKeyToRowMap[idToUse] = {};
        }
      }
      return idToUse;
    }

    for (final row in rows) {
      if (row.isEmpty) continue;

      // Extract basic data
      String? name;
      if (mapping.nameColumnIndex != null && mapping.nameColumnIndex! < row.length) {
        name = row[mapping.nameColumnIndex!].toString();
      }
      if (name == null || name.trim().isEmpty) continue;

      String? key;
      if (mapping.keyColumnIndex != null && mapping.keyColumnIndex! < row.length) {
        key = row[mapping.keyColumnIndex!].toString().trim();
        if (key.isEmpty) key = null;
      }

      DateTime? start;
      DateTime? baselineStart;
      if (mapping.startColumnIndex != null && mapping.startColumnIndex! < row.length) {
        final val = row[mapping.startColumnIndex!].toString();
        final parsed = parseDateRange(val);
        start = parsed?.start;
        baselineStart = parsed?.originalStart;
      }

      DateTime? end;
      DateTime? baselineEnd;
      if (mapping.endColumnIndex != null && mapping.endColumnIndex! < row.length) {
        final val = row[mapping.endColumnIndex!].toString();
        final parsed = parseDateRange(val);
        end = parsed?.end;
        baselineEnd = parsed?.originalEnd;
      }
      if (start != null && end != null && end.isBefore(start)) {
        end = start.add(const Duration(days: 1));
      }
      bool datesValid = start != null && end != null;

      double completion = 0.0;
      bool isOpenStatus = false;
      if (mapping.progressColumnIndex != null && mapping.progressColumnIndex! < row.length) {
        final progressVal = row[mapping.progressColumnIndex!].toString().trim();
        completion = parseProgress(progressVal);
        if (mapping.closedStatusValue != null && mapping.closedStatusValue!.isNotEmpty) {
          if (progressVal.toLowerCase() == mapping.closedStatusValue!.toLowerCase().trim()) {
            completion = 1.0;
          }
        }
        if (mapping.openStatusValue != null && mapping.openStatusValue!.isNotEmpty) {
          if (progressVal.toLowerCase() == mapping.openStatusValue!.toLowerCase().trim()) {
            isOpenStatus = true;
          }
        }
      }

      bool shouldKeepRow = datesValid;
      if (!datesValid) {
        if (mapping.openStatusValue != null && mapping.openStatusValue!.isNotEmpty) {
          shouldKeepRow = isOpenStatus;
        } else {
          shouldKeepRow = true;
        }
      }

      if (!shouldKeepRow) continue;

      String? parentKey;
      if (mapping.parentColumnIndex != null && mapping.parentColumnIndex! < row.length) {
        parentKey = row[mapping.parentColumnIndex!].toString().trim();
        if (parentKey.isEmpty) parentKey = null;
      }

      String? assigneeName;
      if (mapping.resourceColumnIndex != null && mapping.resourceColumnIndex! < row.length) {
        assigneeName = row[mapping.resourceColumnIndex!].toString().trim();
        if (assigneeName.isEmpty) assigneeName = null;
      }

      // Hierarchy Logic
      final assigneeId = getAssigneeId(assigneeName);
      String parentRowId = assigneeId;

      if (parentKey != null) {
        final assigneeRowMap = assigneeKeyToRowMap[assigneeId]!;
        if (!assigneeRowMap.containsKey(parentKey)) {
          final virtId = _uuid.v4();
          final virtName = keyToNameMap[parentKey] ?? parentKey;

          chunkResources.add(LocalResource(id: virtId, name: virtName, parentId: assigneeId, isExpanded: true));
          assigneeRowMap[parentKey] = virtId;
        }
        parentRowId = assigneeRowMap[parentKey]!;
      }

      String taskRowId;
      final assigneeRowMap = assigneeKeyToRowMap[assigneeId]!;

      if (key != null && assigneeRowMap.containsKey(key)) {
        taskRowId = assigneeRowMap[key]!;
        // Update existing resource in chunk? For now, re-emit to update details
        chunkResources.add(LocalResource(id: taskRowId, name: name, parentId: parentRowId, isExpanded: true));
      } else {
        taskRowId = _uuid.v4();
        if (key != null) assigneeRowMap[key] = taskRowId;
        chunkResources.add(LocalResource(id: taskRowId, name: name, parentId: parentRowId, isExpanded: true));
      }

      if (start != null && end != null) {
        String taskId = _uuid.v4();
        if (key != null && existingTaskKeyMap.containsKey(key)) {
          taskId = existingTaskKeyMap[key]!;
        }

        chunkTasks.add(LegacyGanttTask(
          id: taskId,
          rowId: taskRowId,
          start: start,
          end: end,
          name: name,
          completion: completion,
          resourceId: assigneeName,
          baselineStart: baselineStart != start ? baselineStart : null,
          baselineEnd: baselineEnd != end ? baselineEnd : null,
          originalId: key,
        ));
      }

      // Yield Chunk
      if (chunkTasks.length + chunkResources.length >= chunkSize) {
        yield (tasks: List.of(chunkTasks), resources: List.of(chunkResources));
        chunkTasks.clear();
        chunkResources.clear();
      }
    }

    // Yield Remaining
    if (chunkTasks.isNotEmpty || chunkResources.isNotEmpty) {
      yield (tasks: chunkTasks, resources: chunkResources);
    }
  }

  /// Parses diverse date strings including ranges.
  /// Returns a record with identifying dates.
  static ({DateTime start, DateTime end, DateTime originalStart, DateTime originalEnd})? parseDateRange(String input) {
    if (input.trim().isEmpty) {
      return null;
    }

    // Clean input
    final cleanedInput = input.trim();

    // Check for range patterns like "Jan-Mar, 2026" or "Jan 2025-Feb 2026" (though CSV usually has one field per date)
    // The example showed "Jan-Mar, 2026" in a single cell.

    // Split by common separators if it looks like a range inside the text
    // Regex for "Jan-Mar, 2026" -> Month-Month, Year
    final monthRangeYearRegExp = RegExp(r'^([A-Za-z]+)-([A-Za-z]+),\s*(\d{4})$');
    final match = monthRangeYearRegExp.firstMatch(cleanedInput);

    if (match != null) {
      final startMonth = match.group(1)!;
      final endMonth = match.group(2)!;
      final year = match.group(3)!;

      final startDt = _parseSingleDate('$startMonth $year');
      // For the end date of the range, we need the END of the endMonth
      final endMonthStart = _parseSingleDate('$endMonth $year');

      if (startDt == null || endMonthStart == null) return null;

      final endDt = _endOfGranularity(endMonthStart, 'month');

      // Task Start: Start of first month
      // Task End: End of first month (Optimistic/Earliest)
      // Baseline Start: Start of first month
      // Baseline End: End of last month

      final taskEnd = _endOfGranularity(startDt, 'month');

      return (start: startDt, end: taskEnd, originalStart: startDt, originalEnd: endDt);
    }

    // Handle standard single dates
    final dt = _parseSingleDate(cleanedInput);
    if (dt == null) return null;

    // Determine granularity to set 'end' correctly if it's just "May 2025" (implied whole month)
    // If input has day, granularity is day. If only month/year, granularity is month.
    final hasDay = RegExp(r'\d{1,2}').hasMatch(cleanedInput.replaceAll(RegExp(r'\d{4}'), ''));
    // ^ simplistic check: if there is a number that isn't the year.

    DateTime endDt;
    if (hasDay) {
      // It's a specific day, so end is same day (or next day depending on if we want 1 day duration)
      // Let's assume 1 day duration for specific dates? Or just use the exact time?
      // _parseSingleDate returns local time 00:00:00.
      endDt = dt.add(const Duration(days: 1));
    } else {
      // It's likely a month/year, so end is end of month.
      endDt = _endOfGranularity(dt, 'month');
    }

    return (start: dt, end: endDt, originalStart: dt, originalEnd: endDt);
  }

  static DateTime? _parseSingleDate(String input) {
    // Try formats
    final formats = [
      DateFormat('MMM d, yyyy', 'en_US'),
      DateFormat('MMM yyyy', 'en_US'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('yyyy/MM/dd'),
      DateFormat('MM/dd/yyyy'),
      DateFormat('M/d/yyyy'),
      DateFormat('d MMM yyyy', 'en_US'),
      DateFormat('MMM, yyyy', 'en_US'), // Just in case comma exists
      DateFormat('MMM d', 'en_US'), // For implicit year support
    ];

    for (var fmt in formats) {
      try {
        final dt = fmt.parse(input);
        // Sanity check: If date is suspiciously old (e.g. < 2000), treat as invalid/default?
        // Unless input explicitly contains that year.
        // This catches cases where DateFormat might default to epoch or year 0/1.
        if (dt.year < 2000) {
          // Double check if input really has that year
          if (!input.contains(dt.year.toString())) {
            continue; // Try next format or fail
          }
        }
        return dt;
      } catch (_) {}
    }

    // Fallback: try parsing just year?
    // Or return now.
    print('Failed to parse date: "$input" (ignoring row task bar)');
    return null;
  }

  static DateTime _endOfGranularity(DateTime dt, String granularity) {
    if (granularity == 'month') {
      // Go to next month, day 1, subtract 1 second/day
      final nextMonth = DateTime(dt.year, dt.month + 1, 1);
      return nextMonth.subtract(const Duration(seconds: 1));
    }
    return dt.add(const Duration(days: 1));
  }

  /// Parses progress string like "Done: 14 of 15 work items" or "50%"
  static double parseProgress(String input) {
    if (input.isEmpty) return 0.0;

    // Check "Done: X of Y"
    final doneOfTotalRegExp = RegExp(r'Done:\s*(\d+)\s*of\s*(\d+)');
    final match = doneOfTotalRegExp.firstMatch(input);
    if (match != null) {
      final done = int.parse(match.group(1)!);
      final total = int.parse(match.group(2)!);
      if (total == 0) return 0.0;
      return done / total;
    }

    // Check percentage "50%"
    if (input.contains('%')) {
      final val = double.tryParse(input.replaceAll('%', '').trim());
      if (val != null) return val / 100.0;
    }

    // Check raw number 0-1
    final val = double.tryParse(input);
    if (val != null && val <= 1.0) return val;

    return 0.0;
  }
}
