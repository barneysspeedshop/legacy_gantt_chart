/// Represents the result of parsing a Jira "Time in Status" field.
class JiraStatusResult {
  /// The calculated start date of the task (creation date + duration of first status).
  final DateTime start;

  /// The calculated end date of the task (start date + sum of subsequent durations).
  final DateTime end;

  const JiraStatusResult({
    required this.start,
    required this.end,
  });

  @override
  String toString() => 'JiraStatusResult(start: $start, end: $end)';
}

/// A utility class for parsing Jira "Time in Status" custom field strings.
///
/// The raw string is expected to be in a serialized format where segments are
/// separated by `_*|*_` and values within each segment are separated by `_*:*_`.
///
/// Format: `[StatusID]_*:*_[OccurrenceCount]_*:*_[DurationInMS]_*|*_[StatusID]_*:*_[OccurrenceCount]_*:*_[DurationInMS]`
class JiraStatusParser {
  /// The delimiter used to separate segments in the raw Jira string.
  static const String segmentDelimiter = '_*|*_';

  /// The delimiter used to separate values within a segment.
  static const String valueDelimiter = '_*:*_';

  /// Parses a Jira "Time in Status" [rawString] and returns a [JiraStatusResult].
  ///
  /// [createdDate] is the baseline (typically the Jira issue creation timestamp).
  ///
  /// Logic:
  /// - Task Start Date = [createdDate] + (Duration of the first segment).
  /// - Task End Date = (Task Start Date) + (Sum of durations of all subsequent segments).
  /// - Active Tasks: If the final segment has a duration of `0`, the [end] date is set to [DateTime.now].
  static JiraStatusResult? parse(String? rawString, DateTime createdDate) {
    if (rawString == null || rawString.trim().isEmpty) {
      return null;
    }

    try {
      final segments = rawString.split(segmentDelimiter);
      if (segments.isEmpty) return null;

      // Parse all durations first to handle active state and calculate total subsequent time
      final durations = <int>[];
      for (final segment in segments) {
        final values = segment.split(valueDelimiter);
        if (values.length < 3) {
          // If any segment is malformed, we might not be able to parse correctly
          return null;
        }

        final durationMs = int.tryParse(values[2]);
        if (durationMs == null) return null;
        durations.add(durationMs);
      }

      if (durations.isEmpty) return null;

      // 1. Task Start Date: creation timestamp + duration of first segment
      final firstDurationMs = durations.first;
      final startDate = createdDate.add(Duration(milliseconds: firstDurationMs));

      // 2. Task End Date calculation
      final lastDurationMs = durations.last;
      final isActive = lastDurationMs == 0;

      if (isActive) {
        return JiraStatusResult(
          start: startDate,
          end: DateTime.now(),
        );
      }

      // Sum all subsequent durations (after the first one)
      int totalSubsequentDurationMs = 0;
      for (int i = 1; i < durations.length; i++) {
        totalSubsequentDurationMs += durations[i];
      }

      final endDate = startDate.add(Duration(milliseconds: totalSubsequentDurationMs));

      return JiraStatusResult(
        start: startDate,
        end: endDate,
      );
    } catch (_) {
      // Catch any unexpected parsing errors (e.g. range errors)
      return null;
    }
  }
}
