# AI Agent Instructions for Legacy Gantt Chart Example App

This directory contains the rich example Flutter application (`legacy_gantt_chart/example`) demonstrating the Gantt chart in action. 

## Context and Fragile Areas

### 1. Data Initialization Race Conditions
> [!WARNING]
> The `GanttViewModel` used within this example app generates "seed data" upon application launch to offer a fallback experience. 
> 
> Previously, a race condition triggered duplicate data generation. **Rule:** Seed data must ONLY be generated if BOTH the task and resource databases are completely empty. Do not loosen this check or change the initialization order without testing the edge cases.

### 2. CSV Isolate Import & Rollback
The example app features a robust CSV importer (`_handleCsvImport`). Because parsing large schedules locks the UI thread, this process utilizes `Isolate.spawn` and background `compute` workers. 
> [!IMPORTANT]
> If modifying the CSV importer, be extremely wary of the `_rollbackImport` function; it manually deletes tasks and resources via the view model if the user cancels. Breaking the isolate messaging protocol or the rollback iteration order will silently corrupt the local SQLite cache.

### 3. Bulk Optimization Routines
The `GanttViewModel` implements `updateTasksBulk` and `deleteTasksBulk`. For performance during heavy edits, these functions **optimistically patch the in-memory list** (`_allGanttTasks`) while side-loading the database writes and network Sync messages `unawaited`. If you alter state updates, adhere to this optimistic pattern to prevent the UI from stuttering during heavy re-stack computations.

### 4. "Snap To Task" Math
In `main.dart`, the `_handleSnapToTask` method scales the Gantt chart Scrubber Window to precisely 3x the target task's duration (or 1 day for a 0-duration milestone) to center it optimally without losing contextual overview. Modifying the date math here can easily cause division-by-zero exceptions or inverted date domains if `newWindowDuration` evaluates backwards.

### 5. Multiplayer Presence (Hex Parsing)
The UI renders active users via `_buildUserChips`. It parses `#hex` color strings passed dynamically over the WebSocket sync client from other `RemoteGhost` and `RemoteCursor` entities. If touching the `_parseColor` logic, ensure you strictly catch exceptions for invalid network color streams.
