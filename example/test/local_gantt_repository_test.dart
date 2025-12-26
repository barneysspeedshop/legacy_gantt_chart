// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/data/local/gantt_db.dart';
import '../lib/data/local/local_gantt_repository.dart';
import 'package:legacy_gantt_chart/src/sync/hlc.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('LocalGanttRepository persists lastServerSyncTimestamp', () async {
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();

    final repo = LocalGanttRepository();
    await repo.init();

    // Initial state should be null
    expect(await repo.getLastServerSyncTimestamp(), isNull);

    // Set value
    final now = Hlc.fromDate(DateTime.now(), 'local');
    await repo.setLastServerSyncTimestamp(now);

    // Verify persistence
    expect(await repo.getLastServerSyncTimestamp(), equals(now));

    // Update value
    final later = Hlc.fromIntTimestamp(now.millis + 1000);
    await repo.setLastServerSyncTimestamp(later);
    expect(await repo.getLastServerSyncTimestamp(), equals(later));
  });
}
