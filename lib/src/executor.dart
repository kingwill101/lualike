import 'package:lualike/src/bytecode/bytecode.dart' show BytecodeChunk;
import 'package:lualike/src/bytecode/compiler.dart' show Compiler;
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/lua_error.dart';

import 'ast.dart';
import 'exceptions.dart';
import 'file_manager.dart';
import 'parser_wrapper.dart';
import 'interpreter/interpreter.dart';

typedef InterpreterSetupCallback = void Function(Interpreter);

/// Specifies how code should be executed by the interpreter.
enum ExecutionMode {
  /// Execute code by walking the AST directly
  astInterpreter,

  /// Execute code by compiling to bytecode first
  bytecodeVM,
}

/// Executes source code using the specified execution mode.
///
/// [sourceCode] - The source code to execute
/// [mode] - Whether to use AST interpretation or bytecode compilation
/// [environment] - Optional environment for variable scope
/// [fileManager] - Optional file manager for I/O operations
///
/// Returns the result of executing the code.
Future<Object?> executeCode(
  String sourceCode,
  ExecutionMode mode, {
  FileManager? fileManager,
  InterpreterSetupCallback? onInterpreterSetup,
}) async {
  if (mode == ExecutionMode.astInterpreter) {
    final vm = Interpreter(fileManager: fileManager);
    if (onInterpreterSetup != null) {
      onInterpreterSetup(vm);
    }
    final program = parse(sourceCode);
    try {
      return await vm.run(program.statements);
    } on ReturnException catch (e) {
      // Handle return statement at the top level
      return e.value;
    } on Exception catch (e, s) {
      // Format error message in Lua style
      String errorMsg = e.toString();
      if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring('Exception: '.length);
      }

      vm.reportError(errorMsg, trace: s);
      rethrow;
    }
  } else if (mode == ExecutionMode.bytecodeVM) {
    final compiler = Compiler();
    final program = parse(sourceCode);
    final bytecodeChunk = await compiler.compile(program.statements);
    final vm = BytecodeVM();
    return vm.execute(bytecodeChunk);
  } else {
    throw LuaError('Invalid ExecutionMode: $mode');
  }
}

/// Compiles source code to bytecode without executing it.
///
/// [sourceCode] - The source code to compile
/// [fileManager] - Optional file manager for I/O operations
///
/// Returns the compiled bytecode chunk.
Future<BytecodeChunk> compileToBytecode(
  String sourceCode, {
  FileManager? fileManager,
}) async {
  final compiler = Compiler();
  final program = parse(sourceCode);
  return await compiler.compile(program.statements);
}

/// Executes a pre-compiled bytecode chunk.
///
/// [chunk] - The bytecode chunk to execute
/// [fileManager] - Optional file manager for I/O operations
///
/// Returns the result of executing the bytecode.
Future<Object?> executeBytecodeChunk(
  BytecodeChunk chunk, {
  FileManager? fileManager,
}) async {
  final vm = BytecodeVM();
  return vm.execute(chunk);
}

/// Executes an AST directly without compilation.
///
/// [program] - The AST nodes to execute
/// [fileManager] - Optional file manager for I/O operations
///
/// Returns the result of executing the AST.
Future<Object?> executeAst(
  List<AstNode> program, {
  FileManager? fileManager,
  InterpreterSetupCallback? onInterpreterSetup,
}) async {
  final vm = Interpreter(fileManager: fileManager);
  if (onInterpreterSetup != null) {
    onInterpreterSetup(vm);
  }
  return await vm.run(program);
}
