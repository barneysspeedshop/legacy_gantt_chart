import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initializePlatform() async {
  // Disable the default browser context menu to allow our custom context menu to handle right-clicks.
  await BrowserContextMenu.disableContextMenu();

  databaseFactory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      // FIX 1: Explicitly point to the WASM file.
      // Without this, the worker might look for it at the root domain instead of your base href.
      sharedWorkerUri: Uri.parse('sqflite_sw.js'),
      sqlite3WasmUri: Uri.parse('sqlite3.wasm'),

      // FIX 2 (Optional): Uncomment the line below if "Error: 3" persists.
      // "Error: 3" is often a Permission Denied error because GitHub Pages lacks
      // the COOP/COEP headers required for SharedWorkers using SharedArrayBuffer.
      // forceAsBasicWorker: true,
    ),
  );
}
