import 'dart:convert';
import 'dart:typed_data';

import 'dart:io';

import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:path/path.dart' as path;

import 'base_command.dart';

/// Command to execute script files
class ScriptCommand extends BaseCommand {
  @override
  String get name => 'script';

  @override
  String get description => 'Execute a Lua script file';

  final String scriptPath;
  final List<String> scriptArgs;
  final List<String> originalArgs;

  ScriptCommand(this.scriptPath, this.scriptArgs, this.originalArgs);

  @override
  Future<void> run() async {
    try {
      // Setup arg table for script mode
      setupArgTable(
        originalArgs: originalArgs,
        scriptPath: scriptPath,
        scriptArgs: scriptArgs,
      );

      // Execute the script
      final file = File(scriptPath);
      if (!file.existsSync()) {
        safePrint('Error: Script file "$scriptPath" not found');
        exit(1);
      }

      final bytes = await file.readAsBytes();

      // Get absolute path for better debugging
      final absolutePath = file.absolute.path;
      _updateScriptMetadata(absolutePath);

      if (looksLikeTrackedLuaBytecodeBytes(bytes)) {
        final loadResult = await bridge.vm.loadChunk(
          LuaChunkLoadRequest(
            source: Value(LuaString.fromBytes(Uint8List.fromList(bytes))),
            chunkName: absolutePath,
            mode: 'b',
          ),
        );
        if (!loadResult.isSuccess) {
          throw Exception(loadResult.errorMessage ?? 'failed to load chunk');
        }
        await bridge.vm.callFunction(loadResult.chunk!, const <Object?>[]);
        return;
      }

      final sourceCode = utf8.decode(bytes);

      await bridge.execute(sourceCode, scriptPath: absolutePath);
    } catch (e, s) {
      safePrint('Error executing script "$scriptPath": $e');
      safePrint(s.toString());
      rethrow;
    }
  }

  void _updateScriptMetadata(String scriptPath) {
    final normalizedPath = path.url.joinAll(
      path.split(path.normalize(scriptPath)),
    );
    bridge.vm.globals.define('_SCRIPT_PATH', Value(normalizedPath));
    bridge.vm.callStack.setScriptPath(normalizedPath);
    bridge.vm.currentScriptPath = normalizedPath;

    final scriptDir = path.dirname(scriptPath);
    final normalizedDir = path.url.joinAll(
      path.split(path.normalize(scriptDir)),
    );
    bridge.vm.globals.define('_SCRIPT_DIR', Value(normalizedDir));
    if (scriptDir.isNotEmpty) {
      bridge.vm.fileManager.addSearchPath(scriptDir);
    }
  }
}
