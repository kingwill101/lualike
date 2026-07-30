import 'dart:io';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';

Future<void> main() async {
  final code = File('/tmp/list_bar.lua').readAsStringSync();
  for (final mode in [EngineMode.ast, EngineMode.luaBytecode]) {
    print('=== $mode ===');
    try {
      await executeCode(code, mode: mode);
    } catch (e) {
      print('FAIL $e');
    }
  }
}
