import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  test('custom metadata survives protocol conversion, edits, and copying', () {
    final task = LegacyGanttTask(
      id: 'task-1',
      rowId: 'row-1',
      start: DateTime.utc(2024),
      end: DateTime.utc(2024, 1, 2),
      load: 2,
      stackIndex: 3,
      isAutoScheduled: false,
      extraMetadata: const {
        'externalReference': {
          'system': 'example',
          'ids': ['custom-42'],
        },
      },
    );
    final wire = ProtocolTask.fromBuffer(task.toProtocolTask().writeToBuffer());
    final restored = LegacyGanttTask.fromProtocolTask(wire);
    expect(restored, task);
    expect(restored.contentHash, wire.contentHash);
    final edited = restored.copyWith(name: 'Edited');
    expect(edited.extraMetadata['externalReference'], {
      'system': 'example',
      'ids': ['custom-42'],
    });
    expect(jsonDecode(edited.toProtocolTask().metadataJson)['externalReference'], {
      'system': 'example',
      'ids': ['custom-42'],
    });
    expect(restored.copyWithProtocol(wire).extraMetadata, restored.extraMetadata);
    expect(restored.copyWith(extraMetadata: {'custom': 2}), isNot(restored));
  });

  test('empty optional fields retain hashes after a binary snapshot', () {
    final task = LegacyGanttTask(
      id: 'task-1',
      rowId: 'row-1',
      start: DateTime.utc(2024),
      end: DateTime.utc(2024, 1, 2),
    );
    final snapshot = ProtobufMapper.toProtobuf({
      'type': 'BATCH_UPDATE',
      'data': <String, dynamic>{
        'operations': [
          {'type': 'UPDATE_TASK', 'data': ProtobufMapper.taskToJson(task.toProtocolTask())},
        ],
      },
    });
    final wire = ProtocolMessage.fromBuffer(snapshot.writeToBuffer()).batchUpdate.tasks.single;
    final restored = LegacyGanttTask.fromProtocolTask(wire);
    expect(restored.name, isNull);
    expect(restored.resourceId, isNull);
    expect(restored.parentId, isNull);
    expect(restored.notes, isNull);
    expect(restored.contentHash, wire.contentHash);
    expect(restored.contentHash, task.contentHash);
  });

  test('metadata is defensively immutable and typed fields override extras', () {
    final reference = <String, dynamic>{
      'ids': ['original'],
    };
    final input = <String, dynamic>{'externalReference': reference, 'load': 99};
    final task = LegacyGanttTask(
      id: 'task-1',
      rowId: 'row-1',
      start: DateTime.utc(2024),
      end: DateTime.utc(2024, 1, 2),
      load: 2,
      extraMetadata: input,
    );
    input['load'] = 100;
    (reference['ids'] as List).add('later');
    expect(task.extraMetadata['externalReference'], {
      'ids': ['original'],
    });
    expect(() => task.extraMetadata['custom'] = 1, throwsUnsupportedError);
    expect(() => (task.extraMetadata['externalReference']['ids'] as List).add('later'), throwsUnsupportedError);
    expect(jsonDecode(task.toProtocolTask().metadataJson)['load'], 2.0);
  });
}
