import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/local_gantt_repository.dart';
import 'package:example/data/local/protocol_state_store.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;

Hlc _clock(int tick) => Hlc(millis: tick, counter: 0, nodeId: 'fixture');

Operation _operation(String type, Map<String, dynamic> data, int tick) =>
    Operation(type: type, data: data, timestamp: _clock(tick), actorId: 'fixture');

Operation _wire(Operation operation) => Operation.fromJson(
  ProtobufMapper.toJson(ProtocolMessage.fromBuffer(ProtobufMapper.toProtobuf(operation.toJson()).writeToBuffer())),
);

Operation _batch(List<Operation> operations, int tick) =>
    _operation('BATCH_UPDATE', {'operations': operations.map((operation) => operation.toJson()).toList()}, tick);

LegacyGanttTask _task(String id, {String? parentId}) => LegacyGanttTask(
  id: id,
  rowId: 'row',
  name: 'Task $id',
  start: DateTime.utc(2026, 11, 20),
  end: DateTime.utc(2026, 11, 21),
  parentId: parentId,
  notes: 'Offline notes',
);

class _Client {
  final String path;
  late SqliteCrdt database;
  late GanttViewModel viewModel;
  bool _open = false;

  _Client(this.path);

  Future<void> open() async {
    database = await GanttDb.open(path);
    await database.execute('INSERT OR REPLACE INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
      'canonical_scope',
      'local',
    ]);
    viewModel = GanttViewModel(database: Future.value(database), useLocalDatabase: true);
    _open = true;
    await viewModel.initialized;
  }

  Future<void> close() async {
    if (!_open) return;
    await viewModel.disposeAsync();
    await database.close();
    _open = false;
  }

  Future<void> reopen() async {
    await close();
    await open();
  }

  Future<List<Operation>> outgoing() async {
    final rows = await database.query(
      'SELECT type, data, timestamp, actor_id FROM offline_queue '
      'WHERE is_deleted = 0 ORDER BY id',
    );
    return rows
        .map(
          (row) => Operation.fromJson({
            'type': row['type'],
            'data': jsonDecode(row['data']! as String),
            'timestamp': row['timestamp'],
            'actorId': row['actor_id'],
          }),
        )
        .toList();
  }

  Future<void> receive(Iterable<Operation> operations) async {
    for (final operation in operations) {
      await viewModel.handleIncomingOperationForTesting(_wire(operation));
    }
  }

  Future<void> until(bool Function() predicate) async {
    final complete = Completer<void>();
    void changed() {
      if (predicate() && !complete.isCompleted) complete.complete();
    }

    viewModel.addListener(changed);
    try {
      changed();
      await complete.future.timeout(const Duration(seconds: 5));
    } finally {
      viewModel.removeListener(changed);
    }
  }

  Future<String> root() async => (await ProtocolStateStore(Future.value(database)).computeMerkleTree()).root.hash;
}

