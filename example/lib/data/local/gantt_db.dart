import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

class GanttDb {
  static SqliteCrdt? _db;

  static Future<SqliteCrdt> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<SqliteCrdt> _init() async {
    // Initialization of sqflite_ffi / web factory is now handled in main() via platform_init

    String path = 'gantt_local.db';
    if (!kIsWeb) {
      final dir = await getApplicationSupportDirectory();
      path = join(dir.path, 'gantt_local.db');
    }

    return await SqliteCrdt.open(
      path,
      onCreate: (db, version) async {
        // Tasks table
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            row_id TEXT,
            start_date TEXT,
            end_date TEXT,
            name TEXT,
            resource_id TEXT,
            color TEXT,
            text_color TEXT,
            stack_index INTEGER,
            is_summary INTEGER,
            is_milestone INTEGER,
            completion REAL
          )
        ''');

        // Dependencies table
        // We use a composite primary key or just a rowid + unique constraint
        await db.execute('''
          CREATE TABLE dependencies (
            from_id TEXT,
            to_id TEXT,
            type INTEGER,
            lag_ms INTEGER,
            PRIMARY KEY (from_id, to_id)
          )
        ''');
        // Resources table
        await db.execute('''
          CREATE TABLE resources (
            id TEXT PRIMARY KEY,
            name TEXT,
            parent_id TEXT,
            is_expanded INTEGER DEFAULT 1
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE resources (
              id TEXT PRIMARY KEY,
              name TEXT,
              parent_id TEXT,
              is_expanded INTEGER DEFAULT 1
            )
          ''');
        }
        if (oldVersion < 3) {
          // If resources table exists (ver 2), alter it. If it was just created in ver < 2 block, we have to check or just create it with column.
          // Since we are upgrading sequentially:
          // If oldVersion was 1, we executed createtable just now.
          // Wait, CREATE TABLE in block < 2 does NOT have is_expanded.
          // So we can alter table here repeatedly or check if column exists.
          // Safer to just use ALTER TABLE if it exists.

          // However, if we just created it in <2 block, it's fresh.
          // But simpler approach: in <2 block create with ALL columns? No, strict versioning.

          try {
            await db.execute('ALTER TABLE resources ADD COLUMN is_expanded INTEGER DEFAULT 1');
          } catch (e) {
            // Might fail if table doesn't exist? (it should)
            // Or if column already exists (shouldn't given logic)
            // But if we just created it above...
          }
        }
      },
      version: 3,
    );
  }
}
