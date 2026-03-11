import 'exceptions.dart';
import 'file_manager.dart';
import 'interpreter/interpreter.dart';
import 'parse.dart';
import 'semantic_checker.dart';
import 'runtime/lua_runtime.dart';
import 'config.dart';
import 'ir/compiler.dart';
import 'ir/disassembler.dart';
import 'ir/runtime.dart';
import 'ir/vm.dart';
import 'lua_error.dart';
import 'lua_bytecode/runtime.dart';

typedef RuntimeSetupCallback = void Function(LuaRuntime);

/// Executes source code using the specified execution mode.
///
/// [sourceCode] - The source code to execute
/// [mode] - Whether to use AST interpretation or IR compilation
/// [environment] - Optional environment for variable scope
/// [fileManager] - Optional file manager for I/O operations
///
/// Returns the result of executing the code.
Future<Object?> executeCode(
  String sourceCode, {
  FileManager? fileManager,
  RuntimeSetupCallback? onRuntimeSetup,
  LuaRuntime? vm,
  EngineMode? mode,
}) async {
  final selectedMode = mode ?? LuaLikeConfig().defaultEngineMode;
  final runtime =
      vm ??
      switch (selectedMode) {
        EngineMode.ir => LualikeIrRuntime(fileManager: fileManager),
        EngineMode.luaBytecode => LuaBytecodeRuntime(fileManager: fileManager),
        EngineMode.ast => Interpreter(fileManager: fileManager),
      };
  if (onRuntimeSetup != null) {
    onRuntimeSetup(runtime);
  }

  try {
    final program = parse(sourceCode);

    final semanticError = validateProgramSemantics(program);
    if (semanticError != null) {
      throw Exception(semanticError);
    }

    if (selectedMode == EngineMode.ir) {
      final chunk = LualikeIrCompiler().compile(program);
      if (LuaLikeConfig().dumpIr) {
        final disassembly = disassembleChunk(chunk);
        if (disassembly.isNotEmpty) {
          print('--- IR Disassembly ---');
          print(disassembly);
          print('--- End IR Disassembly ---');
        }
      }
      final result = await LualikeIrVm(
        environment: runtime.globals,
        runtime: runtime,
      ).execute(chunk);
      return result;
    }

    return await runtime.runAst(program.statements);
  } on ReturnException catch (e) {
    // Handle return statement at the top level
    return e.value;
  } on Exception catch (e, s) {
    // Format error message in Lua style
    final String errorMsg = switch (e) {
      final LuaError luaError => luaError.message,
      _ => () {
        var message = e.toString();
        if (message.startsWith('Exception: ')) {
          message = message.substring('Exception: '.length);
        }
        return message;
      }(),
    };

    runtime.reportError(errorMsg, trace: s, error: e);
    rethrow;
  }
}
