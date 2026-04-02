import 'package:lualike/src/ast.dart';
import 'package:lualike/src/ir/bytecode_lowering.dart';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/serialization.dart';
import 'package:lualike/src/ir/textual_formatter.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/goto_validator.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/serializer.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/runtime/compiled_artifact_support.dart';
import 'package:lualike/src/runtime/chunk_loading_support.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/semantic_checker.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/init.dart';
import 'package:lualike/src/stdlib/library.dart';
import 'package:lualike/src/value.dart';

/// Runtime wrapper that executes code via the lualike IR VM while satisfying
/// the [LuaRuntime] contract expected by higher-level tooling.
class LualikeIrRuntime implements LuaRuntime {
  LualikeIrRuntime({FileManager? fileManager})
    : _interpreter = Interpreter(fileManager: fileManager) {
    _libraryRegistry = LibraryRegistry(this);
    final runtimeEnv = Environment(interpreter: this);
    _interpreter.setCurrentEnv(runtimeEnv);
    gc.register(runtimeEnv);
    initializeStandardLibrary(vm: this);
    _ensureEnvironmentBinding(runtimeEnv);
    _interpreter.fileManager.setInterpreter(this);
  }

  final Interpreter _interpreter;
  late final LibraryRegistry _libraryRegistry;

  Interpreter get debugInterpreter => _interpreter;

  Environment get _globals => _interpreter.globals;

  @override
  Environment get globals {
    final env = _globals;
    _ensureEnvironmentBinding(env);
    return env;
  }

  @override
  Environment getCurrentEnv() {
    final env = _interpreter.getCurrentEnv();
    _ensureEnvironmentBinding(env);
    return env;
  }

  @override
  Value get debugRegistry => _interpreter.debugRegistry;

  @override
  void setCurrentEnv(Environment env) {
    _ensureEnvironmentBinding(env);
    _interpreter.setCurrentEnv(env);
  }

  @override
  Future<Object?> runAst(List<AstNode> program) async {
    final ast = Program(program);
    final semanticError = validateProgramSemantics(ast);
    if (semanticError != null) {
      throw Exception(semanticError);
    }
    final chunk = LualikeIrCompiler().compile(ast);
    _dumpDisassemblyIfEnabled(chunk);
    if (LuaLikeConfig().dumpIr) {
      return null;
    }
    return _executeChunk(chunk);
  }

  @override
  Future<Object?> evaluateAst(AstNode node) {
    final returnStatement = node is ReturnStatement
        ? node
        : ReturnStatement([node]);
    return runAst([returnStatement]);
  }

  @override
  Future<Object?> callFunction(
    Value function,
    List<Object?> args, {
    String? debugName,
    String debugNameWhat = '',
  }) async {
    final callee = _resolveCallable(function);
    _ensureValueInterpreter(callee);
    _attachInterpreterToArgs(args);
    final raw = callee.raw;
    if (raw is LuaBytecodeClosure) {
      final vm = LuaBytecodeVm(this);
      final results = await vm.invoke(
        raw,
        args,
        functionValue: callee,
        callName: debugName ?? callee.functionName,
        callNameWhat: debugNameWhat,
        isEntryFrame: true,
      );
      if (results.isEmpty) {
        return null;
      }
      if (results.length == 1) {
        return results.single;
      }
      final packed = Value.multi(results);
      packed.interpreter ??= this;
      return packed;
    }
    return callee.call(args);
  }

  @override
  Future<LuaChunkLoadResult> loadChunk(LuaChunkLoadRequest request) async {
    if (request.environment != null) {
      _ensureValueInterpreter(request.environment!);
    }
    final normalized = await normalizeChunkLoadRequest(this, request);
    if (normalized.failure case final failure?) {
      return failure;
    }

    final normalizedRequest = normalized.request;
    final textSource = switch (normalizedRequest.source.raw) {
      final String text => text,
      final LuaString luaString => luaString.toLatin1String(),
      _ => null,
    };
    if (textSource != null &&
        (textSource.contains('goto') || textSource.contains('::'))) {
      try {
        final ast = parse(textSource, url: normalizedRequest.chunkName);
        final gotoError = GotoLabelValidator().checkGotoLabelViolations(ast);
        if (gotoError != null) {
          return LuaChunkLoadResult.failure(gotoError);
        }
      } on Exception catch (error) {
        return LuaChunkLoadResult.failure(error.toString());
      }
    }

    final luaBytecodeResult = tryLoadLuaBytecodeArtifact(
      this,
      normalizedRequest,
    );
    if (luaBytecodeResult != null) {
      return luaBytecodeResult;
    }

    final irResult = _loadIrArtifact(normalizedRequest);
    if (irResult != null) {
      return irResult;
    }

    return loadChunkWithLegacyAstSupport(this, normalizedRequest);
  }

