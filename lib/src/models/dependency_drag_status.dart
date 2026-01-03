/// Represents the admissibility status of a dependency being dragged.
enum DependencyDragStatus {
  /// No dependency drag is in progress, or no target is hovered.
  none,

  /// The dependency is valid and doesn't push the project deadline.
  admissible,

  /// The dependency is valid but will extend the project's critical path.
  inadmissible,

  /// The dependency would create a cycle in the task graph.
  cycle,
}
