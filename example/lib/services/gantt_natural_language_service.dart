import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

// ---------------------------------------------------------------------------
// Command hierarchy
// ---------------------------------------------------------------------------

abstract class GanttCommand {
  String get description;
}

class HelpCommand extends GanttCommand {
  final String topic;
  HelpCommand(this.topic);
  @override
  String get description => 'Show help for $topic';
}

class ClarificationRequiredCommand extends GanttCommand {
  final String question;
  ClarificationRequiredCommand(this.question);
  @override
  String get description => question;
}

class AddTasksCommand extends GanttCommand {
  final List<String> resourceNames;
  final int count;
  final String taskType; // "task", "milestone", or "summary"
  final DateTime? startDate;
  final DateTime? endDate;

  AddTasksCommand(
    this.resourceNames, {
    this.count = 1,
    required this.taskType,
    this.startDate,
    this.endDate,
  });

  @override
  String get description => 'Add $count $taskType(s) for ${resourceNames.join(", ")}';
}

class UpdateTaskCommand extends GanttCommand {
  final List<String> resourceNames;
  final String? taskName;
  final Map<String, dynamic> updates;

  UpdateTaskCommand({
    required this.resourceNames,
    this.taskName,
    required this.updates,
  });

  @override
  String get description => 'Update task(s) for ${resourceNames.join(", ")} with ${updates.keys.join(", ")}';
}

class TransposeTasksCommand extends GanttCommand {
  final List<String> resourceNames;
  final String? taskName;
  final Duration? offset;
  final DateTime? targetDate;
  final String? targetTaskName;
  final String? relativeSide; // "before", "after"

  TransposeTasksCommand({
    required this.resourceNames,
    this.taskName,
    this.offset,
    this.targetDate,
    this.targetTaskName,
    this.relativeSide,
  });

  @override
  String get description {
    final target = targetTaskName != null
        ? '${relativeSide ?? "at"} "$targetTaskName"'
        : targetDate != null
            ? 'to $targetDate'
            : '${offset?.inDays ?? 0} days';
    return 'Transpose task(s) for ${resourceNames.join(", ")} $target';
  }
}

/// Anchor the schedule so the earliest task starts at [targetDate].
class AnchorScheduleCommand extends GanttCommand {
  final DateTime? targetDate;
  final String? targetTaskName;
  final String? relativeSide; // "before", "after"
  final List<String> resourceNames;

  AnchorScheduleCommand({
    this.targetDate,
    this.targetTaskName,
    this.relativeSide,
    this.resourceNames = const [],
  });

  @override
  String get description {
    final target = targetTaskName != null ? '${relativeSide ?? "at"} "$targetTaskName"' : '$targetDate';
    return 'Anchor schedule so first task starts $target';
  }
}

/// Delete tasks matching resource/task name criteria.
class DeleteTasksCommand extends GanttCommand {
  final List<String> resourceNames;
  final String? taskName;

  DeleteTasksCommand({required this.resourceNames, this.taskName});

  @override
  String get description =>
      'Delete task(s) for ${resourceNames.join(", ")}${taskName != null ? " named \"$taskName\"" : ""}';
}

/// Move tasks from one resource to another.
class ReassignTasksCommand extends GanttCommand {
  final List<String> fromResourceNames;
  final String toResourceName;
  final String? taskName;

  ReassignTasksCommand({
    required this.fromResourceNames,
    required this.toResourceName,
    this.taskName,
  });

  @override
  String get description => 'Reassign task(s) from ${fromResourceNames.join(", ")} to $toResourceName';
}

/// Create a dependency between two tasks.
class AddDependencyCommand extends GanttCommand {
  final String predecessorTaskName;
  final String successorTaskName;

  /// "FS" (finish-to-start), "SS", "FF", "SF"
  final String dependencyType;

  AddDependencyCommand({
    required this.predecessorTaskName,
    required this.successorTaskName,
    this.dependencyType = 'FS',
  });

  @override
  String get description => 'Add $dependencyType dependency: "$predecessorTaskName" → "$successorTaskName"';
}

