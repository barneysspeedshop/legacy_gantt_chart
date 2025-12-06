import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initializePlatform() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
