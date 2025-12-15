import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initializePlatform() async {
  databaseFactory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      sharedWorkerUri: Uri.parse('sqflite_sw.js'),
    ),
  );
}
