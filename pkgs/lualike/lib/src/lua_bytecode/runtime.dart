import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/goto_validator.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_bytecode/vm_value_helpers.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_bytecode/serializer.dart';
import 'package:lualike/src/lua_bytecode/vm_support.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/runtime/chunk_loading_support.dart';
import 'package:lualike/src/runtime/compiled_artifact_support.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/semantic_checker.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/init.dart';
import 'package:lualike/src/stdlib/library.dart';
import 'package:lualike/src/stdlib/metatables.dart';
import 'package:lualike/src/value.dart';

/// Whether [bytes] begin with an official Lua binary chunk header.
///
/// Sniffs signature, version, format, and `luac` data, and rejects known
/// legacy AST/source payload markers. Used by the CLI and loaders so
/// precompiled files are recognized **by content**, not by file extension.
///
/// When this returns `true`, callers should load and run via the bytecode
/// VM only (see [tryLoadLuaBytecodeArtifact]) and must not recompile
/// through the IR/SSA pipeline.
bool looksLikeTrackedLuaBytecodeBytes(List<int> bytes) {
  if (bytes.length < 12) {
    return false;
  }

  const signature = LuaBytecodeChunkSentinels.signature;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) {
      return false;
    }
  }

  if (bytes[4] != LuaBytecodeChunkSentinels.officialVersion ||
      bytes[5] != LuaBytecodeChunkSentinels.officialFormat) {
    return false;
  }

  const luacData = LuaBytecodeChunkSentinels.luacData;
  for (var index = 0; index < luacData.length; index++) {
    if (bytes[index + 6] != luacData[index]) {
      return false;
    }
  }

  const officialHeaderSize = 40;
  if (bytes.length >= officialHeaderSize + 4) {
    final payloadOffset = officialHeaderSize;
    if (_matchesLegacyPayloadMarker(bytes, payloadOffset, <int>[
          0x41,
          0x53,
          0x54,
          0x3A,
        ]) ||
        _matchesLegacyPayloadMarker(bytes, payloadOffset, <int>[
          0x53,
          0x52,
          0x43,
          0x3A,
        ]) ||
        _matchesLegacyPayloadMarker(bytes, payloadOffset, <int>[
          0x53,
          0x52,
          0x43,
          0x4A,
          0x3A,
        ])) {
      return false;
    }
  }

  return true;
}

bool _matchesLegacyPayloadMarker(
  List<int> bytes,
  int offset,
  List<int> marker,
) {
  for (var index = 0; index < marker.length; index++) {
    if (bytes[offset + index] != marker[index]) {
      return false;
    }
  }
  return true;
}

/// Parses official Lua bytecode from [request] and returns a callable chunk.
///
/// Returns `null` when the payload is not a tracked binary chunk. On success,
/// the result is a [Value] wrapping a bytecode closure ready for
/// [LuaRuntime.callFunction] — no IR emission or SSA passes run.
///
/// Requires `b` in [LuaChunkLoadRequest.mode]. Format errors become a
/// failed [LuaChunkLoadResult].
LuaChunkLoadResult? tryLoadLuaBytecodeArtifact(
  LuaRuntime runtime,
  LuaChunkLoadRequest request,
) {
  final bytes = _sourceBytes(request.source);
  if (bytes == null || !looksLikeTrackedLuaBytecodeBytes(bytes)) {
    return null;
  }
  if (!request.mode.contains('b')) {
    return LuaChunkLoadResult.failure(
      "attempt to load a binary chunk (mode is '${request.mode}')",
    );
  }

  try {
    final chunk = const LuaBytecodeParser().parse(bytes);
    final function = LuaBytecodeClosure.main(
      runtime: runtime,
      chunk: chunk,
      chunkName: request.chunkName,
      environment: _createLoadEnvironment(
        runtime: runtime,
        currentEnv: runtime.getCurrentEnv(),
        providedEnv: request.environment,
      ),
    );
    final value = Value(function)..interpreter = runtime;
    return LuaChunkLoadResult.success(value);
  } on FormatException catch (error) {
    return LuaChunkLoadResult.failure(error.message);
  } catch (error) {
    return LuaChunkLoadResult.failure(error.toString());
  }
}

