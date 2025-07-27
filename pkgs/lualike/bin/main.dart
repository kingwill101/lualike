import 'dart:io';

import 'package:lualike/command/lualike_command_runner.dart';

/// Main entry point for the LuaLike interpreter
Future<void> main(List<String> args) async {
  final runner = LuaLikeCommandRunner();

  try {
    await runner.run(args);
  } catch (e) {
    // if (runner.debugMode) {
    //   Logger.error('Error: $e');
    //   Logger.error('Stack trace: $stackTrace');
    // }
    exit(1);
  }
}
