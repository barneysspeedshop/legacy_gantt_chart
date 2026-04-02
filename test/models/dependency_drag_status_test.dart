import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/dependency_drag_status.dart';

void main() {
  group('DependencyDragStatus', () {
    test('contains all expected enum values', () {
      expect(DependencyDragStatus.values, contains(DependencyDragStatus.none));
      expect(DependencyDragStatus.values, contains(DependencyDragStatus.admissible));
      expect(DependencyDragStatus.values, contains(DependencyDragStatus.inadmissible));
      expect(DependencyDragStatus.values, contains(DependencyDragStatus.cycle));
    });

    test('values have correct string representation', () {
      expect(DependencyDragStatus.none.toString(), 'DependencyDragStatus.none');
      expect(DependencyDragStatus.admissible.toString(), 'DependencyDragStatus.admissible');
      expect(DependencyDragStatus.inadmissible.toString(), 'DependencyDragStatus.inadmissible');
      expect(DependencyDragStatus.cycle.toString(), 'DependencyDragStatus.cycle');
    });
  });
}