Map<String, Object?> _visible(_Client client) => {
  'tasks':
      (client.viewModel.allTasks
          .map((task) => {'id': task.id, 'name': task.name, 'parent': task.parentId, 'notes': task.notes})
          .toList()
        ..sort((a, b) => a['id']!.compareTo(b['id']!))),
  'resources':
      (client.viewModel.localResources
          .map((resource) => {'id': resource.id, 'name': resource.name, 'parent': resource.parentId})
          .toList()
        ..sort((a, b) => a['id']!.compareTo(b['id']!))),
  'dependencies': client.viewModel.dependencies
      .map(
        (dependency) => {
          'from': dependency.predecessorTaskId,
          'to': dependency.successorTaskId,
          'type': dependency.type.name,
          'lag': dependency.lag?.inMilliseconds,
        },
      )
      .toList(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  final clients = <_Client>[];
  Future<_Client> create(String name) async {
    final client = _Client('${directory.path}/$name.sqlite');
    clients.add(client);
    await client.open();
    return client;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gantt-offline-convergence-');
  });
  tearDown(() async {
    for (final client in clients.reversed) {
      await client.close();
    }
    clients.clear();
    await directory.delete(recursive: true);
  });

  test('offline commands update the visible state and survive restart with their outbox', () async {
    final client = await create('offline');
    await client.viewModel.addResources([LocalResource(id: 'row', name: 'Team')]);
    await client.viewModel.addTask(_task('parent'));
    await client.viewModel.addTask(_task('child', parentId: 'parent'));
    await client.viewModel.addDependencies([
      const LegacyGanttTaskDependency(
        predecessorTaskId: 'parent',
        successorTaskId: 'child',
        type: DependencyType.contained,
        lag: Duration(milliseconds: 4500),
      ),
    ]);
    final expected = {
      'tasks': [
        {'id': 'child', 'name': 'Task child', 'parent': 'parent', 'notes': 'Offline notes'},
        {'id': 'parent', 'name': 'Task parent', 'parent': null, 'notes': 'Offline notes'},
      ],
      'resources': [
        {'id': 'row', 'name': 'Team', 'parent': null},
      ],
      'dependencies': [
        {'from': 'parent', 'to': 'child', 'type': 'contained', 'lag': 4500},
      ],
    };
    expect(_visible(client), expected);
    final outgoing = await client.outgoing();
    expect(outgoing.map((operation) => operation.type), [
      'INSERT_RESOURCE',
      'INSERT_TASK',
      'INSERT_TASK',
      'INSERT_DEPENDENCY',
    ]);
    final root = await client.root();
    await client.reopen();
    expect(_visible(client), expected);
    expect(await client.outgoing(), outgoing);
    expect(await client.root(), root);
  });

  test('independent clients retain offline edits through restart and binary exchange', () async {
    final a = await create('a');
    final b = await create('b');
    await a.viewModel.addResources([LocalResource(id: 'row', name: 'Team')]);
    await a.viewModel.addTask(_task('a'));
    final initial = await a.outgoing();
    await b.receive(initial);
    expect(_visible(b), _visible(a));
    expect(await b.outgoing(), isEmpty, reason: 'Receiving updates must not enqueue them again');

    await a.viewModel.updateTask(a.viewModel.allTasks.single.copyWith(name: 'Edited offline A'));
    await b.viewModel.addTask(_task('b'));
    final fromA = (await a.outgoing()).skip(initial.length).toList();
    final fromB = await b.outgoing();
    await a.reopen();
    await b.reopen();
    expect(a.viewModel.allTasks.single.name, 'Edited offline A');
    expect(b.viewModel.allTasks.map((task) => task.id), unorderedEquals(['a', 'b']));

    await a.receive(fromB);
    await b.receive(fromA);
    final expected = {
      'tasks': [
        {'id': 'a', 'name': 'Edited offline A', 'parent': null, 'notes': 'Offline notes'},
        {'id': 'b', 'name': 'Task b', 'parent': null, 'notes': 'Offline notes'},
      ],
      'resources': [
        {'id': 'row', 'name': 'Team', 'parent': null},
      ],
      'dependencies': <Object>[],
    };
    expect(_visible(a), expected);
    expect(_visible(b), expected);
    expect(await a.root(), await b.root());
    await a.receive(fromB);
    await b.receive(fromA);
    expect(_visible(a), expected);
    expect(_visible(b), expected);
  });

  test('failed local edits restore the visible committed state and allow retry', () async {
    final client = await create('failed-edit');
    await client.viewModel.addResources([LocalResource(id: 'row', name: 'Team')]);
    await client.viewModel.addTask(_task('task'));
    final before = _visible(client);
    final outgoing = await client.outgoing();
    final root = await client.root();
    await client.database.execute('''
      CREATE TRIGGER reject_vm_outbox BEFORE INSERT ON offline_queue
      BEGIN SELECT RAISE(ABORT, 'injected persistence failure'); END
    ''');
    await expectLater(
      client.viewModel.updateTask(client.viewModel.allTasks.single.copyWith(name: 'Uncommitted edit')),
      throwsA(isA<Exception>()),
    );
    expect(_visible(client), before);
    expect(await client.outgoing(), outgoing);
    expect(await client.root(), root);
    await client.database.execute('DROP TRIGGER reject_vm_outbox');
    await client.viewModel.updateTask(client.viewModel.allTasks.single.copyWith(name: 'Successful retry'));
    expect(client.viewModel.allTasks.single.name, 'Successful retry');
    expect(await client.outgoing(), hasLength(outgoing.length + 1));
    await client.reopen();
    expect(client.viewModel.allTasks.single.name, 'Successful retry');
  });

  test('explicit offline reseed retains causal replacement clocks through binary batching', () async {
    final client = await create('reseed');
    await client.viewModel.seedLocalDatabase();
    expect(client.viewModel.allTasks, hasLength(172));
    expect(client.viewModel.localResources, hasLength(171));
    final outgoing = await client.outgoing();
    final reset = outgoing.singleWhere((operation) => operation.type == 'RESET_DATA');
    final replacements = outgoing.where((operation) => operation.type != 'RESET_DATA').toList();
    expect(replacements, isNotEmpty);
    for (final operation in replacements) {
      expect(
        operation.timestamp > reset.timestamp,
        isTrue,
        reason: 'Every replacement must be causally newer than the explicit reset',
      );
    }
    String key(Operation operation) {
      final data = operation.data;
      return '${operation.type.split('_').last}:${data['id'] ?? '${data['predecessorTaskId']}:${data['successorTaskId']}'}';
    }

    final expectedClocks = {for (final operation in replacements) key(operation): operation.timestamp};
    final decoded = _wire(_batch(replacements, 999));
    final children = (decoded.data['operations'] as List).map(
      (child) => Operation.fromJson(child as Map<String, dynamic>),
    );
    expect({for (final child in children) key(child): child.timestamp}, expectedClocks);
  });

  test('chart edit callbacks persist moves, dependency removal, creation and deletion', () async {
    final client = await create('callbacks');
    await client.viewModel.addResources([
      LocalResource(id: 'row', name: 'Team'),
      LocalResource(id: 'other-row', name: 'Other team'),
    ]);
    await client.viewModel.addTask(_task('edited'));
    await client.viewModel.handleTaskUpdate(
      client.viewModel.allTasks.single,
      DateTime.utc(2026, 11, 22),
      DateTime.utc(2026, 11, 23),
    );
    await client.viewModel.handleTaskMove(
      client.viewModel.allTasks.single,
      DateTime.utc(2026, 11, 24),
      DateTime.utc(2026, 11, 25),
      'other-row',
    );
    await client.reopen();
    final moved = client.viewModel.allTasks.single;
    expect(moved.rowId, 'other-row');
    expect(moved.start, DateTime.utc(2026, 11, 24));
    expect(moved.end, DateTime.utc(2026, 11, 25));
    expect((await client.outgoing()).where((operation) => operation.type == 'UPDATE_TASK'), hasLength(2));

    await client.viewModel.handleTaskDrawEnd(DateTime.utc(2026, 11, 26), DateTime.utc(2026, 11, 27), 'row');
    final drawn = client.viewModel.allTasks.singleWhere((task) => task.id != 'edited');
    expect(drawn.name, 'New Task');
    final dependency = LegacyGanttTaskDependency(
      predecessorTaskId: moved.id,
      successorTaskId: drawn.id,
      lag: const Duration(minutes: 5),
    );
    await client.viewModel.addDependencies([dependency]);
    final removed = client.until(() => client.viewModel.dependencies.isEmpty);
    client.viewModel.removeDependency(dependency);
    await removed;
    await client.viewModel.addDependencies([dependency]);
    final cleared = client.until(() => client.viewModel.dependencies.isEmpty);
    client.viewModel.clearDependenciesForTask(moved);
    await cleared;
    expect((await client.outgoing()).where((operation) => operation.type == 'DELETE_DEPENDENCY'), hasLength(2));
    await client.viewModel.deleteTasksBulk([drawn]);
    await client.reopen();
    expect(client.viewModel.allTasks.map((task) => task.id), ['edited']);
    expect(client.viewModel.dependencies, isEmpty);
    expect((await client.outgoing()).where((operation) => operation.type == 'DELETE_TASK'), hasLength(1));
  });

  test('summary toggles preserve unrelated field clocks and independent offline notes', () async {
    final client = await create('summary-fields');
    await client.receive([
      _operation('INSERT_RESOURCE', {'id': 'row', 'name': 'Team'}, 100),
      _operation('INSERT_TASK', {
        'id': 'task',
        'rowId': 'row',
        'name': 'Original name',
        'notes': 'Original notes',
        'start': '2026-11-20T00:00:00.000Z',
        'end': '2026-11-21T00:00:00.000Z',
      }, 100),
    ]);
    client.viewModel.setParentTaskType('row', true);
    await client.until(
      () =>
          client.viewModel.allTasks.single.fieldTimestamps['isSummary'] != null &&
          client.viewModel.allTasks.single.fieldTimestamps['isSummary']! > _clock(200),
    );
    final queued = (await client.outgoing()).single;
    final transmitted = _wire(queued);
    final fieldClocks = transmitted.data['fieldTimestamps'] as Map;
    expect(fieldClocks['notes'], _clock(100).toString());
    expect(fieldClocks['name'], _clock(100).toString());
    expect(fieldClocks['isSummary'], queued.timestamp.toString());
    await client.viewModel.handleIncomingOperationForTesting(
      _operation('UPDATE_TASK', {'id': 'task', 'notes': 'Independent offline notes'}, 200),
    );
    expect(client.viewModel.allTasks.single.name, 'Original name');
    expect(client.viewModel.allTasks.single.notes, 'Independent offline notes');
    expect(client.viewModel.allTasks.single.isSummary, isTrue);
    await client.reopen();
    expect(client.viewModel.allTasks.single.notes, 'Independent offline notes');
    expect(client.viewModel.allTasks.single.isSummary, isTrue);
    expect((await client.outgoing()).single.data['fieldTimestamps'], queued.data['fieldTimestamps']);
  });

  test('remote sparse updates merge per field and project accepted state after restart', () async {
    final client = await create('fields');
    await client.receive([
      _operation('INSERT_RESOURCE', {'id': 'row', 'name': 'Team'}, 100),
      _operation('INSERT_TASK', {
        'id': 'task',
        'rowId': 'row',
        'name': 'Original',
        'notes': 'Original notes',
        'start': '2026-11-20T00:00:00.000Z',
        'end': '2026-11-21T00:00:00.000Z',
      }, 101),
    ]);
    await client.viewModel.handleIncomingOperationForTesting(
      _operation('UPDATE_TASK', {'id': 'task', 'name': 'New name'}, 301),
    );
    await client.viewModel.handleIncomingOperationForTesting(
      _operation('UPDATE_TASK', {'id': 'task', 'notes': 'Independent earlier notes'}, 201),
    );
    await client.viewModel.handleIncomingOperationForTesting(
      _operation('UPDATE_TASK', {'id': 'task', 'name': 'Stale name'}, 200),
    );
    final expected = {
      'tasks': [
        {'id': 'task', 'name': 'New name', 'parent': null, 'notes': 'Independent earlier notes'},
      ],
      'resources': [
        {'id': 'row', 'name': 'Team', 'parent': null},
      ],
      'dependencies': <Object>[],
    };
    expect(_visible(client), expected);
    expect(await client.outgoing(), isEmpty);
    final root = await client.root();
    await client.reopen();
    expect(_visible(client), expected);
    expect(await client.root(), root);
  });

  test('a reset preserves causally newer entities regardless of delivery order', () async {
    final resetLast = await create('reset-last');
    final resetFirst = await create('reset-first');
    Operation task(String id, String row, int tick) => _operation('INSERT_TASK', {
      'id': id,
      'rowId': row,
      'name': id,
      'start': '2026-11-20T00:00:00.000Z',
      'end': '2026-11-21T00:00:00.000Z',
    }, tick);
    final older = [
      _operation('INSERT_RESOURCE', {'id': 'old-row', 'name': 'Old team'}, 100),
      task('old-a', 'old-row', 101),
      task('old-b', 'old-row', 200),
      _operation('INSERT_DEPENDENCY', {
        'predecessorTaskId': 'old-a',
        'successorTaskId': 'old-b',
        'type': 'finishToStart',
        'lag': 0,
      }, 103),
    ];
    final newer = [
      _operation('INSERT_RESOURCE', {'id': 'new-row', 'name': 'New team'}, 300),
      task('new-a', 'new-row', 301),
      task('new-b', 'new-row', 302),
      _operation('INSERT_DEPENDENCY', {
        'predecessorTaskId': 'new-a',
        'successorTaskId': 'new-b',
        'type': 'finishToStart',
        'lag': 4500,
      }, 303),
    ];
    final reset = _operation('RESET_DATA', {}, 200);
    await resetLast.receive([...older, ...newer, reset]);
    await resetFirst.receive([...older, reset, ...newer]);
    final expected = {
      'tasks': [
        {'id': 'new-a', 'name': 'new-a', 'parent': null, 'notes': null},
        {'id': 'new-b', 'name': 'new-b', 'parent': null, 'notes': null},
      ],
      'resources': [
        {'id': 'new-row', 'name': 'New team', 'parent': null},
      ],
      'dependencies': [
        {'from': 'new-a', 'to': 'new-b', 'type': 'finishToStart', 'lag': 4500},
      ],
    };
    for (final client in [resetLast, resetFirst]) {
      expect(_visible(client), expected);
      await client.reopen();
      expect(_visible(client), expected);
    }
    expect(await resetLast.root(), await resetFirst.root());
  });

  test('live, batched, and restarted replay project the same accepted reset state', () async {
    final live = await create('live');
    final batched = await create('batched');
    final replay = await create('replay');
    final resource = _operation('INSERT_RESOURCE', {'id': 'row', 'name': 'Team'}, 100);
    final original = _operation('INSERT_TASK', {
      'id': 'old',
      'rowId': 'row',
      'name': 'Original',
      'start': '2026-11-20T00:00:00.000Z',
      'end': '2026-11-21T00:00:00.000Z',
    }, 101);
    final reset = _operation('RESET_DATA', {}, 200);
    final replacement = _operation('INSERT_TASK', {
      'id': 'replacement',
      'rowId': 'row',
      'name': 'After reset',
      'start': '2026-11-20T00:00:00.000Z',
      'end': '2026-11-21T00:00:00.000Z',
    }, 202);
    final replacementResource = _operation('INSERT_RESOURCE', {'id': 'row', 'name': 'Replacement team'}, 201);
    final operations = [resource, original, reset, replacementResource, replacement];
    await live.receive(operations);
    final batches = [
      _batch([resource, original], 102),
      reset,
      _batch([replacementResource, replacement], 300),
    ];
    await batched.receive(batches);
    await replay.receive(batches);
    await replay.reopen();
    final stale = [
      _operation('RESET_DATA', {}, 150),
      reset,
      _batch([original, resource], 999),
    ];
    for (final client in [live, batched, replay]) {
      await client.receive(stale);
      expect(_visible(client), {
        'tasks': [
          {'id': 'replacement', 'name': 'After reset', 'parent': null, 'notes': null},
        ],
        'resources': [
          {'id': 'row', 'name': 'Replacement team', 'parent': null},
        ],
        'dependencies': <Object>[],
      });
      expect(await client.outgoing(), isEmpty);
    }
    expect(await live.root(), await batched.root());
    expect(await live.root(), await replay.root());
  });
}