  @override
  Object? dumpFunction(Value function, {bool stripDebugInfo = false}) {
    _ensureValueInterpreter(function);
    switch (function.raw) {
      case LuaBytecodeClosure(:final prototype):
        final chunk = LuaBytecodeBinaryChunk(
          header: const LuaBytecodeChunkHeader.official(),
          rootUpvalueCount: prototype.upvalues.length,
          mainPrototype: stripDebugInfo
              ? _stripBytecodePrototypeDebugInfo(prototype)
              : prototype,
        );
        return LuaString.fromBytes(serializeLuaBytecodeChunk(chunk));
    }
    return dumpFunctionWithLegacyAstTransport(
      function,
      stripDebugInfo: stripDebugInfo,
    );
  }

  @override
  LuaFunctionDebugInfo? debugInfoForFunction(Value function) {
    _ensureValueInterpreter(function);
    return defaultDebugInfoForFunction(this, function);
  }

  @override
  Value constantStringValue(List<int> bytes) {
    return _interpreter.constantStringValue(bytes)..interpreter = this;
  }

  @override
  Value constantPrimitiveValue(Object? raw) {
    return _interpreter.constantPrimitiveValue(raw)..interpreter = this;
  }

  @override
  CallStack get callStack => _interpreter.callStack;

  @override
  Stack get evalStack => _interpreter.evalStack;

  @override
  String? get currentScriptPath => _interpreter.currentScriptPath;

  @override
  set currentScriptPath(String? value) {
    _interpreter.currentScriptPath = value;
  }

  @override
  Coroutine? getCurrentCoroutine() => _interpreter.getCurrentCoroutine();

  @override
  void setCurrentCoroutine(Coroutine? coroutine) {
    _interpreter.setCurrentCoroutine(coroutine);
  }

  @override
  Coroutine getMainThread() => _interpreter.getMainThread();

  @override
  void registerCoroutine(Coroutine coroutine) {
    _interpreter.registerCoroutine(coroutine);
  }

  @override
  void unregisterCoroutine(Coroutine coroutine) {
    _interpreter.unregisterCoroutine(coroutine);
  }

  @override
  void enterProtectedCall() => _interpreter.enterProtectedCall();

  @override
  void exitProtectedCall() => _interpreter.exitProtectedCall();

  @override
  bool get isInProtectedCall => _interpreter.isInProtectedCall;

  @override
  bool get isYieldable => _interpreter.isYieldable;

  @override
  set isYieldable(bool value) {
    _interpreter.isYieldable = value;
  }

  @override
  GenerationalGCManager get gc => _interpreter.gc;

  @override
  List<Object?> getRoots() => _interpreter.getRoots();

  @override
  bool get shouldAbandonIncrementalCycleBeforeManualCollect => false;

  @override
  void pushExternalGcRoots(Iterable<Object?> Function() provider) {
    _interpreter.pushExternalGcRoots(provider);
  }

  @override
  void popExternalGcRoots(Iterable<Object?> Function() provider) {
    _interpreter.popExternalGcRoots(provider);
  }

  @override
  void runAutoGcAtSafePoint() {
    _interpreter.runAutoGcAtSafePoint();
  }

  @override
  bool shouldRunLoopGcAtSafePoint(int loopCounter) {
    return _interpreter.shouldRunLoopGcAtSafePoint(loopCounter);
  }

  @override
  Future<void> runLoopGcAtSafePoint(int loopCounter) {
    return _interpreter.runLoopGcAtSafePoint(loopCounter);
  }

  @override
  FileManager get fileManager => _interpreter.fileManager;

  @override
  LibraryRegistry get libraryRegistry => _libraryRegistry;

  @override
  void reportError(
    String message, {
    StackTrace? trace,
    Object? error,
    AstNode? node,
  }) {
    _interpreter.reportError(message, trace: trace, error: error, node: node);
  }

  void _ensureEnvironmentBinding(Environment env) {
    final root = env.root;
    if (!identical(root.interpreter, this)) {
      root.interpreter = this;
    }
  }

