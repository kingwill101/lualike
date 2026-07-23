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
import 'lua_bytecode/vm_value_helpers.dart';
import 'lua_string.dart';
import 'runtime/lua_slot.dart';
import 'value.dart';

typedef RuntimeSetupCallback = void Function(LuaRuntime);

/// Executes **source** text using the selected engine.
///
/// This is the text path only. Precompiled binary chunks are handled by the
/// CLI or [LuaRuntime.loadChunk] after a header sniff
/// (`looksLikeTrackedLuaBytecodeBytes`); those paths invoke the bytecode VM
/// directly and must not call this function.
///
/// Engine routing for [mode]:
/// * [EngineMode.luaBytecode] — always IR + SSA + mechanical lower, then
///   the bytecode VM (shared with `--compile` via
///   `CompilePipelineConfig.luaBytecodeOptimized`).
/// * [EngineMode.ir] with [foldEnabled] — IR pipeline without SSA.
/// * [EngineMode.ast] — AST interpreter.
///
/// Top-level bytecode pipeline results share the live global environment so
/// stdlib and prior `-e` mutations remain visible.
///
/// [url] is the chunk source name or file path used for parser context.
/// [foldEnabled] defaults to [LuaLikeConfig.foldEnabled] and only affects
/// IR-mode folding; lua-bytecode always uses the full optimized pipeline.
///
/// Returns the public execution result (scalars unwrapped where applicable).
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

    // Engine routing:
    // * luaBytecode → always IR pipeline + SSA + mechanical lower (default).
    // * ir + fold → IR pipeline without SSA (IR VM cannot run post-SSA shapes).
    // * ast → direct AST interpreter.
    //
    // Pipeline path depends on register budget checks, local register
    // inference after serialize, and main lineDefined=0. See doc/decisions.md.
    final folding = foldEnabled ?? LuaLikeConfig().foldEnabled;
    final useBytecodePipeline = selectedMode == EngineMode.luaBytecode;
    final useIrPipeline = folding && selectedMode == EngineMode.ir;

    if (useBytecodePipeline || useIrPipeline) {
      final pipeline = CompilePipeline(
        config: useBytecodePipeline
            ? CompilePipelineConfig.luaBytecodeOptimized(
                dumpIr: LuaLikeConfig().dumpIr,
              )
            : CompilePipelineConfig(
                enableConstantFolding: true,
                enablePeephole: false,
                dumpIr: LuaLikeConfig().dumpIr,
                target: CompileBackend.lualikeIR,
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

      // Top-level scripts must share the live global environment (stdlib,
      // package.path from prior -e snippets). loadBytecode() isolates env for
      // load(); do not use it for entry chunks.
      if (runtime is LuaBytecodeRuntime && artifact is LuaBytecodeArtifact) {
        final env = runtime.getCurrentEnv();
        final closure = LuaBytecodeClosure.main(
          runtime: runtime,
          chunk: artifact.chunk,
          chunkName: url?.toString() ?? '=(pipeline)',
          environment: env,
        );
        final function = Value(closure)..interpreter = runtime;
        return _publicExecutionResult(
          await runtime.callFunction(function, const <Object?>[]),
        );
      }

      final chunk = await runtime.loadBytecode(
        artifact.serializedBytes,
        moduleName: url?.toString() ?? '=(pipeline)',
      );
      return _publicExecutionResult(
        await runtime.callFunction(chunk, const <Object?>[]),
      );
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
