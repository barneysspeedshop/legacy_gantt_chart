# AI Agent Instructions for Legacy Gantt Chart

This package is the core Flutter widget for displaying and interacting with the Gantt chart (`legacy_gantt_chart`). 

## Context and Fragile Areas

### 1. UI Thread Blocking (Dependencies)
Gantt dependency recalculations can be extremely expensive and easily block the UI thread during synchronization bursts. 
We rely on `LegacyGanttViewModel` to process dependencies in batches. If modifying the synchronization callback, ensure the logic preserves batched execution and utilizes `onDependenciesSynced` for bulk scale.

### 2. "Self-Healing" Summary Tasks & Task Behaviors
Parent/Summary tasks visualize dependencies derived from their children. If dependencies appear briefly and vanish, they are failing the persistence reconciliation. 

Additionally, summary tasks support specialized **Task Behaviors**:
- **Standard (Group)**: The parent's date range is driven by children. Move parent = move children.
- **Static Bucket**: The parent acts as a fixed container. Moving parent does *not* move children.
- **Constrain**: The parent acts as a boundary. Resizing parent pushes children.
- **Elastic**: Resizing parent proportionally stretches children.
When modifying drag/drop math in `LegacyGanttViewModel`, you **MUST** respect these strict bounds and evaluate the parent's `behavior` property.

### 3. Web / WASM Type-Casting Bugs
> [!CAUTION]
> Dart compiled to Web/WASM handles integers and floating-point numeric types differently than the Dart VM. In the past, this led to type-casting exceptions when parsing database row identifiers across network syncs that failed silently on Web but worked on Desktop. Always handle parsed ID rows with secure typemaps (e.g. `dynamic` falling back to `as String` or `int.tryParse`).

### 4. Hybrid Logical Clocks (HLC) Integration
As of package version 5.0.0, `LegacyGanttTask.lastUpdated` utilizes `Hlc` (Hybrid Logical Clock) objects instead of `int`. Whenever manually instantiating or updating tasks inside the view model, do not regress to epoch integers. Use `Hlc.fromDate()` or the internal protocol equivalents.

### 5. Timeline Scrubber Synchronization
The primary chart integrates tightly with `legacy_timeline_scrubber`. To ensure smooth zooming, the `LegacyGanttViewModel` actively drives the visible ranges (`gridMin` / `gridMax`). Do not break this 2-way data binding math, as it controls the high-level project zoom "mini-map".

### 6. Interaction Context (Tools)
The chart supports dynamic user interactions via `GanttTool` enumerations (`move`, `select`, `draw`). Ensure handlers like `onTaskDrawEnd` remain coupled with the `LegacyGanttController` state.