  Value _resolveCallable(Value original) {
    var callee = original;
    final raw = callee.raw;
    if (raw is String) {
      final lookup = globals.get(raw);
      if (lookup != null) {
        callee = lookup is Value ? lookup : Value(lookup);
      }
    }
    return callee;
  }

  void _ensureValueInterpreter(Value value) {
    if (!identical(value.interpreter, this)) {
      value.interpreter = this;
    }
  }

  void _attachInterpreterToArgs(List<Object?> args) {
    for (var i = 0; i < args.length; i++) {
      final candidate = args[i];
      if (candidate is Value && !identical(candidate.interpreter, this)) {
        candidate.interpreter = this;
      }
    }
  }

  Future<Object?> _executeChunk(LualikeIrChunk chunk) {
    final env = _interpreter.getCurrentEnv();
    _ensureEnvironmentBinding(env);
    final lowered = lowerIrChunkToLuaBytecodeChunk(
      chunk,
      chunkName: currentScriptPath ?? '=(lualike_ir)',
    );
    final closure = LuaBytecodeClosure.main(
      runtime: this,
      chunk: lowered,
      chunkName: currentScriptPath ?? '=(lualike_ir)',
      environment: env,
    );
    return closure.call(const <Object?>[]);
  }

  void _dumpDisassemblyIfEnabled(LualikeIrChunk chunk) {
    if (!LuaLikeConfig().dumpIr) {
      return;
    }

    final formatted = formatLualikeIrChunk(chunk);
    if (formatted.isEmpty) {
      return;
    }

    // Use print so output is visible even when logging is disabled.
    print('--- Lualike IR ---');
    print(formatted);
    print('--- End Lualike IR ---');
  }

  LuaChunkLoadResult? _loadIrArtifact(LuaChunkLoadRequest request) {
    final bytes = _sourceBytes(request.source);
    if (bytes == null || !looksLikeLualikeIrBytes(bytes)) {
      return null;
    }
    if (!request.mode.contains('b')) {
      return LuaChunkLoadResult.failure(
        "attempt to load a binary chunk (mode is '${request.mode}')",
      );
    }

    try {
      final chunk = deserializeLualikeIrBytes(bytes);
      final loadEnvironment = _createLoadEnvironment(
        currentEnv: getCurrentEnv(),
        providedEnv: request.environment,
      );
      final lowered = lowerIrChunkToLuaBytecodeChunk(
        chunk,
        chunkName: request.chunkName,
      );
      final closure = LuaBytecodeClosure.main(
        runtime: this,
        chunk: lowered,
        chunkName: request.chunkName,
        environment: loadEnvironment,
      );
      final value = Value(closure)..interpreter = this;
      return LuaChunkLoadResult.success(value);
    } on FormatException catch (error) {
      return LuaChunkLoadResult.failure(error.message);
    }
  }

  Environment _createLoadEnvironment({
    required Environment currentEnv,
    required Value? providedEnv,
  }) {
    final loadEnv = Environment(
      parent: null,
      interpreter: this,
      isLoadIsolated: true,
    );
    final globalValue = currentEnv.get('_G') ?? currentEnv.root.get('_G');
    if (providedEnv != null) {
      loadEnv.declare('_ENV', providedEnv);
      if (globalValue != null) {
        loadEnv.declare('_G', globalValue);
      }
      return loadEnv;
    }

    if (globalValue != null) {
      loadEnv
        ..declare('_ENV', globalValue)
        ..declare('_G', globalValue);
    }
    return loadEnv;
  }

  List<int>? _sourceBytes(Value source) {
    return switch (source.raw) {
      final LuaString luaString => luaString.bytes,
      final String text => text.codeUnits,
      final List<int> bytes => bytes,
      _ => null,
    };
  }
}

LuaBytecodePrototype _stripBytecodePrototypeDebugInfo(
  LuaBytecodePrototype prototype,
) {
  return LuaBytecodePrototype(
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    parameterCount: prototype.parameterCount,
    flags: prototype.flags,
    maxStackSize: prototype.maxStackSize,
    code: prototype.code,
    constants: prototype.constants,
    upvalues: prototype.upvalues,
    prototypes: List<LuaBytecodePrototype>.unmodifiable(
      prototype.prototypes.map(_stripBytecodePrototypeDebugInfo),
    ),
    source: prototype.source,
    lineInfo: const <int>[],
    absoluteLineInfo: const <LuaBytecodeAbsLineInfo>[],
    localVariables: const <LuaBytecodeLocalVariableDebugInfo>[],
    upvalueNames: const <String?>[],
  );
}
