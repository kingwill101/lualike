import 'dart:convert';
import 'dart:io';

import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/lua_bytecode/vm_value_helpers.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/value.dart';
import 'package:path/path.dart' as path;

import 'base_command.dart';

/// Command to execute script files.
///
/// Precompiled Lua bytecode (`.lub` / official chunk header) is loaded and
/// run **directly on the bytecode VM**. It never enters
/// `executeCode` / `CompilePipeline` / IR / SSA.
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

      final looksBytecode = looksLikeTrackedLuaBytecodeBytes(bytes);
      final lubExtension = path.extension(scriptPath).toLowerCase() == '.lub';

      if (lubExtension && !looksBytecode) {
        throw Exception(
          'File "$scriptPath" has a .lub extension but is not a valid '
          'Lua bytecode chunk (bad or missing header). Recompile with '
          '`--compile -o file.lub`.',
        );
      }

      if (looksBytecode) {
        // Direct binary path: parse chunk → invoke VM. No IR/SSA/pipeline.
        await _runPrecompiledBytecode(bytes, absolutePath);
        return;
      }

      final sourceCode = () {
        try {
          return utf8.decode(bytes);
        } on FormatException {
          // Lua suite files such as strings.lua still use raw Latin-1 bytes.
          return latin1.decode(bytes);
        }
      }();

      await bridge.execute(sourceCode, scriptPath: absolutePath);
    } catch (e, s) {
      safePrint('Error executing script "$scriptPath": $e');
      safePrint(s.toString());
      rethrow;
    }
  }

  /// Load a precompiled chunk and run it on [LuaBytecodeRuntime] only.
  ///
  /// Steps: `LuaBytecodeParser.parse` → `LuaBytecodeClosure.main` (live env)
  /// → `callFunction`. Does not call [LuaLike.execute] or the compile pipeline.
  Future<void> _runPrecompiledBytecode(
    List<int> bytes,
    String chunkName,
  ) async {
    final runtime = _requireBytecodeRuntime();
    final chunk = const LuaBytecodeParser().parse(bytes);
    final env = runtime.getCurrentEnv();
    final closure = LuaBytecodeClosure.main(
      runtime: runtime,
      chunk: chunk,
      chunkName: chunkName,
      // Top-level scripts share live globals (stdlib, prior -e state).
      environment: env,
    );
    final function = Value(closure)..interpreter = runtime;
    await runtime.callFunction(function, const <Object?>[]);
  }

  /// Precompiled chunks must run on the bytecode VM, not AST/IR.
  LuaBytecodeRuntime _requireBytecodeRuntime() {
    final vm = bridge.vm;
    if (vm is LuaBytecodeRuntime) {
      return vm;
    }
    throw StateError(
      'Precompiled bytecode requires the lua_bytecode engine, but the '
      'runtime is ${vm.runtimeType}. Pass --lua-bytecode or open a .lub '
      'file (auto-selected).',
    );
  }

  void _updateScriptMetadata(String scriptPath) {
    final normalizedPath = path.url.joinAll(
      path.split(path.normalize(scriptPath)),
    );
    bridge.vm.globals.define(
      '_SCRIPT_PATH',
      valueFromLuaSlot(bridge.vm, normalizedPath),
    );
    bridge.vm.callStack.setScriptPath(normalizedPath);
    bridge.vm.currentScriptPath = normalizedPath;

    final scriptDir = path.dirname(scriptPath);
    final normalizedDir = path.url.joinAll(
      path.split(path.normalize(scriptDir)),
    );
    bridge.vm.globals.define(
      '_SCRIPT_DIR',
      valueFromLuaSlot(bridge.vm, normalizedDir),
    );
    if (scriptDir.isNotEmpty) {
      bridge.vm.fileManager.addSearchPath(scriptDir);
    }
  }
}
