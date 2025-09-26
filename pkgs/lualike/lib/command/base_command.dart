import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lualike/src/interop.dart';

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
    final interpreter = _getInterpreterCommand();

    // For Lua compatibility we store the *display string* in arg[-1]/arg[0]
    // (joined with a single space) – when we actually spawn a subprocess
    // we use the list that `_getInterpreterCommand()` returned.
    final interpreterDisplay = interpreter.join(' ');

    if (scriptPath != null) {
      // Script file mode: arg[0] is script name, arg[1..n] are script arguments
      argTable[0] = scriptPath;
      for (var i = 0; i < scriptArgs.length; ++i) {
        argTable[i + 1] = scriptArgs[i];
      }
      argTable[-1] = interpreterDisplay;
    } else if (codeStrings.isNotEmpty) {
      // -e mode: arg[0] is interpreter name, arg[1] is -e, arg[2] is code
      argTable[0] = interpreterDisplay;
      var index = 1;
      for (final code in codeStrings) {
        argTable[index++] = '-e';
        argTable[index++] = code;
      }
    } else {
      // No script or code: arg[0] is interpreter name
      argTable[0] = interpreterDisplay;
    }

    print("Interpreter command: $interpreterDisplay");
    // Note: We don't set arg.n as it's nil in actual Lua 5.4.8

    // Set the global arg table
    bridge.setGlobal('arg', argTable);
  }

  /// Returns the command that has to be executed to launch **this very
  /// program** again.  The first element is the executable, the remaining
  /// elements are arguments that belong *before* any user-supplied args.
  ///
  ///   • [0]  → executable (`/usr/bin/lualike` or `/usr/bin/dart`)
  ///   • [1 …]→ extra args (`bin/main.dart`, "run", …)            ── optional
  List<String> _getInterpreterCommand() {
    final exe = Platform.resolvedExecutable; // what launched us
    final script = Platform.script.toFilePath(); // the entry-point script

    // Does the name of the executable look like the Dart VM?
    bool looksLikeDartVm(String path) {
      final name = path.split(Platform.pathSeparator).last.toLowerCase();
      return name == 'dart' || name == 'dart.exe';
    }

    if (looksLikeDartVm(exe)) {
      // We are running on the Dart VM. We need to reconstruct the full command
      // including all the flags that were passed to dart.

      // Get all the arguments that were passed to dart (including flags)
      final allArgs = Platform.executableArguments;

      // Find where the script path appears in the arguments
      int scriptIndex = -1;
      for (int i = 0; i < allArgs.length; i++) {
        if (allArgs[i] == script || allArgs[i].endsWith('bin/main.dart')) {
          scriptIndex = i;
          break;
        }
      }

      if (scriptIndex >= 0) {
        // Include all arguments up to and including the script
        final cmd = [exe, ...allArgs.take(scriptIndex + 1)];
        return cmd;
      }

      // Fallback: just dart + script
      return [exe, script];
    }

    // AOT / native executable – can be run directly
    return [exe];
  }
}
