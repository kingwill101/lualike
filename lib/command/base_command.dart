import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lualike/testing.dart';

/// Base class for all LuaLike commands providing common functionality
abstract class BaseCommand extends Command {
  // Use a single global bridge instance for consistency
  static final LuaLike _globalBridge = LuaLike();

  /// Get the global LuaLike bridge instance
  LuaLike get bridge => _globalBridge;

  /// Safe print function that doesn't flush stdout
  void safePrint(String message) {
    print(message);
  }

  /// Handle LUA_INIT environment variable
  Future<void> handleLuaInit() async {
    final luaInit = Platform.environment['LUA_INIT'];
    if (luaInit != null && luaInit.isNotEmpty) {
      if (luaInit.startsWith('@')) {
        // Execute file
        final filename = luaInit.substring(1);
        try {
          final sourceCode = await File(
            filename,
          ).readAsBytes().then((bytes) => utf8.decode(bytes));
          await bridge.execute(sourceCode, scriptPath: filename);
        } catch (e) {
          safePrint('Error in LUA_INIT file: $e');
          exit(1);
        }
      } else {
        // Execute string
        try {
          await bridge.execute(luaInit);
        } catch (e) {
          safePrint('Error in LUA_INIT: $e');
          exit(1);
        }
      }
    }
  }

  /// Setup the global arg table following Lua's conventions
  void setupArgTable({
    required List<String> originalArgs,
    String? scriptPath,
    List<String> scriptArgs = const [],
    List<String> codeStrings = const [],
  }) {
    final argTable = <dynamic, dynamic>{};

    if (scriptPath != null) {
      // Script file mode: arg[0] is script name, arg[1..n] are script arguments
      argTable[0] = scriptPath;
      for (int i = 0; i < scriptArgs.length; i++) {
        argTable[i + 1] = scriptArgs[i];
      }
      // Store interpreter name at negative index
      argTable[-1] = 'lualike';
    } else if (codeStrings.isNotEmpty) {
      // -e mode: arg[0] is interpreter name, arg[1] is -e, arg[2] is code
      argTable[0] = 'lualike';
      int index = 1;
      for (final code in codeStrings) {
        argTable[index++] = '-e';
        argTable[index++] = code;
      }
    } else {
      // No script or code: arg[0] is interpreter name
      argTable[0] = 'lualike';
    }

    // Note: We don't set arg.n as it's nil in actual Lua 5.4.8

    // Set the global arg table
    bridge.setGlobal('arg', argTable);
  }
}