/// Compress or stretch the schedule by a factor.
class CompressScheduleCommand extends GanttCommand {
  /// < 1.0 compresses, > 1.0 stretches
  final double factor;
  final List<String> resourceNames;

  CompressScheduleCommand({required this.factor, this.resourceNames = const []});

  @override
  String get description =>
      'Scale schedule durations by ${factor}x for ${resourceNames.isEmpty ? "all resources" : resourceNames.join(", ")}';
}

/// Shift tasks by a number of working days (skipping weekends).
class ShiftWorkingDaysCommand extends GanttCommand {
  final List<String> resourceNames;
  final String? taskName;
  final int offsetWorkingDays;

  ShiftWorkingDaysCommand({
    required this.resourceNames,
    this.taskName,
    required this.offsetWorkingDays,
  });

  @override
  String get description => 'Shift task(s) for ${resourceNames.join(", ")} by $offsetWorkingDays working days';
}

/// Remove gaps between tasks for specified resources (pack them end-to-end).
class PackTasksCommand extends GanttCommand {
  final List<String> resourceNames;

  PackTasksCommand({required this.resourceNames});

  @override
  String get description => 'Pack tasks for ${resourceNames.join(", ")} with no gaps';
}

/// Mirror/reverse the schedule so it ends at [targetEndDate].
class MirrorScheduleCommand extends GanttCommand {
  final DateTime targetEndDate;
  final List<String> resourceNames;

  MirrorScheduleCommand({
    required this.targetEndDate,
    this.resourceNames = const [],
  });

  @override
  String get description => 'Mirror schedule to end at $targetEndDate';
}

