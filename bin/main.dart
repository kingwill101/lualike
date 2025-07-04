import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:lualike/command/lualike_command_runner.dart';

/// Main entry point for the LuaLike interpreter
Future<void> main(List<String> args) async {
  final runner = LuaLikeCommandRunner();

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    print(e.message);
    print('');
    print(runner.usage);
    exit(1);
  } catch (e, stackTrace) {
    print('Error: $e');
    if (runner.debugMode) {
      print('Stack trace: $stackTrace');
    }
    exit(1);
  }
}
