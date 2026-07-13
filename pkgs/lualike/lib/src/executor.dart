import 'dart:io' show stderr;

import 'exceptions.dart';
import 'file_manager.dart';
import 'interpreter/interpreter.dart';
import 'parse.dart';
import 'semantic_checker.dart';
import 'runtime/lua_runtime.dart';
import 'config.dart';
import 'compile/pipeline.dart';
import 'ir/runtime.dart';
import 'lua_error.dart';
import 'lua_bytecode/runtime.dart';
import 'lua_string.dart';
import 'runtime/lua_slot.dart';
import 'value.dart';

typedef RuntimeSetupCallback = void Function(LuaRuntime);

/// Executes source code using the specified execution mode.
///
/// [sourceCode] - The source code to execute
/// [mode] - Whether to use AST interpretation or IR compilation
/// [environment] - Optional environment for variable scope
/// [fileManager] - Optional file manager for I/O operations
/// [url] - Optional chunk source name or file path used for parser context
/// [foldEnabled] - Whether to enable constant folding (bytecode modes only).
///   Defaults to [LuaLikeConfig.foldEnabled].
///
/// Returns the result of executing the code.
Future<Object?> executeCode(
  String sourceCode, {
  FileManager? fileManager,
  RuntimeSetupCallback? onRuntimeSetup,
  LuaRuntime? vm,
  EngineMode? mode,
  Object? url,
  bool? foldEnabled,
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
    // Preserve the caller's chunk source so file-backed parse behavior such as
    // shebang stripping and diagnostic source names matches Lua's file loader.
    final program = parse(sourceCode, url: url);

    final semanticError = validateProgramSemantics(program);
    if (semanticError != null) {
      throw Exception(semanticError);
    }

    // --fold / foldEnabled: compile through CompilePipeline (IR + SSA) then
    // load serialized bytecode. That path depends on:
    //   * SSA passes staying register-safe (CALL multi-reg, GVN kills, etc.)
    //   * parse-time local register inference after serialize
    //   * main lineDefined == 0 from IR lowering
    // See doc/decisions.md (IR contract + official bytecode locals).
    // Direct --lua-bytecode without fold uses the emitter via runAst instead.
    final folding = foldEnabled ?? LuaLikeConfig().foldEnabled;
    if (folding && selectedMode != EngineMode.ast) {
      final backend = switch (selectedMode) {
        EngineMode.luaBytecode => CompileBackend.luaBytecode,
        EngineMode.ir => CompileBackend.lualikeIR,
        _ => CompileBackend.luaBytecode,
      };
      // SSA is only enabled for the lua-bytecode backend today: the pure IR
      // VM cannot execute some post-SSA instruction shapes.
      final enableSsa = backend == CompileBackend.luaBytecode;
      final pipeline = CompilePipeline(
        config: CompilePipelineConfig(
          enableConstantFolding: true,
          enablePeephole: enableSsa,
          enableSsaDeadCodeElimination: enableSsa,
          enableSsaGlobalValueNumbering: enableSsa,
          enableSsaSccp: enableSsa,
          // LICM/coalesce/escape currently follow the fold path for bytecode
          // even when enableSsa is false for IR — keep them tied to enableSsa
          // if the IR backend is ever given a different pipeline.
          enableSsaLicm: enableSsa,
          enableSsaCoalesce: enableSsa,
          enableSsaEscape: enableSsa,
          dumpIr: LuaLikeConfig().dumpIr,
          target: backend,
        ),
      );
      final artifact = pipeline.compile(program);

      // Print IR disassembly if requested.
      if (artifact is LualikeIrArtifact && artifact.disassembly != null) {
        stderr.writeln(artifact.disassembly);
      }
      if (artifact is LualikeIrArtifact && artifact.ssaDisassembly != null) {
        stderr.writeln('--- Lualike SSA ---');
        stderr.writeln(artifact.ssaDisassembly);
        stderr.writeln('--- End Lualike SSA ---');
      }

      final chunk = await runtime.loadBytecode(
        artifact.serializedBytes,
        moduleName: url?.toString() ?? '=(pipeline)',
      );
      await runtime.callFunction(chunk, const <Object?>[]);
      return null;
    }

    return _publicExecutionResult(await runtime.runAst(program.statements));
  } on ReturnException catch (e) {
    // Handle return statement at the top level
    return _publicExecutionResult(e.value);
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

Object? _publicExecutionResult(Object? result) {
  final resultValues = luaResultValues(result);
  if (resultValues != null) {
    return valueMultiFromLuaResults(resultValues.map(_publicResultSlot));
  }
  return _publicResultSlot(result);
}

Object? _publicResultSlot(Object? result) {
  if (result is Value) {
    final raw = rawLuaSlot(result);
    if (isLuaScalarPrimitiveSlot(raw)) {
      return raw;
    }
    if (raw is LuaString) {
      return raw.toString();
    }
  }
  if (result is LuaString) {
    return result.toString();
  }
  return result;
}
