import 'dart:typed_data';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/goto_validator.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_bytecode/serializer.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/runtime/chunk_loading_support.dart';
import 'package:lualike/src/runtime/compiled_artifact_support.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/semantic_checker.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/init.dart';
import 'package:lualike/src/stdlib/library.dart';
import 'package:lualike/src/value.dart';

final RegExp _semanticLikeTokenPattern = RegExp(
  r'<[A-Za-z_][A-Za-z0-9_]*>|(^|[^A-Za-z0-9_])global\b|\bfor\b|\breturn\b|\.\.\.\s*[A-Za-z_][A-Za-z0-9_]*',
);

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
  return switch (source.raw) {
    final LuaString luaString => luaString.bytes,
    final String text => text.codeUnits,
    final List<int> bytes => bytes,
    _ => null,
  };
}

String? _sourceText(Value source) {
  return switch (source.raw) {
    final String text => text,
    final LuaString luaString => luaString.toString(),
    _ => null,
  };
}

String _cleanEmitterFailure(Object error) {
  final message = error.toString();
  return message.startsWith('Unsupported operation: ')
      ? message.substring('Unsupported operation: '.length)
      : message;
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
  }

  final Interpreter _interpreter;
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
    final chunkName = currentScriptPath ?? '=(lua_bytecode source)';
    final ast = Program(program);
    final semanticError = validateProgramSemantics(ast);
    if (semanticError != null) {
      throw Exception(semanticError);
    }
    final artifact = const LuaBytecodeEmitter().compileProgram(
      ast,
      chunkName: chunkName,
    );
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
    if (callee.raw case final LuaBytecodeClosure closure) {
      final vm = LuaBytecodeVm(this);
      final results = await vm.invoke(
        closure,
        args,
        callName: callee.functionName,
        isEntryFrame: true,
      );
      if (results.isEmpty) {
        return Value(null);
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
    if (function.raw case final LuaBytecodeClosure closure) {
      final chunk = LuaBytecodeBinaryChunk(
        header: const LuaBytecodeChunkHeader.official(),
        rootUpvalueCount: closure.prototype.upvalues.length,
        mainPrototype: closure.prototype,
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
    final key = bytes.join(',');
    final cached = _interpreter.literalValueCache[key];
    if (cached != null) {
      _ensureValueInterpreter(cached);
      return cached;
    }

    final luaString = _interpreter.literalStringInternPool[key] ??=
        LuaString.fromBytes(bytes);
    final value = Value(luaString)..interpreter = this;
    _interpreter.literalValueCache[key] = value;
    return value;
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
  List<Object?> getRoots() => <Object?>[
    ..._interpreter.getRoots(),
    for (final provider in _activeFrameRoots) ...provider.gcReferences(),
  ];

  @override
  bool get shouldAbandonIncrementalCycleBeforeManualCollect => true;

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

  void pushExternalGcRoots(Iterable<Object?> Function() provider) {
    _interpreter.pushExternalGcRoots(provider);
  }

  void popExternalGcRoots(Iterable<Object?> Function() provider) {
    _interpreter.popExternalGcRoots(provider);
  }

  void runAutoGcAtSafePoint() {
    if (gc.isStopped || !gc.autoTriggerEnabled) {
      return;
    }
    final threshold = gc.autoTriggerDebtThreshold;
    final debt = gc.allocationDebt;
    if (debt < threshold) {
      return;
    }
    gc.runPendingAutoTrigger();
  }

  Future<void> runLoopGcAtSafePoint(int loopCounter) async {
    if (gc.isStopped || !gc.autoTriggerEnabled) {
      return;
    }
    final debt = gc.allocationDebt;
    if (debt <= 0) {
      return;
    }
    runAutoGcAtSafePoint();
  }

  ({Value callee, List<Object?> args}) _prepareCallable(
    Value original,
    List<Object?> args,
  ) {
    var callee = original;
    var normalizedArgs = List<Object?>.from(args, growable: false);
    var extraArgs = 0;

    while (true) {
      final raw = callee.raw;
      if (raw is String) {
        final lookup = globals.get(raw);
        if (lookup != null) {
          callee = lookup is Value ? lookup : Value(lookup);
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
      callee = callMeta is Value ? callMeta : Value(callMeta);
      normalizedArgs = <Object?>[originalCallee, ...normalizedArgs];
      extraArgs += 1;
    }
  }

  void _ensureValueInterpreter(Value value) {
    if (!identical(value.interpreter, this)) {
      value.interpreter = this;
    }
  }

  List<Object?> _currentChunkArgs(Environment env) {
    final varargs = env.get('...');
    return switch (varargs) {
      Value(isMulti: true, raw: final List values) => List<Object?>.from(
        values,
      ),
      Value(raw: null) || null => const <Object?>[],
      final Value value => <Object?>[value],
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
    final source = _sourceText(request.source);
    if (source == null) {
      return const LuaChunkLoadResult.failure('chunk source must be a string');
    }

    try {
      final ast = parse(source, url: request.chunkName);
      if (_semanticLikeTokenPattern.hasMatch(source)) {
        final semanticError = validateProgramSemantics(ast);
        if (semanticError != null) {
          return LuaChunkLoadResult.failure(
            _adjustLoadValidationError(source, semanticError),
          );
        }
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
        runtime: this,
        chunk: artifact.chunk,
        chunkName: request.chunkName,
        environment: _createLoadEnvironment(
          runtime: this,
          currentEnv: getCurrentEnv(),
          providedEnv: request.environment,
        ),
      );
      final value = Value(closure)..interpreter = this;
      return LuaChunkLoadResult.success(value);
    } on UnsupportedError catch (error) {
      return LuaChunkLoadResult.failure(_cleanEmitterFailure(error));
    } catch (error) {
      return LuaChunkLoadResult.failure(error.toString());
    }
  }
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
