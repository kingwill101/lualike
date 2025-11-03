import 'const_checker.dart';
import 'exceptions.dart';
import 'file_manager.dart';
import 'interpreter/interpreter.dart';
import 'parse.dart';
import 'runtime/lua_runtime.dart';
import 'config.dart';
import 'bytecode/compiler.dart';
import 'bytecode/disassembler.dart';
import 'bytecode/vm.dart';

typedef RuntimeSetupCallback = void Function(LuaRuntime);

/// Executes source code using the specified execution mode.
///
/// [sourceCode] - The source code to execute
/// [mode] - Whether to use AST interpretation or bytecode compilation
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
  final runtime = vm ?? Interpreter(fileManager: fileManager);
  if (onRuntimeSetup != null) {
    onRuntimeSetup(runtime);
  }
  final program = parse(sourceCode);

  // Check for const variable assignment errors
  final constChecker = ConstChecker();
  final constError = constChecker.checkConstViolations(program);
  if (constError != null) {
    throw Exception(constError);
  }

  try {
    if (selectedMode == EngineMode.bytecode) {
      final chunk = BytecodeCompiler().compile(program);
      if (LuaLikeConfig().dumpBytecode) {
        final disassembly = disassembleChunk(chunk);
        if (disassembly.isNotEmpty) {
          print('--- Bytecode Disassembly ---');
          print(disassembly);
          print('--- End Disassembly ---');
        }
      }
      final result = await BytecodeVm(
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
    String errorMsg = e.toString();
    if (errorMsg.startsWith('Exception: ')) {
      errorMsg = errorMsg.substring('Exception: '.length);
    }

    runtime.reportError(errorMsg, trace: s, error: e);
    rethrow;
  }
}
