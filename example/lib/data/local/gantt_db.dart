import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

class GanttDb {
  static SqliteCrdt? _db;
  static String? overridePath;

  static Future<SqliteCrdt> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<void> reset() async {
    _db = null;
  }

  static Future<SqliteCrdt> _init() async {
    // Initialization of sqflite_ffi / web factory is now handled in main() via platform_init

    String path = 'gantt_local.db';
    if (overridePath != null) {
      path = overridePath!;
    } else if (!kIsWeb) {
      final dir = await getApplicationSupportDirectory();
      path = join(dir.path, 'gantt_local.db');
    }

    final db = await SqliteCrdt.open(
      path,
      version: 6,
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
            completion REAL,
            last_updated INTEGER
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
            last_updated INTEGER,
            PRIMARY KEY (from_id, to_id)
          )
        ''');
        // Resources table
        await db.execute('''
          CREATE TABLE resources (
            id TEXT PRIMARY KEY,
            name TEXT,
            parent_id TEXT,
            is_expanded INTEGER DEFAULT 1,
            last_updated INTEGER
          )
        ''');

        // Offline Queue table (for sync)
        await db.execute('''
          CREATE TABLE offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            data TEXT,
            timestamp INTEGER,
            actor_id TEXT
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
          try {
            await db.execute('ALTER TABLE resources ADD COLUMN is_expanded INTEGER DEFAULT 1');
          } catch (e) {
            // Might fail if table doesn't exist? (it should)
          }
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE offline_queue (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT,
              data TEXT,
              timestamp INTEGER,
              actor_id TEXT
            )
          ''');
        }
        if (oldVersion < 6) {
          // Ensure these columns exist for everyone upgrading to v6
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN last_updated INTEGER');
            await db.execute('ALTER TABLE dependencies ADD COLUMN last_updated INTEGER');
            await db.execute('ALTER TABLE resources ADD COLUMN last_updated INTEGER');
          } catch (e) {
            // Ignore if columns already exist
          }
        }
      },
    );

    // Enable WAL mode for better concurrency (allows concurrent reads and writes)
    if (!kIsWeb) {
      await db.execute('PRAGMA journal_mode=WAL');
      await db.execute('PRAGMA busy_timeout=5000'); // Wait up to 5 seconds for locks
    }

    return db;
  }
}