Environment _createLoadEnvironment({
  required LuaRuntime runtime,
  required Environment currentEnv,
  required Value? providedEnv,
}) {
  final loadEnv = Environment(
    parent: null,
    interpreter: runtime,
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
  return switch (rawLuaSlot(source)) {
    final LuaString luaString => luaString.bytes,
    final String text => text.codeUnits,
    final List<int> bytes => bytes,
    _ => null,
  };
}

String? _sourceText(Value source) {
  return switch (rawLuaSlot(source)) {
    final String text => text,
    final LuaString luaString => _decodeLuaSourceBytes(luaString.bytes),
    final List<int> bytes => _decodeLuaSourceBytes(bytes),
    _ => null,
  };
}

String _decodeLuaSourceBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

String _cleanEmitterFailure(Object error) {
  final message = error.toString();
  return message.startsWith('Unsupported operation: ')
      ? message.substring('Unsupported operation: '.length)
      : message;
}

LuaChunkLoadResult loadLuaBytecodeSourceChunk(
  LuaRuntime runtime,
  LuaChunkLoadRequest request,
) {
  final source = _sourceText(request.source);
  if (source == null) {
    return const LuaChunkLoadResult.failure('chunk source must be a string');
  }

  try {
    final ast = parse(source, url: request.chunkName);
    final semanticError = validateProgramSemantics(ast);
    if (semanticError != null) {
      return LuaChunkLoadResult.failure(
        _adjustLoadValidationError(source, semanticError),
      );
    }
    if (source.contains('goto') || source.contains('::')) {
      final gotoError = GotoLabelValidator().checkGotoLabelViolations(ast);
      if (gotoError != null) {
        return LuaChunkLoadResult.failure(gotoError);
      }
    }

    final artifact = const LuaBytecodeEmitter().compileProgram(
      ast,
      chunkName: request.chunkName,
      sourceName: request.chunkName,
    );
    final closure = LuaBytecodeClosure.main(
      runtime: runtime,
      chunk: artifact.chunk,
      chunkName: request.chunkName,
      environment: _createLoadEnvironment(
        runtime: runtime,
        currentEnv: runtime.getCurrentEnv(),
        providedEnv: request.environment,
      ),
    );
    final value = Value(closure)..interpreter = runtime;
    return LuaChunkLoadResult.success(value);
  } on FormatException catch (error) {
    return LuaChunkLoadResult.failure(error.message);
  } on RangeError {
    return const LuaChunkLoadResult.failure('bytecode overflow');
  } on UnsupportedError catch (error) {
    return LuaChunkLoadResult.failure(_cleanEmitterFailure(error));
  } catch (error) {
    return LuaChunkLoadResult.failure(error.toString());
  }
}

/// Runtime wrapper that executes source by emitting real `lua_bytecode`
/// chunks and running them through the bytecode VM.
class LuaBytecodeRuntime implements LuaRuntime {
  LuaBytecodeRuntime({FileManager? fileManager})
    : _interpreter = Interpreter(fileManager: fileManager) {
    _interpreter.gc.bindRuntime(this);
    _libraryRegistry = LibraryRegistry(this);
    final runtimeEnv = Environment(interpreter: this);
    _globalEnvironment = runtimeEnv;
    _interpreter.setCurrentEnv(runtimeEnv);
    gc.register(runtimeEnv);
    initializeStandardLibrary(vm: this);
    _ensureEnvironmentBinding(runtimeEnv);
    _interpreter.fileManager.setInterpreter(this);
    _bytecodeVm = LuaBytecodeVm(this);
  }

  final Interpreter _interpreter;
  late final LuaBytecodeVm _bytecodeVm;
  late final Environment _globalEnvironment;
  late final LibraryRegistry _libraryRegistry;
  final List<LuaBytecodeGCRootProvider> _activeFrameRoots =
      <LuaBytecodeGCRootProvider>[];
  final Map<LuaBytecodeGCRootProvider, Iterable<Object?> Function()>
  _interpreterRootProviders =
      <LuaBytecodeGCRootProvider, Iterable<Object?> Function()>{};

  @override
  Value get debugRegistry => _interpreter.debugRegistry;

  Interpreter get debugInterpreter => _interpreter;

  Value? get debugHookFunction => _interpreter.debugHookFunction;
  set debugHookFunction(Value? value) {
    _interpreter.debugHookFunction = value;
  }

  String get debugHookMask => _interpreter.debugHookMask;
  set debugHookMask(String value) {
    _interpreter.debugHookMask = value;
  }

  int get debugHookCount => _interpreter.debugHookCount;
  set debugHookCount(int value) {
    _interpreter.debugHookCount = value;
  }

  int get debugHookCountRemaining => _interpreter.debugHookCountRemaining;
  set debugHookCountRemaining(int value) {
    _interpreter.debugHookCountRemaining = value;
  }

  void resetDebugHookCounter() {
    _interpreter.resetDebugHookCounter();
  }

  void rememberDebugHookLine(int line, {String? source}) {
    _interpreter.rememberDebugHookLine(line, source: source);
  }

  Environment get _globals => _globalEnvironment;

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
  void setCurrentEnv(Environment env) {
    _ensureEnvironmentBinding(env);
    _interpreter.setCurrentEnv(env);
  }

  @override
  Future<Object?> runAst(List<AstNode> program) async {
    final chunkName = currentScriptPath ?? '=(lua_bytecode_source)';
    final ast = Program(program);
    final semanticError = validateProgramSemantics(ast);
    if (semanticError != null) {
      throw Exception(semanticError);
    }
    // Prefer IR pipeline (same as executeCode / --lua-bytecode). Keep the
    // direct emitter as a private escape hatch only if the pipeline throws
    // IrRegisterBudgetExceeded during development of new SSA features.
    final pipeline = CompilePipeline(
      config: CompilePipelineConfig.luaBytecodeOptimized(),
    );
    final artifact = pipeline.compile(ast) as LuaBytecodeArtifact;
    final env = getCurrentEnv();
    _ensureEnvironmentBinding(env);
    final closure = LuaBytecodeClosure.main(
      runtime: this,
      chunk: artifact.chunk,
      chunkName: chunkName,
      environment: env,
    );
    return closure.call(_currentChunkArgs(env));
  }

  @override
  Future<Object?> evaluateAst(AstNode node) {
    final returnStatement = node is ReturnStatement
        ? node
        : ReturnStatement([node]);
    return runAst([returnStatement]);
  }

  /// Fast path for calling a bytecode closure with exactly two Value
  /// arguments. `table.sort` hits this in a tight inner loop, so we avoid the
  /// generic `List<Object?>`/`Value` rebuild and keep the comparator hot path
  /// as small as possible.
  Future<Object?> callBytecodeClosureDirect(
    LuaBytecodeClosure closure,
    Value arg0,
    Value arg1, {
    String? debugName,
  }) async {
    final results = await _bytecodeVm.invoke(
      closure,
      <Object?>[arg0, arg1],
      functionValue: closure.callableValue,
      callName: debugName ?? closure.chunkName,
      callNameWhat: '',
      isEntryFrame: true,
    );
    if (results.isEmpty) return null;
    if (results.length == 1) return results.single;
    return LuaResults(results);
  }

  @override
  Future<Object?> callFunction(
    Value function,
    List<Object?> args, {
    String? debugName,
    String debugNameWhat = '',
  }) async {
    final prepared = _prepareCallable(function, args);
    final callee = prepared.callee;
    args = prepared.args;
    _ensureValueInterpreter(callee);
    _attachInterpreterToArgs(args);
    if (rawLuaSlot(callee) case final LuaBytecodeClosure closure) {
      final results = await _bytecodeVm.invoke(
        closure,
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
      return LuaResults(results);
    }
    final topFrame = callStack.top;
    final alreadyFramed = identical(topFrame?.callable, callee);
    if (!alreadyFramed) {
      callStack.push(
        debugName ?? callee.functionName ?? 'function',
        env: getCurrentEnv(),
        debugName: debugName ?? callee.functionName,
        debugNameWhat: debugNameWhat,
        callable: callee,
      );
    }
    try {
      return await callee.call(args);
    } finally {
      if (!alreadyFramed) {
        callStack.pop();
      }
    }
  }

  @override
  final Map<String, Value> moduleBytecodeCache = <String, Value>{};

  @override
  Future<Value> loadBytecode(
    List<int> bytes, {
    required String moduleName,
  }) async {
    final result = await loadChunk(
      LuaChunkLoadRequest(
        source: Value.primitive(bytes),
        chunkName: moduleName,
        mode: 'b',
      ),
    );
    if (!result.isSuccess) {
      throw Exception(
        'Failed to load bytecode module \'$moduleName\': '
        '${result.errorMessage}',
      );
    }
    return result.chunk!;
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
    final sourceBytes = compiledArtifactSourceBytes(normalizedRequest.source);
    if (sourceBytes != null &&
        sourceBytes.isNotEmpty &&
        !looksLikeTrackedLuaBytecodeBytes(sourceBytes) &&
        sourceBytes.first == 0x1B) {
      return loadChunkWithLegacyAstSupport(this, normalizedRequest);
    }

    final luaBytecodeResult = tryLoadLuaBytecodeArtifact(
      this,
      normalizedRequest,
    );
    if (luaBytecodeResult != null) {
      return luaBytecodeResult;
    }

    if (!normalizedRequest.mode.contains('t')) {
      return LuaChunkLoadResult.failure(
        "attempt to load a text chunk (mode is '${normalizedRequest.mode}')",
      );
    }

    return _loadSourceChunk(normalizedRequest);
  }

  @override
  Object? dumpFunction(Value function, {bool stripDebugInfo = false}) {
    _ensureValueInterpreter(function);
    if (rawLuaSlot(function) case final LuaBytecodeClosure closure) {
      final chunk = LuaBytecodeBinaryChunk(
        header: const LuaBytecodeChunkHeader.official(),
        rootUpvalueCount: closure.prototype.upvalues.length,
        mainPrototype: stripDebugInfo
            ? _stripPrototypeDebugInfo(closure.prototype)
            : closure.prototype,
      );
      return LuaString.fromBytes(
        Uint8List.fromList(serializeLuaBytecodeChunk(chunk)),
      );
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
  Value constantRawStringValue(String value) {
    return _interpreter.constantStringValue(value.codeUnits)
      ..interpreter = this;
  }

  @override
  Value constantDartStringValue(String value) {
    return _interpreter.constantDartStringValue(value)..interpreter = this;
  }

  @override
  Value constantPrimitiveValue(Object? raw) {
    final value = _interpreter.constantPrimitiveValue(raw);
    if (_defaultPrimitiveMetatableActive(raw)) {
      _ensureValueInterpreter(value);
    }
    return value;
  }

  @override
  Value wrapRuntimeValue(Object? raw) => valueFromLuaSlot(this, raw);

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
  bool get shouldAbandonIncrementalCycleBeforeManualCollect => true;

  @override
  FileManager get fileManager => _interpreter.fileManager;

  @override
  Set<Value> get openFiles => _interpreter.openFiles;

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

  void pushActiveFrameRoots(LuaBytecodeGCRootProvider provider) {
    _activeFrameRoots.add(provider);
    Iterable<GCObject> rootProvider() => provider.gcReferences();
    _interpreterRootProviders[provider] = rootProvider;
    _interpreter.pushExternalGcRoots(rootProvider);
  }

  void popActiveFrameRoots(LuaBytecodeGCRootProvider provider) {
    _activeFrameRoots.remove(provider);
    if (_interpreterRootProviders.remove(provider) case final rootProvider?) {
      _interpreter.popExternalGcRoots(rootProvider);
    }
  }

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
    if (gc.isStopped ||
        !gc.autoTriggerEnabled ||
        gc.isManualCollectRunning ||
        gc.isFinalizerActive) {
      return;
    }
    final threshold = gc.autoTriggerDebtThreshold;
    final debt = gc.allocationDebt;
    if (debt < threshold) {
      return;
    }
    gc.runPendingAutoTrigger();
  }

  @override
  bool shouldRunLoopGcAtSafePoint(int loopCounter) {
    if (gc.isStopped || !gc.autoTriggerEnabled) {
      return false;
    }
    if (gc.isManualCollectRunning || gc.isFinalizerActive) {
      return false;
    }
    if (gc.needsAsyncFinalizerDrain) {
      return true;
    }
    final threshold = gc.autoTriggerDebtThreshold;
    final debt = gc.allocationDebt;
    if (debt >= threshold) {
      return true;
    }
    return gc.shouldForceAsyncLoopRescue(loopCounter, debt, threshold) ||
        gc.shouldAdvanceIncrementalLoopCycle(loopCounter);
  }

  @override
  Future<void> runLoopGcAtSafePoint(int loopCounter) async {
    if (gc.isStopped || !gc.autoTriggerEnabled) {
      return;
    }
    if (gc.isManualCollectRunning || gc.isFinalizerActive) {
      return;
    }
    if (gc.needsAsyncFinalizerDrain) {
      await _finishBytecodeFinalizerCycle();
      return;
    }
    final debt = gc.allocationDebt;
    if (debt > 0) {
      runAutoGcAtSafePoint();
      if (gc.needsAsyncFinalizerDrain) {
        await _finishBytecodeFinalizerCycle();
        return;
      }
    }
    final threshold = gc.autoTriggerDebtThreshold;
    if (gc.shouldForceAsyncLoopRescue(loopCounter, debt, threshold)) {
      await _finishBytecodeFinalizerCycle();
      return;
    }
    if (!gc.shouldAdvanceIncrementalLoopCycle(loopCounter)) {
      return;
    }
    gc.performIncrementalStep(gc.loopIncrementalGcBudget());
    if (gc.needsAsyncFinalizerDrain) {
      await _finishBytecodeFinalizerCycle();
      return;
    }
    if (gc.hasPendingAsyncFinalizers) {
      await gc.drainPendingAsyncFinalizers();
    }
  }

  /// Finishes bytecode-visible finalization with the collector's async path.
  ///
  /// A full major collection is heavier than another incremental slice, but
  /// this branch only runs once a cycle already has pending finalizers. At
  /// that point correctness matters more than throughput: the async major
  /// collector awaits bytecode `__gc` bodies before the object is freed, which
  /// preserves Lua's `debug.getinfo(1)` / traceback semantics inside finalizers.
  Future<void> _finishBytecodeFinalizerCycle() async {
    await gc.majorCollection(getRoots());
  }

  ({Value callee, List<Object?> args}) _prepareCallable(
    Value original,
    List<Object?> args,
  ) {
    var callee = original;
    var normalizedArgs = args
        .map(
          (arg) => arg is List
              ? valueFromLuaSlot(this, Value.listToLuaTable(arg))
              : arg,
        )
        .toList(growable: false);
    var extraArgs = 0;

    while (true) {
      final raw = rawLuaSlot(callee);
      if (raw is String) {
        final lookup = globals.get(raw);
        if (lookup != null) {
          callee = valueFromLuaSlot(this, lookup);
          continue;
        }
      }

      if (raw is Function ||
          raw is BuiltinFunction ||
          raw is FunctionDef ||
          raw is FunctionLiteral ||
          raw is LuaCallableArtifact ||
          raw is FunctionBody ||
          raw is LuaBytecodeClosure) {
        return (callee: callee, args: normalizedArgs);
      }

      if (!callee.hasMetamethod('__call')) {
        return (callee: callee, args: normalizedArgs);
      }

      final callMeta = callee.getMetamethod('__call');
      if (callMeta == null) {
        return (callee: callee, args: normalizedArgs);
      }
      if (extraArgs >= 15) {
        throw LuaError("'__call' chain too long");
      }

      final originalCallee = callee;
      callee = valueFromLuaSlot(this, callMeta);
      normalizedArgs = <Object?>[originalCallee, ...normalizedArgs];
      extraArgs += 1;
    }
  }

  void _ensureValueInterpreter(Value value) {
    if (!identical(value.interpreter, this)) {
      value.interpreter = this;
    }
  }

  bool _defaultPrimitiveMetatableActive(Object? raw) {
    final type = switch (raw) {
      null => 'nil',
      bool() => 'boolean',
      _ => 'number',
    };
    return MetaTable().isDefaultMetatableActive(type);
  }

  List<Object?> _currentChunkArgs(Environment env) {
    final varargs = env.get('...');
    final resultValues = luaResultValues(varargs);
    if (resultValues != null) {
      return List<Object?>.from(resultValues);
    }
    if (varargs is Value) {
      if (rawLuaSlot(varargs) == null) {
        return const <Object?>[];
      }
      return <Object?>[varargs];
    }
    return switch (varargs) {
      null => const <Object?>[],
      _ => <Object?>[varargs],
    };
  }

  void _attachInterpreterToArgs(List<Object?> args) {
    for (var index = 0; index < args.length; index++) {
      final candidate = args[index];
      if (candidate is Value && !identical(candidate.interpreter, this)) {
        candidate.interpreter = this;
      }
    }
  }

  LuaChunkLoadResult _loadSourceChunk(LuaChunkLoadRequest request) {
    return loadLuaBytecodeSourceChunk(this, request);
  }
}

LuaBytecodePrototype _stripPrototypeDebugInfo(LuaBytecodePrototype prototype) {
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
      prototype.prototypes.map(_stripPrototypeDebugInfo),
    ),
    source: '=?',
    lineInfo: const <int>[],
    absoluteLineInfo: const <LuaBytecodeAbsLineInfo>[],
    localVariables: const <LuaBytecodeLocalVariableDebugInfo>[],
    upvalueNames: List<String?>.filled(prototype.upvalues.length, null),
  );
}

String _adjustLoadValidationError(String source, String error) {
  if (!source.startsWith('\n')) {
    return error;
  }
  return error.replaceAllMapped(RegExp(r':(\d+):'), (match) {
    final lineNum = int.parse(match.group(1)!);
    final adjustedLine = lineNum > 1 ? lineNum - 1 : lineNum;
    return ':$adjustedLine:';
  });
}