/// A read-only query about the schedule. The service answers in prose.
class ScheduleQueryCommand extends GanttCommand {
  final String question;
  ScheduleQueryCommand(this.question);
  @override
  String get description => 'Query: $question';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class GanttNaturalLanguageService {
  ChatSession? _chatSession;
  late GenerativeModel _model;

  // A separate model (no chat state) used for read-only queries with injected
  // task snapshot context.
  GenerativeModel? _queryModel;

  String? apiKey;

  GanttNaturalLanguageService({this.apiKey}) {
    if (apiKey != null && apiKey!.isNotEmpty) {
      _initModel();
    }
  }

  void updateApiKey(String newKey) {
    if (newKey.isNotEmpty && newKey != apiKey) {
      apiKey = newKey;
      _initModel(newKey);
    }
  }

  static const _colorMap = {
    'red': 'ff0000',
    'green': '00cc44',
    'blue': '0066ff',
    'yellow': 'ffdd00',
    'orange': 'ff8800',
    'purple': '9933ff',
    'pink': 'ff66aa',
    'teal': '009999',
    'gray': '888888',
    'grey': '888888',
    'black': '000000',
    'white': 'ffffff',
  };

  void _initModel([String? key]) {
    final effectiveKey = key ?? apiKey!;
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: effectiveKey,
      systemInstruction: Content.system(_buildSystemPrompt()),
    );
    _queryModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: effectiveKey,
    );
    _chatSession = _model.startChat();
  }

  String _buildSystemPrompt() => '''
You are an intelligent assistant helping a user manage tasks in a Gantt chart.
Supported operations: ADD, UPDATE, TRANSPOSE, ANCHOR, DELETE, REASSIGN, ADD_DEPENDENCY, COMPRESS, SHIFT_WORKING_DAYS, PACK, MIRROR, QUERY, HELP.

**HELP** — If the user asks "What can you do?", "How do you work?", or "Help with [topic]", use **HELP**.
Extract: `topic` (string, the specific function or "all").
Instructions: Your response for "HELP" will be a prose explanation shown to the user. Describe the functions clearly:
- **Add**: Create new tasks, milestones, or summaries for resources.
- **Update**: Change completion %, colors, notes, or dates of existing tasks.
- **Transpose/Move**: Shift tasks in time. You can say "Move A to [date]" or "Shift A before B".
- **Anchor**: Move an entire group of tasks (e.g. "Shift everything to start Jan 1").
- **Delete**: Remove tasks or milestones by name or resource.
- **Reassign**: Move tasks from one person to another.
- **Dependencies**: Link tasks (e.g. "Task B depends on Task A").
- **Compress**: Scale the schedule duration (e.g. "Compress by 50%").
- **Shift Working Days**: Move tasks while skipping weekends.
- **Pack**: Remove all gaps between a resource's tasks.
- **Mirror**: Reverse the schedule to end at a specific date.
- **Query**: Ask questions about the schedule (e.g. "Do I have any overlaps?").

**ADD tasks** — Extract: resourceNames (array), count (int, default 1), taskType ("task"/"milestone"/"summary"), startDate (ISO8601), endDate (ISO8601).
Clarification rules: ALWAYS ask if taskType or dates are not specified. Bundle all questions into one message.

**UPDATE tasks** — Extract: resourceNames, taskName (optional), updates (object):
  - completion: float 0.0–1.0. "50%" → 0.5, "100%" → 1.0, "done" → 1.0, "not started" → 0.0
  - color: hex string WITHOUT leading #. Color names map as: red→ff0000, green→00cc44, blue→0066ff, yellow→ffdd00, orange→ff8800, purple→9933ff, pink→ff66aa, teal→009999, gray/grey→888888
  - notes: string
  - startDate, endDate: ISO8601
  - load: float

**TRANSPOSE tasks** (move in time) — Examples: "Move Task A to 2026-05-01", "Shift Task A to happen before Task B", "Move Job 2 right by 3 days".
Extract: resourceNames, taskName (optional name of task to move), offsetDays (int, optional), targetDate (ISO8601, optional), targetTaskName (string, optional reference task), relativeSide ("before"/"after", optional).

**ANCHOR schedule** (absolute move of group) — Examples: "shift everything to start Jan 1 2026", "move person 0 to start after Extra Task".
Extract: targetDate (ISO8601, optional), targetTaskName (string, optional), relativeSide ("before"/"after", optional), resourceNames (empty=all).

**DELETE tasks** — Examples: "delete all tasks for person 0", "remove the review task for job 2". Extract: resourceNames, taskName (optional).

**REASSIGN tasks** — Examples: "move person 0's tasks to person 1", "reassign job 2's review task to job 3". Extract: fromResourceNames (array), toResourceName (string), taskName (optional).

**ADD_DEPENDENCY** — Examples: "make Task B depend on Task A", "add finish-to-start from design to review". Extract: predecessorTaskName (string), successorTaskName (string), dependencyType ("FS"/"SS"/"FF"/"SF", default "FS").

**COMPRESS schedule** — Examples: "compress the schedule by 50%", "stretch everything by 2x". Extract: factor (float, <1 compresses, >1 stretches), resourceNames (empty=all).

**SHIFT_WORKING_DAYS** — Examples: "shift job 2 right by 5 working days". Extract: resourceNames, taskName (optional), offsetWorkingDays (int, signed).

**PACK tasks** — Examples: "pack person 0's tasks together", "remove gaps between job 1's tasks". Extract: resourceNames.

**MIRROR schedule** — Examples: "flip the schedule to end on 3/31/2026", "mirror everything to end March 31". Extract: targetEndDate (ISO8601), resourceNames (empty=all).

**QUERY** — Examples: "what tasks does person 0 have?", "do any tasks overlap?", "how many days of work does job 2 have?". Extract: question (string, the user's original question verbatim).

**MOVE vs DEPENDENCY rule**: 
- If the user uses "move", "shift", "put", or "happens at/before/after", they usually want to change the date using **TRANSPOSE** or **ANCHOR**.
- Only use **ADD_DEPENDENCY** if they say "depends on", "successor", "predecessor", or "after" in a way that implies a permanent logical link.
- If the user uses "0-2", "Job 0 Task 2", etc., these are usually **task names** or **task IDs**.
- If they say "Shift X before Y", use **TRANSPOSE** with `taskName: "X"`, `targetTaskName: "Y"`, and `relativeSide: "before"`.
- "Tasks" generally includes **milestones** and **summaries** unless specified otherwise. "Delete all tasks" means everything.

Current time: ${DateTime.now().toIso8601String()}.

ALWAYS respond with ONLY a raw JSON object (no markdown fences):
{
  "status": "<one of: clarify|add|update|transpose|anchor|delete|reassign|add_dependency|compress|shift_working_days|pack|mirror|query|help>",
  "payload": { ... }
}

Payload schemas:
- help: { "topic": "string" }
- clarify: { "question": "string" }
- add: { "resourceNames": string[], "count": int, "taskType": string, "startDate": string, "endDate": string }
- update: { "resourceNames": string[], "taskName": string?, "updates": object }
- transpose: { "resourceNames": string[], "taskName": string?, "offsetDays": int?, "targetDate": string?, "targetTaskName": string?, "relativeSide": string? }
- anchor: { "targetDate": string?, "targetTaskName": string?, "relativeSide": string?, "resourceNames": string[] }
- delete: { "resourceNames": string[], "taskName": string? }
- reassign: { "fromResourceNames": string[], "toResourceName": string, "taskName": string? }
- add_dependency: { "predecessorTaskName": string, "successorTaskName": string, "dependencyType": string }
- compress: { "factor": float, "resourceNames": string[] }
- shift_working_days: { "resourceNames": string[], "taskName": string?, "offsetWorkingDays": int }
- pack: { "resourceNames": string[] }
- mirror: { "targetEndDate": string, "resourceNames": string[] }
- query: { "question": "string" }
''';

  void clearConversation() {
    if (apiKey != null && apiKey!.isNotEmpty) {
      _chatSession = _model.startChat();
    }
  }

  // ---------------------------------------------------------------------------
  // parse() — write commands
  // ---------------------------------------------------------------------------

  Future<GanttCommand?> parse(String input, {String? apiKey}) async {
    if (apiKey != null && apiKey.isNotEmpty) {
      updateApiKey(apiKey);
    }

    if (_chatSession == null) {
      return ClarificationRequiredCommand(
          'Please configure a Gemini API Key in the server settings to use the Gantt Assistant.');
    }

    try {
      final response = await _chatSession!.sendMessage(Content.text(input));
      final responseText = response.text?.trim() ?? '';

      // Strip accidental markdown fences
      var jsonText = responseText;
      if (jsonText.startsWith('```json')) jsonText = jsonText.substring(7);
      if (jsonText.startsWith('```')) jsonText = jsonText.substring(3);
      if (jsonText.endsWith('```')) jsonText = jsonText.substring(0, jsonText.length - 3);
      jsonText = jsonText.trim();

      final json = jsonDecode(jsonText) as Map<String, dynamic>;
      final status = json['status'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;

      if (status == null || payload == null) return null;

      return _dispatchParse(status, payload);
    } catch (e) {
      print('GanttNaturalLanguageService Error: $e');
      return ClarificationRequiredCommand('I am having trouble understanding that. Error: $e');
    }
  }

  GanttCommand? _dispatchParse(String status, Map<String, dynamic> payload) {
    List<String> strings(String key) => (payload[key] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    switch (status) {
      case 'help':
        return HelpCommand(payload['topic'] ?? 'all');

      case 'clarify':
        return ClarificationRequiredCommand(payload['message'] as String? ?? '');

      case 'complete':
      case 'add':
        final startDate = DateTime.tryParse(payload['startDate'] as String? ?? '');
        final endDate = DateTime.tryParse(payload['endDate'] as String? ?? '');
        return AddTasksCommand(
          strings('resourceNames'),
          count: (payload['count'] as num?)?.toInt() ?? 1,
          taskType: payload['taskType'] as String? ?? 'task',
          startDate: startDate,
          endDate: endDate,
        );

      case 'update':
        final updates = Map<String, dynamic>.from(payload['updates'] as Map? ?? {});
        // Normalise color names to hex
        if (updates.containsKey('color')) {
          final raw = updates['color'].toString().toLowerCase().replaceAll('#', '');
          updates['color'] = _colorMap[raw] ?? raw;
        }
        return UpdateTaskCommand(
          resourceNames: strings('resourceNames'),
          taskName: payload['taskName'] as String?,
          updates: updates,
        );

      case 'transpose':
        return TransposeTasksCommand(
          resourceNames: strings('resourceNames'),
          taskName: payload['taskName'] as String?,
          offset: payload['offsetDays'] != null ? Duration(days: (payload['offsetDays'] as num).toInt()) : null,
          targetDate: DateTime.tryParse(payload['targetDate'] as String? ?? ''),
          targetTaskName: payload['targetTaskName'] as String?,
          relativeSide: payload['relativeSide'] as String?,
        );

      case 'anchor':
        return AnchorScheduleCommand(
          targetDate: DateTime.tryParse(payload['targetDate'] as String? ?? ''),
          targetTaskName: payload['targetTaskName'] as String?,
          relativeSide: payload['relativeSide'] as String?,
          resourceNames: strings('resourceNames'),
        );

      case 'delete':
        return DeleteTasksCommand(
          resourceNames: strings('resourceNames'),
          taskName: payload['taskName'] as String?,
        );

      case 'reassign':
        final to = payload['toResourceName'] as String?;
        if (to == null || to.isEmpty) {
          return ClarificationRequiredCommand('Please specify the target resource to reassign tasks to.');
        }
        return ReassignTasksCommand(
          fromResourceNames: strings('fromResourceNames'),
          toResourceName: to,
          taskName: payload['taskName'] as String?,
        );

      case 'add_dependency':
        return AddDependencyCommand(
          predecessorTaskName: payload['predecessorTaskName'] as String? ?? '',
          successorTaskName: payload['successorTaskName'] as String? ?? '',
          dependencyType: payload['dependencyType'] as String? ?? 'FS',
        );

      case 'compress':
        return CompressScheduleCommand(
          factor: (payload['factor'] as num?)?.toDouble() ?? 1.0,
          resourceNames: strings('resourceNames'),
        );

      case 'shift_working_days':
        return ShiftWorkingDaysCommand(
          resourceNames: strings('resourceNames'),
          taskName: payload['taskName'] as String?,
          offsetWorkingDays: (payload['offsetWorkingDays'] as num?)?.toInt() ?? 0,
        );

      case 'pack':
        return PackTasksCommand(resourceNames: strings('resourceNames'));

      case 'mirror':
        final endDate = DateTime.tryParse(payload['targetEndDate'] as String? ?? '');
        if (endDate == null)
          return ClarificationRequiredCommand('Please specify a valid target end date for mirroring.');
        return MirrorScheduleCommand(
          targetEndDate: endDate,
          resourceNames: strings('resourceNames'),
        );

      case 'query':
        return ScheduleQueryCommand(payload['question'] as String? ?? '');

      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // query() — read-only, injects task snapshot
  // ---------------------------------------------------------------------------

  /// Answer a natural-language question about the schedule.
  /// [tasksJson] is a compact JSON string of the relevant tasks + resources.
  Future<String> query(String question, String tasksJson) async {
    if (_queryModel == null) {
      return 'Please configure a Gemini API Key to use query features.';
    }
    try {
      final prompt = '''
You are a Gantt schedule analyst. Answer the following question based ONLY on the provided schedule data.
Be concise and factual. Use plain text, no markdown.

The schedule data is a JSON object with these fields:
- "tasks": array of task objects with id, name, resource, person, start, end, durationHours, completion, isMilestone, isSummary, parentId, notes
- "conflicts": array of pre-computed overlaps. Each entry has: resource, taskA, taskB, overlapStart, overlapEnd, overlapMinutes
- "taskCount": total number of tasks
- "conflictCount": total number of overlapping task pairs

IMPORTANT: For any question about conflicts, overlaps, or scheduling issues, use the "conflicts" array directly — it is already computed and accurate. Do NOT try to re-derive overlaps from the raw task timestamps.

Schedule data:
$tasksJson

Question: $question
''';
      final response = await _queryModel!.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? 'No answer returned.';
    } catch (e) {
      return 'Query error: $e';
    }
  }
}
