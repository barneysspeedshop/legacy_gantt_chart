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
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
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
            baseline_start TEXT,
            baseline_end TEXT,
            notes TEXT,
            last_updated INTEGER,
            deleted_at INTEGER,
            uses_work_calendar INTEGER
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
            deleted_at INTEGER,
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
            last_updated INTEGER,
            deleted_at INTEGER
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

        // KV Store table (for sync metadata)
        await db.execute('''
          CREATE TABLE sync_metadata (
            meta_key TEXT PRIMARY KEY,
            meta_value TEXT
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
            // Or if column already exists (shouldn't given logic)
            // But if we just created it above...
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
          // Add last_updated and deleted_at columns to all tables
          // Tasks
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN last_updated INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN deleted_at INTEGER');
          } catch (_) {}
          // Migrate is_deleted (if we have access to it, SqliteCrdt usually manages it, but we want our own tracking)
          // We can't easily read the internal is_deleted here via raw SQL if it's hidden or managed,
          // but SqliteCrdt exposes it.
          // Let's assume we maintain parallel state for now or just init deleted_at null.

          // Dependencies
          try {
            await db.execute('ALTER TABLE dependencies ADD COLUMN last_updated INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE dependencies ADD COLUMN deleted_at INTEGER');
          } catch (_) {}

          // Resources
          try {
            await db.execute('ALTER TABLE resources ADD COLUMN last_updated INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE resources ADD COLUMN deleted_at INTEGER');
          } catch (_) {}
        }
        if (oldVersion < 7) {
          // Attempted creation of kv_store, might have failed or been bad.
          // We will fix in v8.
        }
        if (oldVersion < 8) {
          try {
            await db.execute('DROP TABLE IF EXISTS kv_store');
          } catch (_) {}
          try {
            await db.execute('''
              CREATE TABLE sync_metadata (
                meta_key TEXT PRIMARY KEY,
                meta_value TEXT
              )
            ''');
          } catch (_) {}
        }
        if (oldVersion < 9) {
          // Force fix for sync_metadata missing
          try {
            await db.execute('DROP TABLE IF EXISTS kv_store');
          } catch (e) {
            print('Error dropping kv_store: $e');
          }
          try {
            await db.execute('DROP TABLE IF EXISTS sync_metadata');
          } catch (e) {
            print('Error dropping sync_metadata: $e');
          }
          try {
            await db.execute('''
              CREATE TABLE sync_metadata (
                meta_key TEXT PRIMARY KEY,
                meta_value TEXT
              )
            ''');
            print('Successfully created sync_metadata table (v9 migration)');
          } catch (e) {
            print('Error creating sync_metadata table: $e');
            rethrow; // Don't hide it this time
          }
        }
        if (oldVersion < 10) {
          // REPAIR: Add last_updated and deleted_at columns if missing (fresh installs on v9 had buggy onCreate)
          // Tasks
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN last_updated INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN deleted_at INTEGER');
          } catch (_) {}

          // Dependencies
          try {
            await db.execute('ALTER TABLE dependencies ADD COLUMN last_updated INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE dependencies ADD COLUMN deleted_at INTEGER');
          } catch (_) {}

          // Resources
          try {
            await db.execute('ALTER TABLE resources ADD COLUMN last_updated INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE resources ADD COLUMN deleted_at INTEGER');
          } catch (_) {}
          print('Successfully applied v10 column repair');
        }
        if (oldVersion < 11) {
          // Add new feature columns
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN baseline_start TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN baseline_end TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN notes TEXT');
          } catch (_) {}
          // completion/resource_id were already in create but missing from v10 upgrade if user was on old version?
          // Actually completion was in CREATE but not explicitly added in upgrades.
          // Resource_id was in CREATE.
          // Let's add them safely just in case.
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN completion REAL DEFAULT 0.0');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN resource_id TEXT');
          } catch (_) {}

          // Dependencies
          try {
            await db.execute('ALTER TABLE dependencies ADD COLUMN lag_ms INTEGER');
          } catch (_) {}
        }
        if (oldVersion < 12) {
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN uses_work_calendar INTEGER DEFAULT 0');
          } catch (_) {}
        }

        // SqliteCrdt automatically ensures all CRDT columns (is_deleted, hlc, etc.) are present
        // on open, so we don't need manual migration for is_deleted.
      },
      version: 12,
    );

    // Enable WAL mode for better concurrency (allows concurrent reads and writes)
    if (!kIsWeb) {
      await db.execute('PRAGMA journal_mode=WAL');
      await db.execute('PRAGMA busy_timeout=5000'); // Wait up to 5 seconds for locks
    }

    return db;
  }
}
