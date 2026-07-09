import 'dart:async' show FutureOr;
import 'dart:collection';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/exceptions.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/lua_bytecode/opcode_analysis.dart';
import 'package:lualike/src/lua_bytecode/instruction_analysis.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/vararg_table.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/parse.dart' show looksLikeLuaFilePath, luaChunkId;
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'package:lualike/src/value.dart';
import 'package:path/path.dart' as path;

final bool _debugFileOps =
    platform.getEnvironmentVariable('LUALIKE_DEBUG_FILE_OPS') == '1';
final bool _profileBytecode =
    platform.getEnvironmentVariable('LUALIKE_PROFILE_BYTECODE') == '1';

final RegExp _bytecodeFormattedLuaErrorPattern = RegExp(
  r'^(?:\[[^\n]+\]|[^:\n]+):(?:\d+|\?): ',
);

final Expando<_LuaBytecodeFrame> _callFrameBytecodeFrames =
    Expando<_LuaBytecodeFrame>();
final Expando<bool> _closeSignalYieldableStates = Expando<bool>();
final class _LuaBytecodeProfileEntry {
  int count = 0;
  int micros = 0;
}

final class _LuaBytecodeProfile {
  _LuaBytecodeProfile({required this.label});

  final String label;
  final Stopwatch wall = Stopwatch()..start();
  int totalInstructions = 0;
  final Map<String, _LuaBytecodeProfileEntry> entries =
      <String, _LuaBytecodeProfileEntry>{};
  final Map<String, int> callTargets = <String, int>{};

  void record(String opcodeName, int micros) {
    totalInstructions++;
    final entry = entries.putIfAbsent(opcodeName, _LuaBytecodeProfileEntry.new);
    entry.count++;
    entry.micros += micros;
  }

  void recordCallTarget(String label) {
    callTargets.update(label, (count) => count + 1, ifAbsent: () => 1);
  }

  void printSummary() {
    wall.stop();
    final sorted = entries.entries.toList()
      ..sort((a, b) => b.value.micros.compareTo(a.value.micros));
    final top = sorted.take(12);
    final totalMicros = entries.values.fold<int>(
      0,
      (sum, entry) => sum + entry.micros,
    );
    print(
      '[bc-profile] label=$label wall_ms=${wall.elapsedMilliseconds} '
      'instructions=$totalInstructions',
    );
    for (final item in top) {
      final entry = item.value;
      final pct = totalMicros == 0 ? 0.0 : entry.micros * 100 / totalMicros;
      print(
        '[bc-profile] ${item.key} count=${entry.count} '
        'micros=${entry.micros} pct=${pct.toStringAsFixed(1)}',
      );
    }
    final topCalls = callTargets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final item in topCalls.take(12)) {
      print('[bc-profile] call_target ${item.key} count=${item.value}');
    }
  }
}

_LuaBytecodeFrame? _bytecodeFrameForCallFrame(CallFrame? callFrame) {
  if (callFrame == null) {
    return null;
  }
  final mapped = _callFrameBytecodeFrames[callFrame];
  if (mapped != null) {
    return mapped;
  }
  return switch (callFrame.engineFrameState) {
    final _LuaBytecodeFrame bytecodeFrame => bytecodeFrame,
    _ => null,
  };
}

void _bindBytecodeCallFrame(CallFrame callFrame, _LuaBytecodeFrame frame) {
  _callFrameBytecodeFrames[callFrame] = frame;
  callFrame.engineFrameState = frame;
}

void _clearBytecodeCallFrame(CallFrame callFrame) {
  _callFrameBytecodeFrames[callFrame] = null;
  if (callFrame.engineFrameState case final _LuaBytecodeFrame _) {
    callFrame.engineFrameState = null;
  }
}

void _rememberCloseSignalYieldable(
  CoroutineCloseSignal signal,
  bool isYieldable,
) {
  final previous = _closeSignalYieldableStates[signal];
  _closeSignalYieldableStates[signal] = switch (previous) {
    null => isYieldable,
    final bool prior => prior && isYieldable,
  };
}

void _debugFileLog(String message) {
  if (_debugFileOps) {
    print('[file-debug] $message');
  }
}

abstract interface class LuaBytecodeGCRootProvider {
  Iterable<GCObject> gcReferences();
}

enum _LuaBinaryOperation {
  add('+'),
  sub('-'),
  mul('*'),
  mod('%'),
  pow('^'),
  div('/'),
  idiv('//'),
  band('&', integerOnly: true),
  bor('|', integerOnly: true),
  bxor('bxor', integerOnly: true),
  shl('<<', integerOnly: true),
  shr('>>', integerOnly: true),
  concat('..', isConcat: true);

  const _LuaBinaryOperation(
    this.operatorSymbol, {
    this.integerOnly = false,
    this.isConcat = false,
  });

  final String operatorSymbol;
  final bool integerOnly;
  final bool isConcat;
}

final class LuaBytecodeClosure extends BuiltinFunction
    implements LuaCallableArtifact, BuiltinFunctionGcRefs {
  factory LuaBytecodeClosure.main({
    required LuaRuntime runtime,
    required LuaBytecodeBinaryChunk chunk,
    required String chunkName,
    required Environment environment,
  }) {
    final upvalues = List<_LuaBytecodeUpvalue>.generate(
      chunk.rootUpvalueCount,
      (_) => _LuaBytecodeUpvalue.closed(_runtimeValue(runtime, null)),
      growable: false,
    );
    if (upvalues.isNotEmpty) {
      final envValue = environment.get('_ENV') ?? environment.root.get('_G');
      upvalues[0] = _LuaBytecodeUpvalue.closed(
        _runtimeValue(runtime, envValue),
      );
    }
    return LuaBytecodeClosure._(
      runtime: runtime,
      prototype: chunk.mainPrototype,
      chunkName: chunkName,
      environment: environment,
      upvalues: upvalues,
    );
  }

  LuaBytecodeClosure._({
    required this.runtime,
    required this.prototype,
    required this.chunkName,
    required this.environment,
    required List<_LuaBytecodeUpvalue> upvalues,
  }) : _upvalues = upvalues,
       super(runtime);

  final LuaRuntime runtime;
  final LuaBytecodePrototype prototype;
  final String chunkName;
  final Environment environment;
  final List<_LuaBytecodeUpvalue> _upvalues;
  FunctionBody? _debugFunctionBody;

  int get upvalueCount => _upvalues.length;

  FunctionBody get debugFunctionBody =>
      _debugFunctionBody ??= _buildDebugFunctionBody();

  String? upvalueName(int index) => prototype.upvalues[index].name;

  Value readUpvalue(int index) => _upvalues[index].read();

  void writeUpvalue(int index, Value value) {
    _upvalues[index].write(value);
  }

  Object upvalueIdentity(int index) => _upvalues[index].identity;

  FunctionBody _buildDebugFunctionBody() {
    final parameters = <Identifier>[];
    for (var register = 0; register < prototype.parameterCount; register++) {
      final local = prototype.localVariables.firstWhere(
        (local) =>
            local.register == register &&
            local.name != null &&
            !local.name!.startsWith('('),
        orElse: () => LuaBytecodeLocalVariableDebugInfo(
          name: '_$register',
          startPc: 0,
          endPc: 0,
          register: register,
        ),
      );
      parameters.add(Identifier(local.name!));
    }
    return FunctionBody(parameters, const <AstNode>[], prototype.isVararg);
  }

  void joinUpvalueWith(int index, LuaBytecodeClosure other, int otherIndex) {
    _upvalues[index] = other._upvalues[otherIndex];
  }

  @override
  LuaFunctionDebugInfo get debugInfo {
    final source = prototype.source ?? chunkName;
    int? firstActiveLine;
    int? lastActiveLine;
    for (var pc = 0; pc < prototype.code.length; pc++) {
      final line = prototype.lineForPc(pc);
      if (line == null || line <= 0) {
        continue;
      }
      firstActiveLine ??= line;
      lastActiveLine = line;
    }
    final lineDefined = prototype.lineDefined > 0 ? prototype.lineDefined : 0;
    final lastLineDefined = switch (lastActiveLine) {
      final int line when line > 0 => switch (prototype.lastLineDefined) {
        final int prototypeLast
            when prototypeLast == line || prototypeLast == line + 1 =>
          prototypeLast,
        _ => line + 1,
      },
      _ when prototype.lastLineDefined > 0 => prototype.lastLineDefined,
      _ => lineDefined,
    };
    return LuaFunctionDebugInfo(
      source: source,
      shortSource: _shortSource(source),
      what: lineDefined == 0 ? 'main' : 'Lua',
      lineDefined: lineDefined,
      lastLineDefined: lastLineDefined,
      nups: _upvalues.length,
      nparams: prototype.parameterCount,
      isVararg: prototype.isVararg,
    );
  }

  @override
  Future<Object?> call(List<Object?> args) async {
    final vm = LuaBytecodeVm(runtime);
    final results = await vm.invoke(this, args, isEntryFrame: true);
    return _packCallResults(runtime, results);
  }

  @override
  Iterable<Object?> getGcReferences() sync* {
    yield environment;
    // Suspended bytecode frames often keep `__close` handlers or iterator
    // callbacks alive only through ordinary Lua Values such as table fields.
    // Exposing the captured upvalue contents here keeps those closures' state
    // reachable without having to retain stale registers past their live range.
    for (final upvalue in _upvalues) {
      final value = upvalue.read();
      yield value;
      if (value.metatableRef case final Value metatable?) {
        yield metatable;
      }
    }
  }
}

final Object _inlineBuiltinUnhandled = Object();

final class LuaBytecodeVm {
  LuaBytecodeVm(this.runtime);

  final LuaRuntime runtime;
  _LuaBytecodeProfile? _activeProfile;

  Interpreter? get _debugInterpreter {
    if (runtime is Interpreter) {
      return runtime as Interpreter;
    }
    try {
      final debugInterpreter = (runtime as dynamic).debugInterpreter;
      if (debugInterpreter is Interpreter) {
        return debugInterpreter;
      }
    } catch (_) {
      // Fall through to environment-bound interpreter discovery.
    }
    final envInterpreter = runtime.getCurrentEnv().interpreter;
    return envInterpreter is Interpreter ? envInterpreter : null;
  }

  Future<List<Value>> invoke(
    LuaBytecodeClosure closure,
    List<Object?> args, {
    Value? functionValue,
    String? callName,
    String? callNameWhat,
    bool isEntryFrame = false,
    bool isTailCall = false,
    int extraArgs = 0,
  }) async {
    final startedProfile =
        _profileBytecode && isEntryFrame && _activeProfile == null
        ? (_activeProfile = _LuaBytecodeProfile(
            label: callName ?? closure.chunkName,
          ))
        : null;
    var currentClosure = closure;
    var currentArgs = args;
    var currentFunctionValue = functionValue;
    var currentCallName = callName;
    var currentCallNameWhat = callNameWhat;
    var currentIsEntryFrame = isEntryFrame;
    var currentIsTailCall = isTailCall;
    var currentExtraArgs = extraArgs;
    try {
      while (true) {
        _guardCallDepth();

        final frame = _LuaBytecodeFrame(
          runtime: runtime,
          closure: currentClosure,
          functionValue: currentFunctionValue,
          arguments: currentArgs,
          callName: currentCallName,
          callNameWhat: currentCallNameWhat,
          isEntryFrame: currentIsEntryFrame,
          isTailCall: currentIsTailCall,
          extraArgs: currentExtraArgs,
        );

        try {
          return await _runFrame(frame);
        } on TailCallException catch (tail) {
          final prepared = _flattenTailCallable(
            valueFromLuaSlot(runtime, tail.functionValue),
            tail.args
                .map((arg) => valueFromLuaSlot(runtime, arg))
                .toList(growable: false),
          );
          final callee = prepared.callee;
          final tailNameInfo = _decodeTailCallNameInfo(tail.callName);
          if (rawLuaSlot(callee) case final LuaBytecodeClosure nextClosure) {
            currentClosure = nextClosure;
            currentArgs = prepared.args;
            currentFunctionValue = callee;
            if (tail.callName != null) {
              currentCallName = tailNameInfo.name;
              currentCallNameWhat = tailNameInfo.namewhat;
            }
            currentIsTailCall = true;
            currentExtraArgs = prepared.extraArgs;
            continue;
          }
          return await _invokePreparedCall(
            (callee: callee, args: prepared.args),
            callName: tail.callName != null
                ? tailNameInfo.name
                : currentCallName,
            callNameWhat: tail.callName != null
                ? tailNameInfo.namewhat
                : currentCallNameWhat,
            isTailCall: true,
          );
        }
      }
    } finally {
      if (startedProfile != null && identical(_activeProfile, startedProfile)) {
        startedProfile.printSummary();
        _activeProfile = null;
      }
    }
  }

  ({Value callee, List<Value> args, int extraArgs}) _flattenTailCallable(
    Value callee,
    List<Value> args,
  ) {
    var extraArgs = 0;
    while (true) {
      callee.interpreter ??= runtime;
      final rawCallee = rawLuaSlot(callee);
      switch (rawCallee) {
        case LuaBytecodeClosure():
        case Function():
        case BuiltinFunction():
        case FunctionDef():
        case FunctionLiteral():
        case FunctionBody():
        case LuaCallableArtifact():
          return (callee: callee, args: args, extraArgs: extraArgs);
        case final String name:
          final rebound = runtime.globals.get(name);
          if (rebound != null) {
            callee = rebound;
            continue;
          }
          return (callee: callee, args: args, extraArgs: extraArgs);
        default:
          if (!callee.hasMetamethod('__call')) {
            return (callee: callee, args: args, extraArgs: extraArgs);
          }
          final callMeta = callee.getMetamethod('__call');
          if (callMeta == null) {
            return (callee: callee, args: args, extraArgs: extraArgs);
          }
          if (extraArgs >= 15) {
            throw LuaError("'__call' chain too long");
          }
          final originalCallee = callee;
          callee = valueFromLuaSlot(runtime, callMeta);
          args = <Value>[originalCallee, ...args];
          extraArgs += 1;
      }
    }
  }

  Future<List<Value>> _runFrame(_LuaBytecodeFrame frame) async {
    final closure = frame.closure;
    final previousEnv = runtime.getCurrentEnv();
    final previousScriptPath = runtime.currentScriptPath;
    final previousCallStackScriptPath = runtime.callStack.scriptPath;
    final parentFrame = runtime.callStack.top;
    final parentFrameEnv = parentFrame?.env;
    runtime.pushExternalGcRoots(frame.externalGcRootProvider);
    runtime.setCurrentEnv(closure.environment);
    final activeScriptPath = closure.prototype.source ?? previousScriptPath;
    runtime.currentScriptPath = activeScriptPath;
    runtime.callStack.setScriptPath(activeScriptPath);
    final callableValue = switch (frame.functionValue) {
      final Value functionValue
          when rawLuaSlot(functionValue) is LuaBytecodeClosure =>
        _hydrateClosureCallableValue(
          functionValue,
          closure,
          fallbackName: frame.callName ?? closure.debugInfo.shortSource,
        ),
      final Value functionValue => functionValue,
      _ => (Value(
        closure,
        functionBody: closure.debugFunctionBody,
        closureEnvironment: closure.environment,
        functionName: frame.callName ?? closure.debugInfo.shortSource,
      )..interpreter = runtime),
    };
    runtime.callStack.push(
      frame.callName ?? closure.debugInfo.shortSource,
      env: closure.environment,
      debugName: frame.callName,
      debugNameWhat: frame.callName == 'hook'
          ? 'hook'
          : (frame.callNameWhat ?? ''),
      callable: callableValue,
    );
    if (parentFrame != null) {
      parentFrame.env = parentFrameEnv;
    }
    final activeCallFrame = runtime.callStack.top;
    if (activeCallFrame != null) {
      _bindBytecodeCallFrame(activeCallFrame, frame);
      final isHookCallback =
          frame.callName == 'hook' ||
          frame.callNameWhat == 'hook' ||
          // The interpreter wraps debug hooks with an outer call-stack frame
          // before dispatching into bytecode. The first bytecode frame inside
          // that wrapper is still the hook callback, but helper calls made from
          // inside the hook should not inherit hook visibility.
          (parentFrame?.isDebugHook == true &&
              _bytecodeFrameForCallFrame(parentFrame!) == null);
      if (isHookCallback) {
        // Only the hook callback itself should count as a debug-hook frame for
        // visibility purposes. Helper functions that the hook calls must remain
        // visible in `debug.getlocal`/`debug.getinfo` stack walks so their
        // levels line up with the reference interpreter.
        activeCallFrame.isDebugHook = true;
      }
      if (frame.callName == null &&
          closure.debugInfo.what != 'main' &&
          activeCallFrame.callable?.functionBody != null) {
        activeCallFrame.functionName = 'unknown';
      }
      activeCallFrame.isTailCall = frame.isTailCall;
      activeCallFrame.extraArgs = frame.extraArgs;
    }
    _syncDebugLocals(frame);
    final entryDebugInterpreter = _debugInterpreter;
    if (frame.pc == 0 &&
        activeCallFrame != null &&
        !activeCallFrame.isDebugHook &&
        entryDebugInterpreter != null &&
        entryDebugInterpreter.debugHookMask.contains('l') &&
        !closure.prototype.hasDebugInfo) {
      await entryDebugInterpreter.fireDebugHook('line');
    }
    if (platform.getEnvironmentVariable('LUALIKE_DEBUG_BYTECODE_HOOKS') ==
        '1') {
      print(
        '[bc-hook] entry debug=${entryDebugInterpreter != null} '
        'hook=${entryDebugInterpreter?.debugHookFunction != null} '
        'mask=${entryDebugInterpreter?.debugHookMask} '
        'co=${runtime.getCurrentCoroutine()?.hashCode}',
      );
    }
    if (entryDebugInterpreter != null &&
        !frame.didFireEntryCallHook &&
        !(frame.pc == 0 && frame.closure.prototype.isVararg)) {
      await _fireFrameCallHook(frame, entryDebugInterpreter);
    }

    var suspended = false;
    var poppedCallFrame = false;
    List<Value> returnTransferValues = const <Value>[];
    try {
      final result = await _executeFrame(frame);
      returnTransferValues = result;
      return result;
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? runtime.getCurrentCoroutine();
      if (coroutine == null || !coroutine.hasContinuation) {
        throw LuaError(
          _opcodeDiagnostic(
            frame,
            'YIELD',
            detail: 'yield across unsupported lua_bytecode coroutine path',
          ),
        );
      }
      suspended = true;
      rethrow;
    } on CoroutineCloseSignal catch (signal) {
      var closeYieldable = _closeSignalYieldableStates[signal];
      runtime.callStack.pop();
      poppedCallFrame = true;
      var closeResult = signal.result;
      if (!frame.closed) {
        final previousYieldable = runtime.isYieldable;
        try {
          if (closeYieldable != null) {
            runtime.isYieldable = closeYieldable;
          }
          await _closeFrameForCoroutine(frame, error: null);
        } on CoroutineCloseSignal catch (nestedSignal) {
          closeResult = nestedSignal.result;
          closeYieldable =
              _closeSignalYieldableStates[nestedSignal] ?? closeYieldable;
        } on YieldException {
          closeResult = <Object?>[
            runtime.constantPrimitiveValue(false),
            runtime.constantDartStringValue(
              'attempt to yield across a C-call boundary',
            ),
          ];
        } catch (error) {
          final adjustedError = switch (error) {
            final LuaError luaError
                when runtime.isInProtectedCall &&
                    luaError.cause != null &&
                    luaError.cause is! LuaError =>
              luaError.cause!,
            final LuaError luaError => _normalizeStrippedFrameError(
              frame,
              _withFrameRuntimeLocation(frame, luaError),
            ),
            _ => error,
          };
          final normalizedError = _normalizeBytecodeCoroutineCloseError(
            adjustedError,
          );
          closeResult = <Object?>[
            runtime.constantPrimitiveValue(false),
            valueFromLuaSlot(runtime, normalizedError),
          ];
        } finally {
          runtime.isYieldable = previousYieldable;
        }
      }
      final propagatedSignal = CoroutineCloseSignal(closeResult);
      if (closeYieldable != null) {
        _rememberCloseSignalYieldable(propagatedSignal, closeYieldable);
      }
      throw propagatedSignal;
    } catch (error, stackTrace) {
      final adjustedError = switch (error) {
        final LuaError luaError
            when runtime.isInProtectedCall &&
                luaError.cause != null &&
                luaError.cause is! LuaError =>
          luaError.cause!,
        final LuaError luaError => _normalizeStrippedFrameError(
          frame,
          _withFrameRuntimeLocation(frame, luaError),
        ),
        _ => error,
      };
      runtime.callStack.pop();
      poppedCallFrame = true;
      _tmpDebugFrame(
        frame,
        'runframe-error adjusted=${adjustedError.runtimeType}:$adjustedError pc=${frame.pc} '
        'closed=${frame.closed}',
      );
      if (!frame.closed) {
        try {
          await _closeFrameForCoroutine(frame, error: adjustedError);
        } on YieldException catch (yieldError) {
          suspended = true;
          _suspendErrorClose(frame, adjustedError, stackTrace, yieldError);
        }
      }
      throw adjustedError;
    } finally {
      runtime.popExternalGcRoots(frame.externalGcRootProvider);
      if (!suspended && !frame.closed) {
        await _closeFrameForCoroutine(frame, error: null);
      }
      final exitDebugInterpreter = _debugInterpreter;
      if (!suspended && !poppedCallFrame && exitDebugInterpreter != null) {
        final topFrame = runtime.callStack.top;
        _syncCallFrameDebugLocals(topFrame);
        _setTransferInfo(topFrame, returnTransferValues);
        final interpreter = exitDebugInterpreter;
        await interpreter.fireDebugHook('return');
        _clearTransferInfo(topFrame);
      }
      if (!poppedCallFrame) {
        runtime.callStack.pop();
      }
      if (suspended) {
        while (runtime.callStack.top?.isDebugHook ?? false) {
          runtime.callStack.pop();
        }
      }
      runtime.callStack.setScriptPath(previousCallStackScriptPath);
      runtime.currentScriptPath = previousScriptPath;
      runtime.setCurrentEnv(previousEnv);
      if (parentFrame != null) {
        parentFrame.env = parentFrameEnv;
      }
    }
  }

  Future<List<Value>> _runFrameWithTailCalls(_LuaBytecodeFrame frame) async {
    while (true) {
      try {
        return await _runFrame(frame);
      } on TailCallException catch (tail) {
        final prepared = _flattenTailCallable(
          valueFromLuaSlot(runtime, tail.functionValue),
          tail.args
              .map((arg) => valueFromLuaSlot(runtime, arg))
              .toList(growable: false),
        );
        final callee = prepared.callee;
        if (rawLuaSlot(callee) case final LuaBytecodeClosure nextClosure) {
          try {
            return await invoke(
              nextClosure,
              prepared.args,
              functionValue: callee,
              callName: tail.callName,
              extraArgs: prepared.extraArgs,
            );
          } on YieldException catch (error) {
            _suspendTailCall(frame, error);
          }
        }
        try {
          return await _invokeValueWithName(
            callee,
            prepared.args,
            callName: tail.callName,
            extraArgs: prepared.extraArgs,
          );
        } on YieldException catch (error) {
          _suspendTailCall(frame, error);
        }
      }
    }
  }

  Future<List<Value>> _executeFrame(_LuaBytecodeFrame frame) async {
    final prototype = frame.closure.prototype;
    final mainThread = runtime.getMainThread();
    final linesByPc = prototype.hasDebugInfo ? prototype.linesByPc : null;
    var currentCoroutine = runtime.getCurrentCoroutine();
    while (frame.pc < prototype.code.length) {
      frame.expireDeadLocals();
      currentCoroutine = _syncCurrentCoroutine(mainThread, currentCoroutine);
      // AST execution only checks auto-GC at statement boundaries. Bytecode
      // runs many more VM instructions per statement, and tighter polling here
      // makes collector debt dominate random-heavy loops. Loop backedges still
      // have their own GC safe point, so keep this coarse.
      if (++frame.safePointCounter >= 512) {
        frame.safePointCounter = 0;
        runtime.runAutoGcAtSafePoint();
      }
      int? nextOpenTop;
      final instructionPc = frame.pc++;
      final word = prototype.code[instructionPc];
      final opcode = word.opcode;
      final lineNumber = linesByPc?[instructionPc];
      final debugInterpreter = _debugInterpreter;
      final hasDebugHook = debugInterpreter?.debugHookFunction != null;
      final previousVisibleLine = hasDebugHook
          ? runtime.callStack.top?.currentLine ?? -1
          : -1;
      final needsCoroutineWideBoundary =
          currentCoroutine != null && !identical(currentCoroutine, mainThread);
      final profile = _activeProfile;
      final opTimer = profile == null ? null : (Stopwatch()..start());
      try {
        if (needsCoroutineWideBoundary ||
            _needsSuspendingOpcodeBoundaryForInstruction(
              frame,
              word.opcode,
              word,
            )) {
          await _preserveSuspendingBytecodeBoundary(
            currentCoroutine: currentCoroutine,
            mainThread: mainThread,
          );
        }
        final forceLineHook = frame.forceNextLineHook;
        frame.forceNextLineHook = false;
        final deferCountHook = hasDebugHook
            ? _deferCountHookForOpcode(opcode)
            : false;
        if (hasDebugHook && !deferCountHook) {
          _syncDebugLocals(frame);
          await debugInterpreter!.maybeFireCountDebugHook();
        }
        if (lineNumber != null) {
          runtime.callStack.top?.currentLine = lineNumber;
          final suppressOwnLineHook = opcode == Opcode.jmp && word.sJ < 0;
          if (hasDebugHook &&
              opcode != Opcode.varArgPrep &&
              !suppressOwnLineHook) {
            _syncDebugLocals(frame);
            await debugInterpreter!.maybeFireLineDebugHook(
              lineNumber,
              force: forceLineHook,
            );
          }
        }
        switch (opcode) {
          case Opcode.move:
            {
              frame.setRegister(word.a, frame.register(word.b));
              break;
            }
          case Opcode.loadI:
            {
              frame.setRegister(
                word.a,
                _framePrimitiveValue(runtime, word.sBx),
              );
              break;
            }
          case Opcode.loadF:
            {
              frame.setRegister(
                word.a,
                _framePrimitiveValue(runtime, word.sBx.toDouble()),
              );
              break;
            }
          case Opcode.loadK:
            {
              frame.setRegister(
                word.a,
                _constantValue(runtime, prototype, word.bx),
              );
              break;
            }
          case Opcode.loadKx:
            {
              frame.setRegister(
                word.a,
                _constantValue(runtime, prototype, _consumeExtraArg(frame).ax),
              );
              break;
            }
          case Opcode.loadFalse:
            {
              frame.setRegister(word.a, _framePrimitiveValue(runtime, false));
              break;
            }
          case Opcode.lFalseSkip:
            {
              frame.setRegister(word.a, _framePrimitiveValue(runtime, false));
              frame.pc += 1;
              break;
            }
          case Opcode.loadTrue:
            {
              frame.setRegister(word.a, _framePrimitiveValue(runtime, true));
              break;
            }
          case Opcode.loadNil:
            {
              for (var index = 0; index <= word.b; index++) {
                frame.setRegister(
                  word.a + index,
                  _framePrimitiveValue(runtime, null),
                );
              }
              break;
            }
          case Opcode.getUpval:
            {
              frame.setRegister(word.a, frame.closure._upvalues[word.b].read());
              break;
            }
          case Opcode.setUpval:
            {
              frame.closure._upvalues[word.b].write(frame.register(word.a));
              break;
            }
          case Opcode.getTabUp:
            {
              final receiver = frame.closure._upvalues[word.b].read();
              final rawKey = _stringConstantRaw(prototype, word.c);
              final fastValue = _tryFastTableGetStringKey(receiver, rawKey);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              final key = _stringConstant(runtime, prototype, word.c);
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(
                  frame,
                  receiver,
                  error,
                  labelOverride: "global '${rawLuaSlot(key)}'",
                );
              }
              break;
            }
          case Opcode.getTable:
            {
              final receiver = frame.register(word.b);
              final key = frame.register(word.c);
              final fastValue = _tryFastTableGet(receiver, key);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.getI:
            {
              final receiver = frame.register(word.b);
              final key = runtime.constantPrimitiveValue(word.c);
              final fastValue = _tryFastTableGet(receiver, key);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.getField:
            {
              final receiver = frame.register(word.b);
              final rawKey = _stringConstantRaw(prototype, word.c);
              final fastValue = _tryFastTableGetStringKey(receiver, rawKey);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              final key = _stringConstant(runtime, prototype, word.c);
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.setTabUp:
            {
              final receiver = frame.closure._upvalues[word.a].read();
              final rawKey = _stringConstantRaw(prototype, word.b);
              final value = _rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSetStringKey(receiver, rawKey, value)) {
                break;
              }
              final key = _stringConstant(runtime, prototype, word.b);
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(
                  frame,
                  receiver,
                  error,
                  labelOverride: "global '${rawLuaSlot(key)}'",
                );
              }
              break;
            }
          case Opcode.checkGlobal:
            {
              final name = _stringConstantRaw(prototype, word.bx);
              if (await _explicitGlobalIsAlreadyDefined(
                frame.register(word.a),
                frame.closure.environment,
                name,
              )) {
                throw LuaError("global '$name' already defined");
              }
              break;
            }
          case Opcode.setTable:
            {
              final receiver = frame.register(word.a);
              final key = frame.register(word.b);
              final value = _rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSet(receiver, key, value)) {
                break;
              }
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.setI:
            {
              final receiver = frame.register(word.a);
              final key = runtime.constantPrimitiveValue(word.b);
              final value = _rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSet(receiver, key, value)) {
                break;
              }
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.setField:
            {
              final receiver = frame.register(word.a);
              final rawKey = _stringConstantRaw(prototype, word.b);
              final value = _rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSetStringKey(receiver, rawKey, value)) {
                break;
              }
              final key = _stringConstant(runtime, prototype, word.b);
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.newTable:
            {
              final extra = word.kFlag
                  ? _consumeExtraArg(frame)
                  : _consumeOptionalZeroExtraArg(frame);
              final extraAx = extra?.ax ?? 0;
              final tableStorage = TableStorage();
              final arraySize =
                  word.vc +
                  (word.kFlag
                      ? extraAx * (LuaBytecodeInstructionLayout.maxArgVC + 1)
                      : 0);
              if (arraySize > 0) {
                tableStorage.ensureArrayCapacity(arraySize);
              }
              frame.setRegister(word.a, _runtimeValue(runtime, tableStorage));
              break;
            }
          case Opcode.self:
            {
              final receiver = frame.register(word.b);
              frame.setRegister(word.a + 1, receiver);
              final rawKey = _stringConstantRaw(prototype, word.c);
              final fastValue = _tryFastTableGetStringKey(receiver, rawKey);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              final key = _stringConstant(runtime, prototype, word.c);
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.addI:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: runtime.constantPrimitiveValue(_signedC(word)),
                operation: _LuaBinaryOperation.add,
              );
              break;
            }
          case Opcode.addK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.add,
              );
              break;
            }
          case Opcode.subK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.sub,
              );
              break;
            }
          case Opcode.mulK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.mul,
              );
              break;
            }
          case Opcode.modK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.mod,
              );
              break;
            }
          case Opcode.powK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.pow,
              );
              break;
            }
          case Opcode.divK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.div,
              );
              break;
            }
          case Opcode.idivK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.idiv,
              );
              break;
            }
          case Opcode.bandK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.band,
              );
              break;
            }
          case Opcode.borK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.bor,
              );
              break;
            }
          case Opcode.bxorK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: _constantValue(runtime, prototype, word.c),
                operation: _LuaBinaryOperation.bxor,
              );
              break;
            }
          case Opcode.shlI:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: runtime.constantPrimitiveValue(_signedC(word)),
                right: frame.register(word.b),
                operation: _LuaBinaryOperation.shl,
              );
              break;
            }
          case Opcode.shrI:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: runtime.constantPrimitiveValue(_signedC(word)),
                operation: _LuaBinaryOperation.shr,
              );
              break;
            }
          case Opcode.add:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.add,
              );
              break;
            }
          case Opcode.sub:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.sub,
              );
              break;
            }
          case Opcode.mul:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.mul,
              );
              break;
            }
          case Opcode.mod:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.mod,
              );
              break;
            }
          case Opcode.pow:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.pow,
              );
              break;
            }
          case Opcode.div:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.div,
              );
              break;
            }
          case Opcode.idiv:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.idiv,
              );
              break;
            }
          case Opcode.band:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.band,
              );
              break;
            }
          case Opcode.bor:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.bor,
              );
              break;
            }
          case Opcode.bxor:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.bxor,
              );
              break;
            }
          case Opcode.shl:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.shl,
              );
              break;
            }
          case Opcode.shr:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: _LuaBinaryOperation.shr,
              );
              break;
            }
          case Opcode.unm:
            {
              final operand = frame.register(word.b);
              final rawOperand = rawLuaSlot(operand);
              if (_canFastPathNumeric(operand)) {
                frame.setRegister(
                  word.a,
                  _runtimeValue(runtime, NumberUtils.negate(rawOperand)),
                );
                break;
              }
              try {
                frame.setRegister(
                  word.a,
                  await _executeUnaryInstruction(
                    frame,
                    operand,
                    operandRegister: word.b,
                    metamethod: '__unm',
                    fastPath: (value) => _canFastPathNumeric(value)
                        ? _runtimeValue(
                            runtime,
                            NumberUtils.negate(rawLuaSlot(value)),
                          )
                        : null,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              }
              break;
            }
          case Opcode.bnot:
            {
              final operand = frame.register(word.b);
              final rawOperand = rawLuaSlot(operand);
              if (_canFastPathInteger(operand)) {
                frame.setRegister(
                  word.a,
                  _runtimeValue(runtime, NumberUtils.bitwiseNot(rawOperand)),
                );
                break;
              }
              try {
                frame.setRegister(
                  word.a,
                  await _executeUnaryInstruction(
                    frame,
                    operand,
                    operandRegister: word.b,
                    metamethod: '__bnot',
                    fastPath: (value) => _canFastPathInteger(value)
                        ? _runtimeValue(
                            runtime,
                            NumberUtils.bitwiseNot(rawLuaSlot(value)),
                          )
                        : null,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              }
              break;
            }
          case Opcode.notOp:
            {
              frame.setRegister(
                word.a,
                _runtimeValue(runtime, !isLuaTruthy(frame.register(word.b))),
              );
              break;
            }
          case Opcode.len:
            {
              final operand = frame.register(word.b);
              if (_canFastPathLength(operand)) {
                frame.setRegister(
                  word.a,
                  _runtimeValue(runtime, _lengthOf(operand)),
                );
                break;
              }
              try {
                frame.setRegister(
                  word.a,
                  await _executeUnaryInstruction(
                    frame,
                    operand,
                    operandRegister: word.b,
                    metamethod: '__len',
                    fastPath: (value) => _canFastPathLength(value)
                        ? _runtimeValue(runtime, _lengthOf(value))
                        : null,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              }
              break;
            }
          case Opcode.concat:
            {
              frame.setRegister(
                word.a,
                await _executeConcatInstruction(frame, word.a, word.b),
              );
              break;
            }
          case Opcode.mmBin:
            {
              final targetRegister = _previousInstruction(frame).a;
              try {
                frame.setRegister(
                  targetRegister,
                  await _executeMetamethodBinaryInstruction(
                    frame,
                    metamethod: _metamethodName(word.c),
                    left: frame.register(word.a),
                    right: frame.register(word.b),
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, targetRegister, error);
              }
              break;
            }
          case Opcode.mmBinI:
            {
              final immediate = runtime.constantPrimitiveValue(_signedB(word));
              final (left, right) = word.kFlag
                  ? (immediate, frame.register(word.a))
                  : (frame.register(word.a), immediate);
              final targetRegister = _previousInstruction(frame).a;
              try {
                frame.setRegister(
                  targetRegister,
                  await _executeMetamethodBinaryInstruction(
                    frame,
                    metamethod: _metamethodName(word.c),
                    left: left,
                    right: right,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, targetRegister, error);
              }
              break;
            }
          case Opcode.mmBinK:
            {
              final constant = _constantValue(runtime, prototype, word.b);
              final (left, right) = word.kFlag
                  ? (constant, frame.register(word.a))
                  : (frame.register(word.a), constant);
              final targetRegister = _previousInstruction(frame).a;
              try {
                frame.setRegister(
                  targetRegister,
                  await _executeMetamethodBinaryInstruction(
                    frame,
                    metamethod: _metamethodName(word.c),
                    left: left,
                    right: right,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, targetRegister, error);
              }
              break;
            }
          case Opcode.tbc:
            {
              // Mark register A as a to-be-closed variable. If the value has
              // no __close metamethod, Value.toBeClose throws UnsupportedError.
              // markToBeClosed wraps that in LuaError with the Lua message, but
              // in some code paths (e.g. shared-primitive detach variants) the
              // UnsupportedError can escape unwrapped. Both catch arms normalise
              // the error and produce the Lua-spec message
              // "variable '<name>' got a non-closable value" when debug info is
              // available, so pcall sees a proper Lua string rather than a raw
              // Dart exception toString().
              try {
                frame.markToBeClosed(word.a);
              } on LuaError catch (error) {
                // markToBeClosed already wrapped the UnsupportedError; rewrite
                // the message to include the local variable name if debug info
                // is present and the message hasn't been rewritten yet.
                final localName = frame.localNameForError(word.a);
                if (localName != null &&
                    error.message ==
                        'to-be-closed variable value must have a __close metamethod') {
                  throw LuaError(
                    "variable '$localName' got a non-closable value",
                  );
                }
                rethrow;
              } on UnsupportedError catch (error) {
                // Belt-and-suspenders: catch UnsupportedError that escapes
                // markToBeClosed unwrapped (e.g. thrown by a code path
                // introduced by refactoring before the inner try/catch).
                // Apply the same local-name rewrite so the error message is
                // always Lua-spec compliant.
                final localName = frame.localNameForError(word.a);
                final baseMessage = error.message ?? error.toString();
                final message =
                    localName != null &&
                        baseMessage ==
                            'to-be-closed variable value must have a __close metamethod'
                    ? "variable '$localName' got a non-closable value"
                    : baseMessage;
                throw LuaError(message);
              }
              break;
            }
          case Opcode.varArgPrep:
            {
              if (debugInterpreter != null && !frame.didFireEntryCallHook) {
                await _fireFrameCallHook(frame, debugInterpreter);
                frame.forceNextLineHook = true;
              }
              break;
            }
          case Opcode.jmp:
            {
              frame.pc += word.sJ;
              if (word.sJ < 0) {
                _resetBackedgeLineHookState(
                  runtime,
                  _debugInterpreter,
                  frame,
                  loopLine: lineNumber ?? previousVisibleLine,
                );
                if (_runGcLoopSafePoint(runtime, frame) case final gcWork?) {
                  await gcWork;
                }
              }
              break;
            }
          case Opcode.eq:
            {
              final left = frame.register(word.a);
              final right = frame.register(word.b);
              if (_rawEquals(left, right)) {
                _docondjump(frame, word, true);
                break;
              }
              if (!_supportsEqualityMetamethod(left, right) ||
                  (!left.hasMetamethod('__eq') &&
                      !right.hasMetamethod('__eq'))) {
                _docondjump(frame, word, false);
                break;
              }
              try {
                _docondjump(frame, word, await _compareEquals(left, right));
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.lt:
            {
              final left = frame.register(word.a);
              final right = frame.register(word.b);
              final primitiveResult = _tryPrimitiveOrdering(
                left,
                right,
                _PrimitiveCompare.lessThan,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareOrdering(
                    left,
                    right,
                    metamethod: '__lt',
                    primitiveCompare: _PrimitiveCompare.lessThan,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.le:
            {
              final left = frame.register(word.a);
              final right = frame.register(word.b);
              final primitiveResult = _tryPrimitiveOrdering(
                left,
                right,
                _PrimitiveCompare.lessThanOrEqual,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareOrdering(
                    left,
                    right,
                    metamethod: '__le',
                    primitiveCompare: _PrimitiveCompare.lessThanOrEqual,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.eqK:
            {
              _docondjump(
                frame,
                word,
                _rawEquals(
                  frame.register(word.a),
                  _constantValue(runtime, prototype, word.b),
                ),
              );
              break;
            }
          case Opcode.eqI:
            {
              _docondjump(
                frame,
                word,
                _compareImmediateEquals(frame.register(word.a), _signedB(word)),
              );
              break;
            }
          case Opcode.ltI:
            {
              final left = frame.register(word.a);
              final right = _signedB(word);
              final primitiveResult = _tryPrimitiveImmediateOrdering(
                left,
                right,
                _PrimitiveCompare.lessThan,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__lt',
                    primitiveCompare: _PrimitiveCompare.lessThan,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.leI:
            {
              final left = frame.register(word.a);
              final right = _signedB(word);
              final primitiveResult = _tryPrimitiveImmediateOrdering(
                left,
                right,
                _PrimitiveCompare.lessThanOrEqual,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__le',
                    primitiveCompare: _PrimitiveCompare.lessThanOrEqual,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.gtI:
            {
              final left = frame.register(word.a);
              final right = _signedB(word);
              final primitiveResult = _tryPrimitiveImmediateOrdering(
                left,
                right,
                _PrimitiveCompare.greaterThan,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__lt',
                    primitiveCompare: _PrimitiveCompare.greaterThan,
                    flipOperands: true,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.geI:
            {
              final left = frame.register(word.a);
              final right = _signedB(word);
              final primitiveResult = _tryPrimitiveImmediateOrdering(
                left,
                right,
                _PrimitiveCompare.greaterThanOrEqual,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__le',
                    primitiveCompare: _PrimitiveCompare.greaterThanOrEqual,
                    flipOperands: true,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.test:
            {
              _docondjump(frame, word, isLuaTruthy(frame.register(word.a)));
              break;
            }
          case Opcode.testSet:
            {
              final value = frame.register(word.b);
              final shouldSkipJump = !isLuaTruthy(value) == word.kFlag;
              if (shouldSkipJump) {
                frame.pc += 1;
              } else {
                frame.setRegister(word.a, value);
              }
              break;
            }
          case Opcode.call:
            {
              try {
                final callee = frame.register(word.a);
                final rawCallee = rawLuaSlot(callee);
                if (profile case final activeProfile?) {
                  activeProfile.recordCallTarget(
                    _callSiteTargetLabel(frame, word.a, callee) ??
                        rawCallee.runtimeType.toString(),
                  );
                }
                if (_debugInterpreter?.debugHookFunction == null &&
                    rawCallee is BuiltinFunction &&
                    word.b != 0) {
                  final fixedArityInlineResult =
                      _tryHandleFixedArityInlineBuiltinCall(
                        frame,
                        word,
                        callee,
                        rawCallee,
                      );
                  if (!identical(
                    fixedArityInlineResult,
                    _inlineBuiltinUnhandled,
                  )) {
                    nextOpenTop = fixedArityInlineResult as int?;
                    break;
                  }
                }
                final callTop = word.b == 0
                    ? frame.effectiveTop
                    : word.a + word.b;
                frame.top = callTop;
                frame.openTop = word.b == 0 ? callTop : null;
                if (_debugFileOps) {
                  final nameInfo = _callSiteNameInfo(frame, word.a, callee);
                  final receiver =
                      word.b >= 2 && word.a + 1 < frame.registers.length
                      ? frame.register(word.a + 1)
                      : null;
                  final receiverDetail = switch (rawLuaSlot(receiver)) {
                    final LuaFile file =>
                      ' receiverValue=${identityHashCode(receiver)}'
                          ' receiverRaw=${identityHashCode(file)}'
                          ' trackedValue=${identityHashCode(IOLib.trackedOpenFileWrapper(file))}',
                    _ => '',
                  };
                  _debugFileLog(
                    'CALL pc=${frame.pc - 1} a=${word.a} b=${word.b} c=${word.c} '
                    'callee=${rawCallee.runtimeType} name=${nameInfo.name}'
                    '$receiverDetail',
                  );
                }
                List<Value>? results;
                if (_debugInterpreter?.debugHookFunction == null &&
                    rawCallee is BuiltinFunction &&
                    _canInlineBuiltinWithoutManagedFrame(rawCallee)) {
                  final storedAssertResult = _tryStoreInlineAssertSuccess(
                    frame,
                    word,
                    builtin: rawCallee,
                  );
                  if (!identical(storedAssertResult, _inlineBuiltinUnhandled)) {
                    nextOpenTop = storedAssertResult as int?;
                    break;
                  } else {
                    if (rawCallee.isBytecodeAssertBuiltin) {
                      results = await _callAt(frame, word);
                    } else {
                      final rawFastResult =
                          _tryInlineBuiltinFastArityRawFromFrame(
                            frame,
                            word,
                            builtin: rawCallee,
                          );
                      if (!identical(
                        rawFastResult,
                        BuiltinFunction.fastCallUnsupported,
                      )) {
                        final storedFastResult = _tryStoreFastInlineResult(
                          frame,
                          word.a,
                          word.c,
                          rawFastResult,
                        );
                        if (!identical(
                          storedFastResult,
                          _inlineBuiltinUnhandled,
                        )) {
                          nextOpenTop = storedFastResult as int?;
                          break;
                        }
                      }
                      results = await _invokeInlineBuiltinFromFrame(
                        callee,
                        frame,
                        word,
                        builtin: rawCallee,
                      );
                    }
                  }
                } else {
                  results = await _callAt(frame, word);
                }
                if (word.c == 1) {
                  await _closeDiscardedCallResults(frame, results);
                }
                nextOpenTop = _storeCallResults(frame, word.a, word.c, results);
              } on YieldException catch (error) {
                _suspendCall(frame, word.a, word.c, error);
              }
              break;
            }
          case Opcode.tailCall:
            {
              try {
                final callTop = word.b == 0
                    ? frame.effectiveTop
                    : word.a + word.b;
                frame.top = callTop;
                frame.openTop = word.b == 0 ? callTop : null;
                final call = _resolveCall(frame, word);
                final tailName = _callSiteTargetLabel(
                  frame,
                  word.a,
                  call.callee,
                );
                final tailNameInfo = _decodeTailCallNameInfo(tailName);
                final prepared = _flattenTailCallable(call.callee, call.args);
                final callee = prepared.callee;
                if (rawLuaSlot(callee) case LuaBytecodeClosure()) {
                  await _closeFrameForCoroutine(frame, error: null);
                  throw TailCallException(
                    callee,
                    prepared.args,
                    callName: tailName,
                  );
                }
                final results = await _invokePreparedCall(
                  (callee: callee, args: prepared.args),
                  frame: frame,
                  callName: tailNameInfo.name,
                  callNameWhat: tailNameInfo.namewhat,
                  isTailCall: true,
                );
                await _closeFrameForCoroutine(frame, error: null);
                return results;
              } on YieldException catch (error) {
                _suspendTailCall(frame, error);
              }
            }
          case Opcode.return_:
            {
              try {
                await _closeFrameForCoroutine(frame, error: null);
                final resultCount = word.b == 0
                    ? frame.effectiveTop - word.a
                    : word.b - 1;
                return frame.resultsFrom(word.a, resultCount);
              } on YieldException catch (error) {
                _suspendReturn(frame, word.a, word.b, error);
              }
            }
          case Opcode.return0:
            {
              try {
                await _closeFrameForCoroutine(frame, error: null);
                return const <Value>[];
              } on YieldException catch (error) {
                _suspendReturn(frame, 0, 1, error);
              }
            }
          case Opcode.return1:
            {
              try {
                await _closeFrameForCoroutine(frame, error: null);
                return <Value>[frame.register(word.a)];
              } on YieldException catch (error) {
                _suspendReturn(frame, word.a, 2, error);
              }
            }
          case Opcode.forPrep:
            {
              if (_forPrep(frame, word.a)) {
                frame.pc += word.bx + 1;
              }
              break;
            }
          case Opcode.forLoop:
            {
              if (_forLoop(frame, word.a)) {
                frame.pc -= word.bx;
                _resetBackedgeLineHookState(
                  runtime,
                  _debugInterpreter,
                  frame,
                  loopLine: lineNumber ?? previousVisibleLine,
                );
                if (_runGcLoopSafePoint(runtime, frame) case final gcWork?) {
                  await gcWork;
                }
              }
              break;
            }
          case Opcode.tForPrep:
            {
              final closingValue = frame.register(word.a + 3);
              final controlValue = frame.register(word.a + 2);
              frame.setRegister(word.a + 2, closingValue);
              frame.setRegister(word.a + 3, controlValue);
              frame.markToBeClosed(word.a + 2);
              frame.pc += word.bx;
              break;
            }
          case Opcode.tForCall:
            {
              try {
                final results = await _genericForCall(frame, word.a, word.c);
                for (var index = 0; index < results.length; index++) {
                  frame.setRegister(word.a + 3 + index, results[index]);
                }
                frame.top = word.a + 3 + results.length;
              } on YieldException catch (error) {
                _suspendTForCall(frame, word.a, word.c, error);
              }
              break;
            }
          case Opcode.tForLoop:
            {
              if (!isLuaNilSlot(frame.register(word.a + 3))) {
                frame.pc -= word.bx;
                if (_runGcLoopSafePoint(runtime, frame) case final gcWork?) {
                  await gcWork;
                }
              }
              break;
            }
          case Opcode.setList:
            {
              await _setList(frame, word);
              break;
            }
          case Opcode.closure:
            {
              final child = prototype.prototypes[word.bx];
              frame.setRegister(
                word.a,
                _wrapClosure(_createClosure(frame, child)),
              );
              break;
            }
          case Opcode.varArg:
            {
              nextOpenTop = _storeVarargResults(frame, word);
              break;
            }
          case Opcode.getVarArg:
            {
              final keyValue = frame.register(word.c);
              final rawKey = rawLuaSlot(keyValue);
              final index = switch (rawKey) {
                final int integer => integer,
                final BigInt integer => NumberUtils.tryToInteger(integer),
                final double number
                    when number.isFinite &&
                        number.truncateToDouble() == number =>
                  number.toInt(),
                _ => null,
              };
              if (index != null) {
                if (index < 1 || index > frame.varargCount) {
                  frame.setRegister(
                    word.a,
                    runtime.constantPrimitiveValue(null),
                  );
                } else {
                  frame.setRegister(word.a, frame.varargAt(index - 1)!);
                }
              } else {
                final keyText = switch (rawKey) {
                  final String text => text,
                  final LuaString text => text.toString(),
                  _ => null,
                };
                if (keyText == 'n') {
                  frame.setRegister(
                    word.a,
                    runtime.constantPrimitiveValue(frame.varargCount),
                  );
                } else {
                  frame.setRegister(
                    word.a,
                    runtime.constantPrimitiveValue(null),
                  );
                }
              }
              break;
            }
          case Opcode.close:
            {
              if (word.b != 0) {
                break;
              }
              if (_debugFileOps) {
                _debugFileLog(
                  'CLOSE pc=${frame.pc - 1} fromRegister=${word.a} '
                  'toBeClosed=${frame._toBeClosedRegisters.toList()..sort()}',
                );
              }
              if (!frame.hasCloseWorkFrom(word.a)) {
                break;
              }
              try {
                await _closeFrameForCoroutine(
                  frame,
                  fromRegister: word.a,
                  error: null,
                );
              } on YieldException catch (error) {
                _suspendClose(frame, word.a, error);
              }
              break;
            }
          case Opcode.extraArg:
            {
              throw LuaError(
                _opcodeDiagnostic(
                  frame,
                  opcode.luaName,
                  detail: 'unexpected EXTRAARG without a consuming opcode',
                ),
              );
            }
          case Opcode.errNNil:
            {
              if (!isLuaNilSlot(frame.register(word.a))) {
                throw LuaError('attempt to use a nil value');
              }
              break;
            }
        }

        if (hasDebugHook && deferCountHook) {
          _syncDebugLocals(frame);
          await debugInterpreter!.maybeFireCountDebugHook();
        }
        frame.openTop = nextOpenTop;
      } finally {
        if (opTimer != null) {
          opTimer.stop();
          profile!.record(opcode.luaName, opTimer.elapsedMicroseconds);
        }
      }
    }

    await _closeFrameForCoroutine(frame, error: null);
    return const <Value>[];
  }

  void _syncDebugLocals(
    _LuaBytecodeFrame frame, {
    CallFrame? callFrame,
    int? currentPc,
  }) {
    final targetCallFrame = callFrame ?? runtime.callStack.top;
    if (targetCallFrame == null) {
      return;
    }
    final effectivePc = currentPc ?? (frame.pc == 0 ? 1 : frame.pc);
    if (identical(targetCallFrame.debugLocalsOwner, frame) &&
        targetCallFrame.debugLocalsPc == effectivePc &&
        targetCallFrame.debugLocalsVersion == frame.debugStateVersion) {
      return;
    }
    targetCallFrame.debugLocals
      ..clear()
      ..addAll(_activeBytecodeDebugLocals(frame, currentPc: effectivePc));
    targetCallFrame.debugLocalsOwner = frame;
    targetCallFrame.debugLocalsPc = effectivePc;
    targetCallFrame.debugLocalsVersion = frame.debugStateVersion;
  }

  void _syncCallFrameDebugLocals(CallFrame? callFrame) {
    if (callFrame == null) {
      return;
    }
    if (_bytecodeFrameForCallFrame(callFrame) case final bytecodeFrame?) {
      // A caller paused in a nested call has already advanced its PC to the
      // instruction after the call. Debug locals should still reflect the
      // call-site window, so resync against `pc - 1` to keep generic-for
      // state and to-be-closed aliases visible while helpers inspect them.
      //
      // Closed bytecode frames are the opposite case: they remain on the stack
      // only long enough for a pending `return` hook, and Lua still expects the
      // return-scope locals to be visible there. Those ranges are keyed to the
      // current 1-based PC, so keep the advanced PC once the frame is closed.
      _syncDebugLocals(
        bytecodeFrame,
        callFrame: callFrame,
        currentPc: bytecodeFrame.closed
            ? (bytecodeFrame.pc == 0 ? 1 : bytecodeFrame.pc)
            : (bytecodeFrame.pc <= 1 ? 1 : bytecodeFrame.pc - 1),
      );
    }
  }

  void _bindCallerFrameForDebugInspection(_LuaBytecodeFrame? callerFrame) {
    if (callerFrame == null) {
      return;
    }
    final callerCallFrame = runtime.callStack.top;
    if (callerCallFrame == null) {
      return;
    }
    _bindBytecodeCallFrame(callerCallFrame, callerFrame);
  }

  List<MapEntry<String, Value>> _activeBytecodeDebugLocals(
    _LuaBytecodeFrame frame, {
    int? currentPc,
  }) {
    currentPc ??= frame.pc == 0 ? 1 : frame.pc;
    final activeWindow = frame.activeDebugLocalWindowAt(currentPc);
    final activeLocals = activeWindow.locals;
    final activeRegisters = activeWindow.registers;
    final varargTableRegister = frame.closure.prototype.needsVarargTable
        ? frame.closure.prototype.parameterCount
        : null;
    return <MapEntry<String, Value>>[
      for (final local in activeLocals)
        if (local.register case final register?)
          MapEntry(local.name ?? '(local)', frame.register(register)),
      for (var register = 0; register < frame.effectiveTop; register++)
        if (!activeRegisters.contains(register) &&
            register != varargTableRegister &&
            _isVisibleTemporaryRegister(frame, register, currentPc))
          MapEntry('(temporary)', frame.register(register)),
    ];
  }

  bool _isVisibleTemporaryRegister(
    _LuaBytecodeFrame frame,
    int register,
    int currentPc,
  ) {
    final value = frame.register(register);
    if (rawLuaSlot(value) == null) {
      return false;
    }
    if (_isPendingCallResultRegister(frame, register, currentPc)) {
      return false;
    }
    if (_isPendingCallSetupRegister(frame, register, currentPc)) {
      return false;
    }

    final prototype = frame.closure.prototype;
    for (var pc = currentPc; pc < prototype.code.length; pc++) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      final reads = _instructionReadsRegisterByOpcodeValue(
        word,
        opcodeValue,
        register,
      );
      final writes = _instructionWritesRegisterByOpcodeValue(
        word,
        opcodeValue,
        register,
      );
      if (reads) {
        return true;
      }
      if (writes) {
        return false;
      }
    }
    return false;
  }

  /// Hide the callee/argument window for a call that is currently suspended.
  ///
  /// When `debug.getlocal` inspects a caller paused inside a nested call, Lua
  /// exposes temporaries that remain live after the call site, but not the
  /// transient registers used to stage the active CALL/TAILCALL/TFORCALL.
  /// Without this filter the bytecode path leaks the callee function itself as
  /// an extra `(temporary)` local in cases like `return (a + 1) + f()`.
  bool _isPendingCallSetupRegister(
    _LuaBytecodeFrame frame,
    int register,
    int currentPc,
  ) {
    if (currentPc < 0 || currentPc >= frame.closure.prototype.code.length) {
      return false;
    }
    final word = frame.closure.prototype.code[currentPc];
    return switch (word.opcode) {
      Opcode.call || Opcode.tailCall => switch (word.b) {
        0 => register >= word.a,
        _ => register >= word.a && register < word.a + word.b,
      },
      Opcode.tForCall => switch (word.c) {
        0 => register >= word.a,
        _ => register >= word.a && register < word.a + word.c + 1,
      },
      _ => false,
    };
  }

  bool _isPendingCallResultRegister(
    _LuaBytecodeFrame frame,
    int register,
    int currentPc,
  ) {
    if (currentPc <= 0) {
      return false;
    }
    final previous = frame.closure.prototype.code[currentPc - 1];
    if (previous.opcode != Opcode.call) {
      return false;
    }
    final base = previous.a;
    final resultCount = previous.c;
    if (resultCount == 0) {
      return register >= base;
    }
    return register >= base && register < base + (resultCount - 1);
  }

  bool _instructionReadsRegisterByOpcodeValue(
    LuaBytecodeInstructionWord word,
    Opcode opcodeValue,
    int register,
  ) {
    return word.readsRegister(register);
  }

  bool _deferCountHookForOpcode(Opcode opcode) {
    return opcode.defersCountHook;
  }


  Coroutine? _syncCurrentCoroutine(Coroutine mainThread, Coroutine? current) {
    if (Coroutine.active case final active?) {
      if (active.status == CoroutineStatus.normal) {
        active.status = CoroutineStatus.running;
      }
      if (!identical(current, active)) {
        runtime.setCurrentCoroutine(active);
      }
      return active;
    }

    if (current != null) {
      if (!identical(current, mainThread)) {
        return current;
      }
      return current;
    }

    runtime.setCurrentCoroutine(mainThread);
    return mainThread;
  }

  LuaBytecodeClosure _createClosure(
    _LuaBytecodeFrame frame,
    LuaBytecodePrototype prototype,
  ) {
    final upvalues = <_LuaBytecodeUpvalue>[
      for (final descriptor in prototype.upvalues)
        descriptor.inStack
            ? frame.captureUpvalue(descriptor.index)
            : frame.closure._upvalues[descriptor.index],
    ];
    return LuaBytecodeClosure._(
      runtime: runtime,
      prototype: prototype,
      chunkName: frame.closure.chunkName,
      environment: frame.closure.environment,
      upvalues: upvalues,
    );
  }

  void _executeBinaryInstruction(
    _LuaBytecodeFrame frame, {
    required int targetRegister,
    required Value left,
    required Value right,
    int? leftRegister,
    int? rightRegister,
    required _LuaBinaryOperation operation,
  }) {
    final fastPath = _tryBinaryFastPath(operation, left, right);
    if (fastPath != null) {
      frame.setRegister(targetRegister, fastPath);
      _skipBinaryMetamethodFollowup(frame);
      return;
    }

    if (_hasBinaryMetamethodFollowup(frame)) {
      return;
    }

    try {
      frame.setRegister(
        targetRegister,
        _forceBinaryOperation(operation, left, right),
      );
    } on LuaError catch (error) {
      throw _rewriteBinaryOperandError(frame, left, right, error);
    }
  }

  Future<Value> _executeUnaryInstruction(
    _LuaBytecodeFrame frame,
    Value operand, {
    int? operandRegister,
    required String metamethod,
    required Value? Function(Value operand) fastPath,
  }) async {
    final direct = fastPath(operand);
    if (direct != null) {
      return direct;
    }

    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      operand,
      operand,
    );
    if (metamethodResult != null) {
      return metamethodResult;
    }

    try {
      final rawOperand = rawLuaSlot(operand);
      return switch (metamethod) {
        '__unm' => _runtimeValue(runtime, NumberUtils.negate(rawOperand)),
        '__bnot' => _runtimeValue(runtime, NumberUtils.bitwiseNot(rawOperand)),
        '__len' => _runtimeValue(runtime, _lengthOf(operand)),
        _ => throw LuaError('unsupported unary metamethod $metamethod'),
      };
    } on LuaError catch (error) {
      final message = error.message;
      final shouldRewriteUnary =
          metamethod == '__unm' &&
          (message.startsWith('Unary negation not supported for type ') ||
              message.startsWith('attempt to perform arithmetic on a '));
      if (!shouldRewriteUnary) {
        rethrow;
      }
      final label =
          _registerSourceLabel(frame, operandRegister) ??
          _valueSourceLabel(frame, operand);
      final type = getLuaType(operand);
      final rewritten = label != null
          ? "attempt to perform arithmetic on $label (a $type value)"
          : "attempt to perform arithmetic on a $type value";
      throw LuaError(
        rewritten,
        cause: error.cause,
        stackTrace: error.stackTrace,
        luaStackTrace: error.luaStackTrace,
        suppressAutomaticLocation: error.suppressAutomaticLocation,
      );
    } catch (_) {
      if (metamethod != '__unm' && metamethod != '__bnot') {
        rethrow;
      }
      final label =
          _registerSourceLabel(frame, operandRegister) ??
          _valueSourceLabel(frame, operand);
      final message = label != null
          ? "attempt to perform arithmetic on $label (a ${getLuaType(operand)} value)"
          : "attempt to perform arithmetic on a ${getLuaType(operand)} value";
      throw LuaError(message);
    }
  }

  Future<Value> _executeConcatInstruction(
    _LuaBytecodeFrame frame,
    int startRegister,
    int operandCount,
  ) async {
    return _continueConcatInstruction(
      frame,
      startRegister: startRegister,
      nextOffset: operandCount - 2,
      current: frame.register(startRegister + operandCount - 1),
    );
  }

  Future<Value> _continueConcatInstruction(
    _LuaBytecodeFrame frame, {
    required int startRegister,
    required int nextOffset,
    required Value current,
  }) async {
    for (var offset = nextOffset; offset >= 0; offset--) {
      final next = frame.register(startRegister + offset);
      final fastPath = _tryBinaryFastPath(
        _LuaBinaryOperation.concat,
        next,
        current,
      );
      if (fastPath != null) {
        current = fastPath;
        continue;
      }

      Value? metamethodResult;
      try {
        metamethodResult = await _invokeBinaryMetamethod(
          '__concat',
          next,
          current,
        );
      } on YieldException catch (error) {
        // Match luaV_finishOp(OP_CONCAT): once the yielded metamethod returns,
        // resume from the remaining left-hand operands instead of treating the
        // partial result as the instruction's final value.
        _suspendConcat(frame, startRegister, offset - 1, error);
      }
      if (metamethodResult != null) {
        current = metamethodResult;
        continue;
      }

      current = _forceBinaryOperation(
        _LuaBinaryOperation.concat,
        next,
        current,
      );
    }
    return current;
  }

  Future<Value> _executeMetamethodBinaryInstruction(
    _LuaBytecodeFrame frame, {
    required String metamethod,
    required Value left,
    required Value right,
  }) async {
    final (leftLabel, rightLabel) =
        _binaryOperandSourceLabelsForPreviousInstruction(frame);
    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      left,
      right,
    );
    if (metamethodResult != null) {
      return metamethodResult;
    }

    try {
      return _forceBinaryOperation(
        _binaryOperationForMetamethod(metamethod),
        left,
        right,
      );
    } on LuaError catch (error) {
      throw _rewriteBinaryOperandError(
        frame,
        left,
        right,
        error,
        leftLabel: leftLabel,
        rightLabel: rightLabel,
      );
    }
  }

  Value? _tryBinaryFastPath(
    _LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (!_canFastPathBinaryOperation(operation, left, right)) {
      return null;
    }
    return _forceFastBinaryOperation(operation, left, right);
  }

  Value _forceFastBinaryOperation(
    _LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return _runtimeValue(runtime, left.concat(right));
    }
    final leftRaw = rawLuaSlot(left);
    final rightRaw = rawLuaSlot(right);
    final rawResult = switch (operation) {
      _LuaBinaryOperation.add => NumberUtils.add(leftRaw, rightRaw),
      _LuaBinaryOperation.sub => NumberUtils.subtract(leftRaw, rightRaw),
      _LuaBinaryOperation.mul => NumberUtils.multiply(leftRaw, rightRaw),
      _LuaBinaryOperation.mod => NumberUtils.modulo(leftRaw, rightRaw),
      _LuaBinaryOperation.pow => NumberUtils.exponentiate(leftRaw, rightRaw),
      _LuaBinaryOperation.div => NumberUtils.divide(leftRaw, rightRaw),
      _LuaBinaryOperation.idiv => NumberUtils.floorDivide(leftRaw, rightRaw),
      _LuaBinaryOperation.band => NumberUtils.bitwiseAnd(leftRaw, rightRaw),
      _LuaBinaryOperation.bor => NumberUtils.bitwiseOr(leftRaw, rightRaw),
      _LuaBinaryOperation.bxor => NumberUtils.bitwiseXor(leftRaw, rightRaw),
      _LuaBinaryOperation.shl => NumberUtils.leftShift(leftRaw, rightRaw),
      _LuaBinaryOperation.shr => NumberUtils.rightShift(leftRaw, rightRaw),
      _LuaBinaryOperation.concat => left.concat(right),
    };
    return _runtimeValue(runtime, rawResult);
  }

  Value _forceBinaryOperation(
    _LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return _runtimeValue(runtime, left.concat(right));
    }
    return _runtimeValue(
      runtime,
      NumberUtils.performArithmetic(
        operation.operatorSymbol,
        rawLuaSlot(left),
        rawLuaSlot(right),
      ),
    );
  }

  bool _canFastPathBinaryOperation(
    _LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return _canFastPathConcat(left) && _canFastPathConcat(right);
    }
    if (operation.integerOnly) {
      return _canFastPathInteger(left) && _canFastPathInteger(right);
    }
    return _canFastPathNumeric(left) && _canFastPathNumeric(right);
  }

  bool _hasBinaryMetamethodFollowup(_LuaBytecodeFrame frame) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      return false;
    }
    return switch (frame.closure.prototype.code[frame.pc].opcode) {
      Opcode.mmBin || Opcode.mmBinI || Opcode.mmBinK => true,
      _ => false,
    };
  }

  void _skipBinaryMetamethodFollowup(_LuaBytecodeFrame frame) {
    if (_hasBinaryMetamethodFollowup(frame)) {
      frame.pc += 1;
    }
  }

  LuaBytecodeInstructionWord _previousInstruction(_LuaBytecodeFrame frame) {
    final index = frame.pc - 2;
    if (index < 0 || index >= frame.closure.prototype.code.length) {
      throw LuaError(
        _opcodeDiagnostic(
          frame,
          'MMBIN*',
          detail: 'missing arithmetic instruction before metamethod fallback',
        ),
      );
    }
    return frame.closure.prototype.code[index];
  }

  Future<Value?> _invokeBinaryMetamethod(
    String metamethod,
    Value left,
    Value right,
  ) async {
    return await _callBinaryMetamethodOn(metamethod, left, left, right) ??
        await _callBinaryMetamethodOn(metamethod, right, left, right);
  }

  Future<Value?> _callBinaryMetamethodOn(
    String metamethod,
    Value receiver,
    Value left,
    Value right,
  ) async {
    if (!receiver.hasMetamethod(metamethod)) {
      return null;
    }

    final result = await (() async {
      try {
        return await receiver.callMetamethodAsync(metamethod, <Value>[
          left,
          right,
        ]);
      } catch (error) {
        if (!error.toString().contains('attempt to call a non-function')) {
          rethrow;
        }
        final method = receiver.getMetamethod(metamethod);
        final methodName = metamethod.startsWith('__')
            ? metamethod.substring(2)
            : metamethod;
        throw LuaError(
          "attempt to call a ${getLuaType(method)} value (metamethod '$methodName')",
        );
      }
    })();
    final value = _firstResultValue(runtime, result);
    return value;
  }

  Future<void> _preserveSuspendingBytecodeBoundary({
    required Coroutine? currentCoroutine,
    required Coroutine mainThread,
  }) async {
    if (_debugInterpreter?.debugHookFunction != null) {
      return;
    }
    if (currentCoroutine != null && !identical(currentCoroutine, mainThread)) {
      // Non-main coroutines still rely on the legacy per-opcode async split to
      // preserve suspended expression state across yield/resume hops. Keep that
      // broader boundary only there so hot main-thread loops stay fast.
      await Future<void>.value();
      return;
    }
    // Yield-sensitive bytecode opcodes relied on the old per-opcode hook awaits
    // to create an async boundary before entering resumable metamethod logic.
    // Preserve that boundary only for opcodes that can suspend through
    // metamethod/table fallback instead of paying it on every instruction.
    await Future<void>.value();
  }

  bool _needsSuspendingOpcodeBoundaryForInstruction(
    _LuaBytecodeFrame frame,
    Opcode opcode,
    LuaBytecodeInstructionWord word,
  ) {
    if (!_needsSuspendingOpcodeBoundary(opcode)) {
      return false;
    }
    return switch (opcode) {
      Opcode.call || Opcode.tailCall => !_canSkipSuspendingBoundaryForCall(frame, word.a),
      Opcode.eq => !_canSkipSuspendingBoundaryForEquality(
        frame.register(word.a),
        frame.register(word.b),
      ),
      Opcode.lt || Opcode.le => !_canSkipSuspendingBoundaryForOrdering(
        frame.register(word.a),
        frame.register(word.b),
        primitiveCompare: opcode == Opcode.lt
            ? _PrimitiveCompare.lessThan
            : _PrimitiveCompare.lessThanOrEqual,
      ),
      Opcode.ltI || Opcode.leI || Opcode.gtI || Opcode.geI =>
        !_canSkipSuspendingBoundaryForImmediateOrdering(
          frame.register(word.a),
          _signedB(word),
          primitiveCompare: switch (opcode) {
            Opcode.ltI => _PrimitiveCompare.lessThan,
            Opcode.leI => _PrimitiveCompare.lessThanOrEqual,
            Opcode.gtI => _PrimitiveCompare.greaterThan,
            Opcode.geI => _PrimitiveCompare.greaterThanOrEqual,
            _ => throw StateError('unreachable opcode $opcode'),
          },
        ),
      Opcode.unm => !_canSkipSuspendingBoundaryForUnary(
        frame.register(word.b),
        '__unm',
      ),
      Opcode.bnot => !_canSkipSuspendingBoundaryForUnary(
        frame.register(word.b),
        '__bnot',
      ),
      Opcode.len => !_canSkipSuspendingBoundaryForUnary(
        frame.register(word.b),
        '__len',
      ),
      Opcode.getTabUp => !_canSkipSuspendingBoundaryForTableGet(
        frame.closure._upvalues[word.b].read(),
        rawStringKey: _stringConstantRaw(frame.closure.prototype, word.c),
      ),
      Opcode.getTable || Opcode.getI || Opcode.getField =>
        !_canSkipSuspendingBoundaryForTableGet(
          frame.register(word.b),
          key: switch (opcode) {
            Opcode.getTable => frame.register(word.c),
            Opcode.getI => runtime.constantPrimitiveValue(word.c),
            _ => null,
          },
          rawStringKey: switch (opcode) {
            Opcode.getField => _stringConstantRaw(
              frame.closure.prototype,
              word.c,
            ),
            _ => null,
          },
        ),
      Opcode.setTabUp => !_canSkipSuspendingBoundaryForTableSet(
        frame.closure._upvalues[word.a].read(),
      ),
      Opcode.setTable || Opcode.setI || Opcode.setField =>
        !_canSkipSuspendingBoundaryForTableSet(frame.register(word.a)),
      Opcode.close => word.b == 0 && frame.hasCloseWorkFrom(word.a),
      Opcode.return_ || Opcode.return0 || Opcode.return1 =>
        frame.hasCloseWorkFrom(0),
      _ => true,
    };
  }

  bool _needsSuspendingOpcodeBoundary(Opcode opcode) {
    return opcode.needsSuspendingBoundary;
  }


  bool _canSkipSuspendingBoundaryForCall(
    _LuaBytecodeFrame frame,
    int calleeRegister,
  ) {
    final callee = frame.register(calleeRegister);
    final raw = rawLuaSlot(callee);
    return raw is BuiltinFunction && _canInlineBuiltinWithoutManagedFrame(raw);
  }

  bool _canSkipSuspendingBoundaryForTableGet(
    Value table, {
    Value? key,
    String? rawStringKey,
  }) {
    final rawTable = rawLuaSlot(table);
    final hasWeakMode = table.tableWeakMode != null;
    if (rawStringKey != null &&
        _canFastPathGlobalProxyTableGetStringKey(table, rawStringKey)) {
      return true;
    }
    if (key != null && _canFastPathGlobalProxyTableGet(table, key)) {
      return true;
    }
    return (rawTable is TableStorage || rawTable is Map) &&
        !hasWeakMode &&
        !table.hasMetamethod('__index');
  }

  bool _canSkipSuspendingBoundaryForEquality(Value left, Value right) {
    if (_rawEquals(left, right)) {
      return true;
    }
    if (!_supportsEqualityMetamethod(left, right)) {
      return true;
    }
    return !left.hasMetamethod('__eq') && !right.hasMetamethod('__eq');
  }

  bool _canSkipSuspendingBoundaryForOrdering(
    Value left,
    Value right, {
    required _PrimitiveCompare primitiveCompare,
  }) {
    return _tryPrimitiveOrdering(left, right, primitiveCompare) != null;
  }

  bool _canSkipSuspendingBoundaryForImmediateOrdering(
    Value left,
    int right, {
    required _PrimitiveCompare primitiveCompare,
  }) {
    return _tryPrimitiveImmediateOrdering(left, right, primitiveCompare) !=
        null;
  }

  bool _canSkipSuspendingBoundaryForUnary(Value operand, String metamethod) {
    return switch (metamethod) {
      '__unm' => _canFastPathNumeric(operand),
      '__bnot' => _canFastPathInteger(operand),
      '__len' => _canFastPathLength(operand),
      _ => false,
    };
  }

  bool _canSkipSuspendingBoundaryForTableSet(Value table) {
    final rawTable = rawLuaSlot(table);
    final hasWeakMode = table.tableWeakMode != null;
    return (rawTable is TableStorage || rawTable is Map) &&
        !hasWeakMode &&
        !table.hasMetamethod('__newindex') &&
        !table.hasMetamethod('__index');
  }

  String _opcodeDiagnostic(
    _LuaBytecodeFrame frame,
    String opcodeName, {
    String? detail,
  }) {
    final pc = frame.pc - 1;
    final prototype = frame.closure.prototype;
    final location = <String>['pc $pc'];
    final line = prototype.lineForPc(pc);
    if (line != null) {
      location.add('line $line');
    }
    final source = prototype.source ?? frame.closure.chunkName;
    if (source.isNotEmpty) {
      location.add(source);
    }
    final suffix = detail == null ? '' : ': $detail';
    return 'unsupported lua_bytecode opcode $opcodeName '
        '(${location.join(', ')})$suffix';
  }

  ({Value callee, List<Value> args}) _resolveCall(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) {
    final callee = frame.register(word.a);
    final args = _callArgsFromFrame(frame, word);
    return (callee: callee, args: args);
  }

  List<Value> _callArgsFromFrame(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) {
    final start = word.a + 1;
    final count = word.b == 0 ? frame.effectiveTop - start : word.b - 1;
    return frame.resultsFrom(start, count);
  }

  Future<List<Value>> _callAt(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) async {
    final call = _resolveCall(frame, word);
    if (_debugInterpreter?.debugHookFunction == null) {
      final rawCallee = rawLuaSlot(call.callee);
      if (rawCallee is BuiltinFunction &&
          _canInlineBuiltinWithoutManagedFrame(rawCallee) &&
          !(runtime.isInProtectedCall && rawCallee.isBytecodeAssertBuiltin)) {
        return _invokePreparedCall(call, frame: frame);
      }
    }
    final nameInfo = _callSiteNameInfo(frame, word.a, call.callee);
    return _invokePreparedCall(
      call,
      frame: frame,
      callName: nameInfo.name,
      callNameWhat: nameInfo.namewhat,
    );
  }

  Future<List<Value>> _invokePreparedCall(
    ({Value callee, List<Value> args}) call, {
    _LuaBytecodeFrame? frame,
    String opcodeName = 'CALL',
    String? callName,
    String? callNameWhat,
    bool isTailCall = false,
  }) async {
    try {
      if (frame != null && _debugInterpreter?.debugHookFunction != null) {
        _syncDebugLocals(frame);
      }
      return await _invokeValueWithName(
        call.callee,
        call.args,
        callName: callName,
        callNameWhat: callNameWhat,
        callerFrame: frame,
        isTailCall: isTailCall,
      );
    } on LuaError catch (error) {
      // Preserve callee-thrown Lua errors, but stamp bytecode call-site line
      // information onto raw call-type errors so protected-call packaging
      // reports the CALL instruction line instead of falling back later.
      final callerLine = _callSiteLine(frame);
      if (callerLine != null &&
          callerLine > 0 &&
          error.lineNumber == null &&
          !error.suppressAutomaticLocation &&
          _isCallTypeErrorMessage(error.message)) {
        throw LuaError(
          error.message,
          span: error.span,
          node: error.node,
          cause: error.cause,
          stackTrace: error.stackTrace,
          luaStackTrace: error.luaStackTrace,
          suppressAutomaticLocation: error.suppressAutomaticLocation,
          suppressProtectedCallLocation: error.suppressProtectedCallLocation,
          lineNumber: callerLine,
          hasBeenReported: error.hasBeenReported,
        );
      }
      rethrow;
    } on Exception catch (error) {
      if (error.toString().contains('attempt to call a non-function value')) {
        final targetLabel = switch ((callName, callNameWhat)) {
          (final String name, final String namewhat) when namewhat.isNotEmpty =>
            "$namewhat '$name'",
          (final String label, _) when label.contains("'") => label,
          _ => null,
        };
        final type = getLuaType(call.callee);
        final message = targetLabel != null
            ? "attempt to call $targetLabel (a $type value)"
            : "attempt to call a $type value";
        throw LuaError(message, lineNumber: _callSiteLine(frame));
      }
      rethrow;
    }
  }

  int? _callSiteLine(_LuaBytecodeFrame? frame) => switch (frame) {
    final _LuaBytecodeFrame caller when caller.pc > 0 =>
      caller.closure.prototype.lineForPc(caller.pc - 1),
    _ => null,
  };

  bool _isCallTypeErrorMessage(String message) =>
      message.startsWith('attempt to call ') ||
      message.contains("attempt to call a ");

  Never _suspendConditionalJump(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeConditionalJumpSuspension(
        vm: this,
        frame: frame,
        word: word,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendStoreRegister(
    _LuaBytecodeFrame frame,
    int register,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeStoreRegisterSuspension(
        vm: this,
        frame: frame,
        register: register,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendConcat(
    _LuaBytecodeFrame frame,
    int startRegister,
    int nextOffset,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeConcatSuspension(
        vm: this,
        frame: frame,
        startRegister: startRegister,
        nextOffset: nextOffset,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendResumeOnly(_LuaBytecodeFrame frame, YieldException error) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeResumeOnlySuspension(
        vm: this,
        frame: frame,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendCall(
    _LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _tmpDebugFrame(
      frame,
      'suspend-call register=$register resultSpec=$resultSpec child=${child.runtimeType} pc=${frame.pc}',
    );
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeCallSuspension(
        vm: this,
        frame: frame,
        register: register,
        resultSpec: resultSpec,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendTailCall(_LuaBytecodeFrame frame, YieldException error) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _tmpDebugFrame(
      frame,
      'suspend-tailcall child=${child.runtimeType} pc=${frame.pc}',
    );
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeTailCallSuspension(
        vm: this,
        frame: frame,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendTForCall(
    _LuaBytecodeFrame frame,
    int base,
    int resultCount,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeTForCallSuspension(
        vm: this,
        frame: frame,
        base: base,
        resultCount: resultCount,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendClose(
    _LuaBytecodeFrame frame,
    int fromRegister,
    YieldException error,
  ) {
    frame.pc--;
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeCloseSuspension(
        vm: this,
        frame: frame,
        fromRegister: fromRegister,
        savedTop: frame.top,
        savedOpenTop: frame.openTop,
        resumeInProtectedCall: runtime.isInProtectedCall,
        pendingError: null,
        pendingErrorStackTrace: null,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendErrorClose(
    _LuaBytecodeFrame frame,
    Object errorObject,
    StackTrace errorStackTrace,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _tmpDebugFrame(
      frame,
      'suspend-error-close values=${error.values} child=${child.runtimeType} pc=${frame.pc}',
    );
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeCloseSuspension(
        vm: this,
        frame: frame,
        fromRegister: 0,
        savedTop: frame.top,
        savedOpenTop: frame.openTop,
        resumeInProtectedCall: runtime.isInProtectedCall,
        pendingError: _preserveCloseErrorObject(runtime, errorObject),
        pendingErrorStackTrace: errorStackTrace,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendReturn(
    _LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    YieldException error,
  ) {
    frame.pc--;
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _tmpDebugFrame(
      frame,
      'suspend-return register=$register resultSpec=$resultSpec child=${child.runtimeType} '
      'top=${frame.top} openTop=${frame.openTop} pc=${frame.pc}',
    );
    _installBytecodeContinuation(
      coroutine,
      _LuaBytecodeReturnSuspension(
        vm: this,
        frame: frame,
        register: register,
        resultSpec: resultSpec,
        savedTop: frame.top,
        savedOpenTop: frame.openTop,
        resumeInProtectedCall: runtime.isInProtectedCall,
        pendingError: null,
        pendingErrorStackTrace: null,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Coroutine _requireCoroutineForYield(
    _LuaBytecodeFrame frame,
    YieldException error,
  ) {
    final coroutine = error.coroutine ?? runtime.getCurrentCoroutine();
    if (coroutine != null) {
      return coroutine;
    }
    throw LuaError(
      _opcodeDiagnostic(
        frame,
        'YIELD',
        detail: 'attempt to yield without an active coroutine',
      ),
    );
  }

  Future<List<Value>> _invokeValueWithName(
    Value callee,
    List<Value> args, {
    String? callName,
    String? callNameWhat,
    int extraArgs = 0,
    _LuaBytecodeFrame? callerFrame,
    bool isTailCall = false,
  }) async {
    final prepared = _flattenTailCallable(callee, args);
    callee = prepared.callee;
    args = prepared.args;
    extraArgs += prepared.extraArgs;
    if (_debugInterpreter?.debugHookFunction == null) {
      final rawCallee = rawLuaSlot(callee);
      if (rawCallee is BuiltinFunction &&
          _canInlineBuiltinWithoutManagedFrame(rawCallee) &&
          !(runtime.isInProtectedCall && rawCallee.isBytecodeAssertBuiltin)) {
        return _invokeInlineBuiltin(callee, args, builtin: rawCallee);
      }
    }
    if (callerFrame case final parentBytecodeFrame?) {
      final callerCallFrame = runtime.callStack.top;
      if (callerCallFrame != null) {
        // Coroutine resume restores cloned CallFrame objects. Before any
        // nested bytecode call, reattach the live bytecode frame so traceback
        // and hook stack walks see current registers/PC rather than state
        // snapshotted at the last yield point.
        _bindBytecodeCallFrame(callerCallFrame, parentBytecodeFrame);
        _syncDebugLocals(parentBytecodeFrame, callFrame: callerCallFrame);
      }
    }
    // `debug.getlocal` / `debug.setlocal` need the paused caller's live local
    // window, not just whatever snapshot the shared debug library last saw on
    // the stack. Keep the bytecode-specific path so we can resync the caller
    // frame against the exact paused PC before delegating to the builtin.
    final debugLocalHandled = _tryHandleDebugLocalBuiltin(
      callee,
      args,
      callName: callName,
      callNameWhat: callNameWhat,
      extraArgs: extraArgs,
      callerFrame: callerFrame,
    );
    final debugLocalResult = debugLocalHandled is Future<List<Value>?>
        ? await debugLocalHandled
        : debugLocalHandled;
    if (debugLocalResult != null) {
      return debugLocalResult;
    }
    final protectedCallHandled = _tryHandleProtectedCallBuiltin(
      callee,
      args,
      callName: callName,
      callNameWhat: callNameWhat,
      extraArgs: extraArgs,
      callerFrame: callerFrame,
    );
    final protectedCallResult = protectedCallHandled is Future<List<Value>?>
        ? await protectedCallHandled
        : protectedCallHandled;
    if (protectedCallResult != null) {
      return protectedCallResult;
    }
    if (rawLuaSlot(callee) case final LuaBytecodeClosure closure) {
      return invoke(
        closure,
        args,
        functionValue: callee,
        callName: callName ?? _callableName(callee),
        callNameWhat: callNameWhat,
        isTailCall: isTailCall,
        extraArgs: extraArgs,
      );
    }
    if (callerFrame != null) {
      final callerLine = callerFrame.closure.prototype.lineForPc(
        callerFrame.pc - 1,
      );
      if (callerLine != null) {
        runtime.callStack.top?.currentLine = callerLine;
      }
    }
    args = _rewriteCoroutineFactoryArgs(
      callee,
      args,
      callName: callName,
      callNameWhat: callNameWhat,
    );
    _guardCallDepth();
    runtime.callStack.push(
      callName ?? _callableName(callee),
      callNode: _syntheticCallNode(callName, callNameWhat),
      env: runtime.getCurrentEnv(),
      debugName: callName,
      debugNameWhat: callNameWhat ?? '',
      callable: callee,
    );
    runtime.callStack.top?.isTailCall = isTailCall;
    runtime.callStack.top?.extraArgs = extraArgs;
    final callDebugInterpreter = _debugInterpreter;
    if (callDebugInterpreter != null) {
      _setTransferInfo(runtime.callStack.top, args);
      final interpreter = callDebugInterpreter;
      await interpreter.fireDebugHook('call');
      _clearTransferInfo(runtime.callStack.top);
    }
    Iterable<Value> tempRootProvider() sync* {
      yield callee;
      for (final arg in args) {
        yield arg;
      }
    }

    runtime.pushExternalGcRoots(tempRootProvider);
    final yieldableAtCallEntry = runtime.isYieldable;
    List<Value> returnTransferValues = const <Value>[];
    try {
      final result = await runtime.callFunction(callee, args);
      final normalized = _normalizeResults(result);
      returnTransferValues = normalized;
      return normalized;
    } on CoroutineCloseSignal catch (signal) {
      _closeSignalYieldableStates[signal] =
          (_closeSignalYieldableStates[signal] ?? true) && yieldableAtCallEntry;
      rethrow;
    } finally {
      final returnDebugInterpreter = _debugInterpreter;
      if (returnDebugInterpreter != null) {
        final topFrame = runtime.callStack.top;
        if (topFrame != null) {
          _setTransferInfo(topFrame, returnTransferValues);
        }
        final interpreter = returnDebugInterpreter;
        await interpreter.fireDebugHook('return');
        _clearTransferInfo(topFrame);
      }
      runtime.popExternalGcRoots(tempRootProvider);
      runtime.callStack.pop();
    }
  }

  /// Only inline synchronous math builtins here.
  ///
  /// The bytecode suite spends a disproportionate amount of time in
  /// `math.random`/`math.max`/`math.min` call churn. Skipping the managed
  /// call-stack frame is safe when no debug hook is installed and avoids
  /// paying per-call push/pop overhead in those loops.
  bool _canInlineBuiltinWithoutManagedFrame(BuiltinFunction builtin) {
    return builtin.canBytecodeInlineWithoutManagedFrame &&
        !builtin.isBytecodeAssertBuiltin;
  }

  /// Invokes a bytecode-approved builtin while still rooting the callee and
  /// arguments for GC visibility.
  FutureOr<List<Value>> _invokeInlineBuiltin(
    Value callee,
    List<Value> args, {
    required BuiltinFunction builtin,
  }) {
    if (!runtime.gc.isCycleActive) {
      return _normalizeResults(builtin.call(args));
    }

    Iterable<Value> tempRootProvider() sync* {
      yield callee;
      for (final arg in args) {
        yield arg;
      }
    }

    runtime.pushExternalGcRoots(tempRootProvider);
    try {
      final result = builtin.call(args);
      if (result is Future) {
        return result
            .then<List<Value>>((value) => _normalizeResults(value))
            .whenComplete(() {
              runtime.popExternalGcRoots(tempRootProvider);
            });
      }
      final normalized = _normalizeResults(result);
      runtime.popExternalGcRoots(tempRootProvider);
      return normalized;
    } catch (_) {
      runtime.popExternalGcRoots(tempRootProvider);
      rethrow;
    }
  }

  FutureOr<List<Value>> _invokeInlineBuiltinFromFrame(
    Value callee,
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word, {
    required BuiltinFunction builtin,
  }) {
    final args = _LuaBytecodeFrameArgsView(
      frame,
      start: word.a + 1,
      count: word.b == 0 ? frame.effectiveTop - (word.a + 1) : word.b - 1,
    );
    if (!runtime.gc.isCycleActive) {
      return _normalizeResults(builtin.call(args));
    }

    Iterable<Value> tempRootProvider() sync* {
      yield callee;
      yield* args.gcRoots;
    }

    runtime.pushExternalGcRoots(tempRootProvider);
    try {
      final result = builtin.call(args);
      if (result is Future) {
        return result
            .then<List<Value>>((value) => _normalizeResults(value))
            .whenComplete(() {
              runtime.popExternalGcRoots(tempRootProvider);
            });
      }
      final normalized = _normalizeResults(result);
      runtime.popExternalGcRoots(tempRootProvider);
      return normalized;
    } catch (_) {
      runtime.popExternalGcRoots(tempRootProvider);
      rethrow;
    }
  }

  Object? _tryStoreInlineAssertSuccess(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word, {
    required BuiltinFunction builtin,
  }) {
    if (!builtin.isBytecodeAssertBuiltin) {
      return _inlineBuiltinUnhandled;
    }
    final count = word.b == 0 ? frame.effectiveTop - (word.a + 1) : word.b - 1;
    if (count <= 0) {
      return _inlineBuiltinUnhandled;
    }

    final firstArg = frame.slotValue(word.a + 1);
    final firstArgResults = luaResultValues(firstArg);
    final primaryCondition =
        firstArgResults != null && firstArgResults.isNotEmpty
        ? firstArgResults.first is Value
              ? firstArgResults.first as Value
              : _runtimeValue(runtime, firstArgResults.first)
        : firstArg;
    if (!isLuaTruthy(primaryCondition)) {
      return _inlineBuiltinUnhandled;
    }
    if (word.c == 1) {
      return null;
    }
    if (word.c == 0) {
      for (var index = 0; index < count; index++) {
        frame.setRegister(
          word.a + index,
          _normalizeInlineAssertSuccessValue(
            frame.slotValue(word.a + 1 + index),
          ),
        );
      }
      frame.top = word.a + count;
      return frame.top;
    }
    final expectedCount = word.c - 1;
    for (var index = 0; index < expectedCount; index++) {
      final value = index < count
          ? _normalizeInlineAssertSuccessValue(
              frame.slotValue(word.a + 1 + index),
            )
          : _framePrimitiveValue(runtime, null);
      frame.setRegister(word.a + index, value);
    }
    return null;
  }

  Object? _tryHandleFixedArityInlineBuiltinCall(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    Value callee,
    BuiltinFunction builtin,
  ) {
    if (builtin.isBytecodeAssertBuiltin) {
      final fastAssertResult = _tryStoreInlineAssertSuccessFast(
        frame,
        word,
        builtin: builtin,
      );
      if (!identical(fastAssertResult, _inlineBuiltinUnhandled)) {
        return fastAssertResult;
      }
      return _inlineBuiltinUnhandled;
    }
    if (!_canInlineBuiltinWithoutManagedFrame(builtin)) {
      return _inlineBuiltinUnhandled;
    }
    final rawFastResult = _tryInlineBuiltinFastArityRawFromFrame(
      frame,
      word,
      builtin: builtin,
    );
    if (identical(rawFastResult, BuiltinFunction.fastCallUnsupported)) {
      return _inlineBuiltinUnhandled;
    }
    return _tryStoreFastInlineResult(frame, word.a, word.c, rawFastResult);
  }

  Object? _tryStoreInlineAssertSuccessFast(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word, {
    required BuiltinFunction builtin,
  }) {
    if (!builtin.isBytecodeAssertBuiltin || word.b != 2 || word.c != 1) {
      return _inlineBuiltinUnhandled;
    }
    final firstArg = frame.slotValue(word.a + 1);
    if (luaResultValues(firstArg) != null) {
      return _inlineBuiltinUnhandled;
    }
    return isLuaTruthy(firstArg) ? null : _inlineBuiltinUnhandled;
  }

  Value _normalizeInlineAssertSuccessValue(Value value) {
    if (luaResultValues(value) == null) {
      final raw = rawLuaSlot(value);
      if (isLuaPrimitiveSlot(raw)) {
        return switch (raw) {
          null ||
          bool() ||
          num() ||
          BigInt() => _framePrimitiveValue(runtime, raw),
          _ => _runtimeValue(runtime, raw),
        };
      }
    }
    return value;
  }

  Object? _tryInlineBuiltinFastArityRawFromFrame(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word, {
    required BuiltinFunction builtin,
  }) {
    final count = word.b == 0 ? frame.effectiveTop - (word.a + 1) : word.b - 1;
    return switch (count) {
      0 => builtin.fastCall0(),
      1 => builtin.fastCall1(frame.slotValue(word.a + 1)),
      2 => builtin.fastCall2(
        frame.slotValue(word.a + 1),
        frame.slotValue(word.a + 2),
      ),
      _ => BuiltinFunction.fastCallUnsupported,
    };
  }

  Object? _tryStoreFastInlineResult(
    _LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    Object? result,
  ) {
    if (isLuaResults(result)) {
      return _inlineBuiltinUnhandled;
    }
    final normalizedValue = switch (result) {
      null => _framePrimitiveValue(runtime, null),
      final Value value when _isSharedRuntimeConstant(runtime, value) =>
        switch (rawLuaSlot(value)) {
          null ||
          bool() ||
          num() ||
          BigInt() => _framePrimitiveValue(runtime, rawLuaSlot(value)),
          _ => value,
        },
      final Value value when luaResultValues(value) == null => value,
      final raw => switch (raw) {
        bool() || num() || BigInt() => _framePrimitiveValue(runtime, raw),
        _ => _runtimeValue(runtime, raw),
      },
    };
    if (luaResultValues(normalizedValue) != null) {
      return _inlineBuiltinUnhandled;
    }
    if (resultSpec == 1) {
      return null;
    }
    if (resultSpec == 0) {
      frame.setRegister(register, normalizedValue);
      frame.top = register + 1;
      return frame.top;
    }
    final expectedCount = resultSpec - 1;
    if (expectedCount <= 0) {
      return null;
    }
    frame.setRegister(register, normalizedValue);
    for (var index = 1; index < expectedCount; index++) {
      frame.setRegister(register + index, _runtimeValue(runtime, null));
    }
    return null;
  }

  List<Value> _rewriteCoroutineFactoryArgs(
    Value callee,
    List<Value> args, {
    required String? callName,
    required String? callNameWhat,
  }) {
    if (args.isEmpty ||
        callNameWhat != 'field' ||
        (callName != 'create' && callName != 'wrap') ||
        rawLuaSlot(callee) is! BuiltinFunction) {
      return args;
    }

    final functionArg = args.first;
    final rawFunctionArg = rawLuaSlot(functionArg);
    if (rawFunctionArg is! LuaBytecodeClosure ||
        functionArg.functionBody == null) {
      return args;
    }

    final closure = rawFunctionArg;
    final strippedFunction = Value(
      closure,
      isConst: functionArg.isConst,
      isToBeClose: functionArg.isToBeClose,
      upvalues: functionArg.upvalues,
      interpreter: functionArg.interpreter ?? runtime,
      closureEnvironment: functionArg.closureEnvironment ?? closure.environment,
      functionName: functionArg.functionName,
      debugLineDefined: functionArg.debugLineDefined,
      strippedDebugInfo: functionArg.strippedDebugInfo,
    );
    if (args.length == 1) {
      return <Value>[strippedFunction];
    }
    return <Value>[strippedFunction, ...args.skip(1)];
  }

  FutureOr<List<Value>?> _tryHandleDebugLocalBuiltin(
    Value callee,
    List<Value> args, {
    String? callName,
    String? callNameWhat,
    int extraArgs = 0,
    _LuaBytecodeFrame? callerFrame,
  }) {
    final rawBuiltin = rawLuaSlot(callee);
    if (rawBuiltin is! BuiltinFunction) {
      return null;
    }
    final isGetLocal =
        rawBuiltin.isBytecodeDebugGetLocalBuiltin || callName == 'getlocal';
    final isSetLocal =
        rawBuiltin.isBytecodeDebugSetLocalBuiltin || callName == 'setlocal';
    if (!isGetLocal && !isSetLocal) {
      return null;
    }
    _bindCallerFrameForDebugInspection(callerFrame);
    final level = args.isNotEmpty
        ? _coerceLuaInteger(rawLuaSlot(args[0]))
        : null;
    final index = args.length >= 2
        ? _coerceLuaInteger(rawLuaSlot(args[1]))
        : null;
    final frame = switch (level) {
      final int visibleLevel when visibleLevel > 0 =>
        _resolveVisibleBytecodeFrame(runtime, visibleLevel),
      _ => null,
    };
    if (rawLuaSlot(frame?.callable) is! LuaBytecodeClosure) {
      return null;
    }
    _syncCallFrameDebugLocals(frame);
    return _invokeFastBuiltinWithHooks(
      callee,
      args,
      callName: callName,
      callNameWhat: callNameWhat,
      extraArgs: extraArgs,
      callerFrame: callerFrame,
      action: () {
        if (isGetLocal && args.length >= 2) {
          if (index case final int varargIndex when varargIndex < 0) {
            final rawVarargs = _frameDebugVarargs(frame!);
            if (rawVarargs == null || -varargIndex > rawVarargs.length) {
              return <Value>[
                runtime.constantPrimitiveValue(null),
                runtime.constantPrimitiveValue(null),
              ];
            }
            final value = rawVarargs[-varargIndex - 1];
            return <Value>[
              runtime.constantDartStringValue('(vararg)'),
              _runtimeValue(runtime, value),
            ];
          }
          if (index case final int localIndex when localIndex > 0) {
            if (frame!.ntransfer > 0 &&
                localIndex >= frame.ftransfer &&
                localIndex < frame.ftransfer + frame.ntransfer) {
              return <Value>[
                runtime.constantDartStringValue('(temporary)'),
                frame.transferValues[localIndex - frame.ftransfer],
              ];
            }
            final locals = _bytecodeFrameLocals(frame);
            if (localIndex > locals.length) {
              return <Value>[
                runtime.constantPrimitiveValue(null),
                runtime.constantPrimitiveValue(null),
              ];
            }
            final entry = locals[localIndex - 1];
            return <Value>[
              runtime.constantDartStringValue(entry.key),
              entry.value,
            ];
          }
          return <Value>[
            runtime.constantPrimitiveValue(null),
            runtime.constantPrimitiveValue(null),
          ];
        }
        if (isSetLocal && args.length >= 3) {
          if (index case final int varargIndex when varargIndex < 0) {
            final rawVarargs = _frameDebugVarargs(frame!);
            if (rawVarargs == null || -varargIndex > rawVarargs.length) {
              return <Value>[runtime.constantPrimitiveValue(null)];
            }
            rawVarargs[-varargIndex - 1] = args[2];
            _syncFrameDebugVarargs(frame, rawVarargs);
            return <Value>[runtime.constantDartStringValue('(vararg)')];
          }
          if (index case final int localIndex when localIndex > 0) {
            final locals = _bytecodeFrameLocals(frame!);
            if (localIndex > locals.length) {
              return <Value>[runtime.constantPrimitiveValue(null)];
            }
            final entry = locals[localIndex - 1];
            if (entry.key == '(vararg table)') {
              return <Value>[runtime.constantPrimitiveValue(null)];
            }
            _overwriteValue(entry.value, args[2]);
            return <Value>[runtime.constantDartStringValue(entry.key)];
          }
          return <Value>[runtime.constantPrimitiveValue(null)];
        }
        return <Value>[runtime.constantPrimitiveValue(null)];
      },
    );
  }

  FutureOr<List<Value>?> _tryHandleProtectedCallBuiltin(
    Value callee,
    List<Value> args, {
    String? callName,
    String? callNameWhat,
    int extraArgs = 0,
    _LuaBytecodeFrame? callerFrame,
  }) {
    final rawBuiltin = rawLuaSlot(callee);
    if (rawBuiltin is! BuiltinFunction) {
      return null;
    }
    if (!rawBuiltin.isBytecodeProtectedCallBuiltin && callName != 'pcall') {
      return null;
    }
    return _invokeFastBuiltinWithHooks(
      callee,
      args,
      callName: callName,
      callNameWhat: callNameWhat,
      extraArgs: extraArgs,
      callerFrame: callerFrame,
      action: () async {
        if (args.isEmpty) {
          throw LuaError('pcall requires a function');
        }
        final func = args.first;
        final callArgs = args.length == 1 ? const <Value>[] : args.sublist(1);
        return _invokeBytecodePCall(func, callArgs);
      },
    );
  }

  Future<List<Value>> _invokeBytecodePCall(
    Value func,
    List<Value> callArgs,
  ) async {
    runtime.enterProtectedCall();
    try {
      if (!func.isCallable()) {
        throw LuaError.typeError('attempt to call a ${getLuaType(func)} value');
      }

      final callResults = await _invokeValueWithName(func, callArgs);
      return <Value>[_runtimeValue(runtime, true), ...callResults];
    } on TailCallException catch (tail) {
      final callee = valueFromLuaSlot(runtime, tail.functionValue);
      final normalizedArgs = tail.args
          .map((arg) => valueFromLuaSlot(runtime, arg))
          .toList(growable: false);
      final awaitedResult = await runtime.callFunction(callee, normalizedArgs);
      return _packBytecodeProtectedCallSuccess(awaitedResult);
    } on CoroutineCloseSignal {
      rethrow;
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? runtime.getCurrentCoroutine();
      if (coroutine != null) {
        final nextChild = coroutine.takeContinuation();
        _installBytecodeContinuation(
          coroutine,
          _LuaBytecodeProtectedCallSuspension(vm: this, child: nextChild),
        );
      }
      rethrow;
    } catch (error) {
      return _packBytecodeProtectedCallFailure(error);
    } finally {
      runtime.exitProtectedCall();
    }
  }

  List<Value> _packBytecodeProtectedCallSuccess(Object? result) {
    final multiValues = luaResultValues(result);
    if (multiValues != null) {
      return <Value>[
        _runtimeValue(runtime, true),
        ...multiValues.map((value) => _runtimeValue(runtime, value)),
      ];
    }
    if (result == null) {
      return <Value>[_runtimeValue(runtime, true)];
    }
    return <Value>[
      _runtimeValue(runtime, true),
      _runtimeValue(runtime, result),
    ];
  }

  List<Value> _packBytecodeProtectedCallFailure(Object error) {
    final normalizedError = _normalizeBytecodeProtectedCallError(error);
    return <Value>[
      _runtimeValue(runtime, false),
      valueFromLuaSlot(runtime, normalizedError),
    ];
  }

  Object? _normalizeBytecodeProtectedCallError(Object error) {
    if (error is Value) {
      final rawError = rawLuaSlot(error);
      if (rawError is Value) {
        return _normalizeBytecodeProtectedCallError(rawError);
      }
      if (rawError == null) {
        return '<no error object>';
      }
      if (rawError is Map || rawError is TableStorage) {
        return error;
      }
      return error.unwrap();
    }
    if (error is LuaError) {
      if (error.suppressAutomaticLocation ||
          error.suppressProtectedCallLocation ||
          _looksFormattedBytecodeLuaErrorMessage(error.message)) {
        return error.message;
      }
      final span = error.span ?? error.node?.span;
      final sourceUrl = span?.sourceUrl?.toString();
      final line = switch (error.lineNumber) {
        final explicitLine? when explicitLine > 0 => explicitLine,
        _ when span != null => span.start.line + 1,
        _ => null,
      };
      if (sourceUrl != null && sourceUrl.isNotEmpty) {
        final formattedSource = switch (Uri.tryParse(sourceUrl)) {
          final Uri uri when uri.scheme == 'file' => uri.toFilePath(),
          _ => sourceUrl,
        };
        if (line != null && line > 0) {
          return '$formattedSource:$line: ${error.message}';
        }
        return '$formattedSource: ${error.message}';
      }
      return _formatBytecodeProtectedCallMessage(
        error.message,
        lineOverride: error.lineNumber,
      );
    }
    return error.toString();
  }

  String _formatBytecodeProtectedCallMessage(
    String message, {
    int? lineOverride,
  }) {
    final topFrame = runtime.callStack.top;
    final line = switch (lineOverride) {
      final currentLine? when currentLine > 0 => currentLine,
      _ => switch (topFrame?.currentLine) {
        final currentLine when currentLine != null && currentLine > 0 =>
          currentLine,
        _ => -1,
      },
    };
    final scriptPath =
        topFrame?.scriptPath ??
        runtime.callStack.scriptPath ??
        runtime.currentScriptPath;
    if (scriptPath != null && line > 0) {
      return '$scriptPath:$line: $message';
    }
    if (scriptPath != null) {
      return '$scriptPath: $message';
    }
    return message;
  }

  Future<List<Value>> _invokeFastBuiltinWithHooks(
    Value callee,
    List<Value> args, {
    String? callName,
    String? callNameWhat,
    int extraArgs = 0,
    _LuaBytecodeFrame? callerFrame,
    bool isTailCall = false,
    required FutureOr<List<Value>> Function() action,
  }) async {
    if (callerFrame != null) {
      final callerLine = callerFrame.closure.prototype.lineForPc(
        callerFrame.pc - 1,
      );
      if (callerLine != null) {
        runtime.callStack.top?.currentLine = callerLine;
      }
    }
    _guardCallDepth();
    runtime.callStack.push(
      callName ?? _callableName(callee),
      callNode: _syntheticCallNode(callName, callNameWhat),
      env: runtime.getCurrentEnv(),
      debugName: callName,
      debugNameWhat: callNameWhat ?? '',
      callable: callee,
    );
    runtime.callStack.top?.isTailCall = isTailCall;
    runtime.callStack.top?.extraArgs = extraArgs;
    final callDebugInterpreter = _debugInterpreter;
    if (callDebugInterpreter != null) {
      _setTransferInfo(runtime.callStack.top, args);
      final interpreter = callDebugInterpreter;
      await interpreter.fireDebugHook('call');
      _clearTransferInfo(runtime.callStack.top);
    }
    Iterable<Value> tempRootProvider() sync* {
      yield callee;
      for (final arg in args) {
        yield arg;
      }
    }

    runtime.pushExternalGcRoots(tempRootProvider);
    final yieldableAtCallEntry = runtime.isYieldable;
    List<Value> returnTransferValues = const <Value>[];
    try {
      final result = await action();
      returnTransferValues = result;
      return result;
    } on CoroutineCloseSignal catch (signal) {
      _closeSignalYieldableStates[signal] =
          (_closeSignalYieldableStates[signal] ?? true) && yieldableAtCallEntry;
      rethrow;
    } finally {
      final returnDebugInterpreter = _debugInterpreter;
      if (returnDebugInterpreter != null) {
        final topFrame = runtime.callStack.top;
        if (topFrame != null) {
          _setTransferInfo(topFrame, returnTransferValues);
        }
        final interpreter = returnDebugInterpreter;
        await interpreter.fireDebugHook('return');
        _clearTransferInfo(topFrame);
      }
      runtime.callStack.pop();
      runtime.popExternalGcRoots(tempRootProvider);
    }
  }

  void _setTransferInfo(CallFrame? frame, List<Value> values) {
    if (frame == null) {
      return;
    }
    frame.ftransfer = values.isEmpty ? 0 : 1;
    frame.ntransfer = values.length;
    frame.transferValues = values;
  }

  void _clearTransferInfo(CallFrame? frame) {
    if (frame == null) {
      return;
    }
    frame.ftransfer = 0;
    frame.ntransfer = 0;
    frame.transferValues = const <Value>[];
  }

  Future<void> _fireFrameCallHook(
    _LuaBytecodeFrame frame,
    Interpreter interpreter,
  ) async {
    _syncDebugLocals(frame);
    _setTransferInfo(runtime.callStack.top, [
      for (var i = 0; i < frame.closure.prototype.parameterCount; i++)
        frame.register(i),
    ]);
    try {
      await interpreter.fireDebugHook(frame.isTailCall ? 'tail call' : 'call');
      frame.didFireEntryCallHook = true;
    } finally {
      _clearTransferInfo(runtime.callStack.top);
    }
  }

  void _guardCallDepth() {
    final callStackBaseDepth =
        runtime.getCurrentCoroutine()?.callStackBaseDepth ?? 0;
    final globalCallDepth = runtime.callStack.depth;
    final coroutineCallDepth = globalCallDepth - callStackBaseDepth;
    if (globalCallDepth >= Interpreter.maxCallDepth ||
        coroutineCallDepth >= Interpreter.maxCallDepth) {
      throw LuaError('C stack overflow');
    }
  }

  String _callableName(Value callee) {
    return switch (callee.functionName) {
      final String name when name.isNotEmpty => name,
      _ => switch (rawLuaSlot(callee)) {
        final String name => name,
        _ => 'function',
      },
    };
  }

  AstNode? _syntheticCallNode(String? callName, String? callNameWhat) {
    if (callNameWhat != 'method' || callName == null || callName.isEmpty) {
      return null;
    }
    return MethodCall(
      Identifier('_bytecode_self'),
      Identifier(callName),
      const <AstNode>[],
      implicitSelf: true,
    );
  }

  ({String? name, String namewhat}) _callSiteNameInfo(
    _LuaBytecodeFrame frame,
    int register,
    Value callee,
  ) {
    final currentPc = frame.pc;
    final logicalMergeValue = _registerHoldsLogicalMergeValue(
      frame,
      register,
      beforePc: currentPc - 2,
    );
    if (!logicalMergeValue) {
      final activeLocals = frame.activeNamedLocalsAt(currentPc);
      if (activeLocals[register] case final String name) {
        return (name: name, namewhat: 'local');
      }
      final calleeRaw = rawLuaSlot(callee);
      for (final entry in activeLocals.entries) {
        final localValue = frame.register(entry.key);
        final localRaw = rawLuaSlot(localValue);
        if ((identical(localValue, callee) || identical(localRaw, calleeRaw)) &&
            _isUnambiguousMoveAlias(frame, register, beforePc: currentPc - 2)) {
          return (name: entry.value, namewhat: 'local');
        }
      }
    }
    final inferred = _inferRegisterCallNameInfo(
      frame,
      register,
      beforePc: currentPc - 2,
      visitedRegisters: <int>{},
    );
    if (inferred.name != null) {
      return inferred;
    }
    return switch (rawLuaSlot(callee)) {
      final String name => (
        name: name,
        namewhat: _inferCallNameWhatFromEnvironment(frame, name),
      ),
      _ => (name: null, namewhat: ''),
    };
  }

  ({String? name, String namewhat}) _inferRegisterCallNameInfo(
    _LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (!visitedRegisters.add(register)) {
      return (name: null, namewhat: '');
    }
    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }
      if (_isLogicalMergeWrite(frame, register, pc, usePc: beforePc + 1)) {
        return (name: null, namewhat: '');
      }
      return switch (opcodeValue) {
        Opcode.move =>
          _isUnambiguousMoveAlias(frame, register, beforePc: beforePc)
              ? (() {
                  if (frame.activeLocalNameAt(word.b, beforePc + 1)
                      case final String name) {
                    return (name: name, namewhat: 'local');
                  }
                  return _inferRegisterCallNameInfo(
                    frame,
                    word.b,
                    beforePc: pc - 1,
                    visitedRegisters: visitedRegisters,
                  );
                })()
              : (name: null, namewhat: ''),
        Opcode.getTable => switch (_stringKeyForRegister(
          frame,
          word.c,
          beforePc: pc - 1,
          visitedRegisters: <int>{},
        )) {
          final String key => switch (_isEnvironmentRegister(
            frame,
            word.b,
            beforePc: pc - 1,
            visitedRegisters: <int>{},
          )) {
            true => (name: key, namewhat: 'global'),
            false => (name: key, namewhat: 'field'),
          },
          _ => (name: null, namewhat: ''),
        },
        Opcode.getField => switch (_isEnvironmentRegister(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: <int>{},
        )) {
          true => (
            name: _stringConstantRaw(prototype, word.c),
            namewhat: 'global',
          ),
          false => (
            name: _stringConstantRaw(prototype, word.c),
            namewhat: 'field',
          ),
        },
        Opcode.self => (
          name: _stringConstantRaw(prototype, word.c),
          namewhat: 'method',
        ),
        Opcode.getTabUp => (
          name: _stringConstantRaw(prototype, word.c),
          namewhat: 'global',
        ),
        Opcode.getUpval => (
          name: frame.closure.upvalueName(word.b),
          namewhat: 'upvalue',
        ),
        Opcode.loadK => switch (_constantRaw(prototype, word.bx)) {
          final String name => (
            name: name,
            namewhat: _inferCallNameWhatFromEnvironment(frame, name),
          ),
          final LuaString name => (
            name: name.toString(),
            namewhat: _inferCallNameWhatFromEnvironment(frame, name.toString()),
          ),
          _ => (name: null, namewhat: ''),
        },
        Opcode.loadKx => switch (_constantRaw(
          prototype,
          prototype.code[pc + 1].ax,
        )) {
          final String name => (
            name: name,
            namewhat: _inferCallNameWhatFromEnvironment(frame, name),
          ),
          final LuaString name => (
            name: name.toString(),
            namewhat: _inferCallNameWhatFromEnvironment(frame, name.toString()),
          ),
          _ => (name: null, namewhat: ''),
        },
        _ => (name: null, namewhat: ''),
      };
    }
    return (name: null, namewhat: '');
  }

  String _inferCallNameWhatFromEnvironment(
    _LuaBytecodeFrame frame,
    String name,
  ) {
    Environment? env = frame.closure.environment;
    while (env != null) {
      if (env.values.containsKey(name)) {
        final box = env.values[name]!;
        return box.isLocal ? 'local' : 'global';
      }
      if (env.declaredGlobals.containsKey(name)) {
        return 'global';
      }
      env = env.parent;
    }
    return 'global';
  }

  String? _callSiteTargetLabel(
    _LuaBytecodeFrame frame,
    int register,
    Value callee,
  ) {
    final info = _callSiteNameInfo(frame, register, callee);
    if (info.name == null) {
      return null;
    }
    if (info.namewhat.isEmpty) {
      return info.name;
    }
    return "${info.namewhat} '${info.name}'";
  }

  ({String? name, String namewhat}) _decodeTailCallNameInfo(String? label) {
    if (label == null) {
      return (name: null, namewhat: '');
    }
    final match = RegExp(r"^([A-Za-z_]+) '(.*)'$").firstMatch(label);
    if (match == null) {
      return (name: label, namewhat: '');
    }
    return (name: match.group(2), namewhat: match.group(1) ?? '');
  }

  bool _looksFormattedBytecodeLuaErrorMessage(String message) =>
      _bytecodeFormattedLuaErrorPattern.hasMatch(message);

  LuaError _rewriteBinaryOperandError(
    _LuaBytecodeFrame frame,
    Value left,
    Value right,
    LuaError error, {
    String? leftLabel,
    String? rightLabel,
  }) {
    final message = error.message;
    final leftRaw = rawLuaSlot(left);
    final rightRaw = rawLuaSlot(right);
    if (message == 'number has no integer representation') {
      final leftInvalid = !_hasIntegerRepresentation(leftRaw);
      final rightInvalid = !_hasIntegerRepresentation(rightRaw);
      if (leftInvalid != rightInvalid) {
        final label = leftInvalid
            ? leftLabel ?? _valueSourceLabel(frame, left)
            : rightLabel ?? _valueSourceLabel(frame, right);
        if (label != null) {
          return LuaError(
            'number has no integer representation in '
            '${label.replaceAll("'", '')}',
            cause: error.cause,
            stackTrace: error.stackTrace,
            luaStackTrace: error.luaStackTrace,
            suppressAutomaticLocation: error.suppressAutomaticLocation,
          );
        }
      }
      return error;
    }
    if (!message.startsWith('attempt to perform arithmetic on a ')) {
      return error;
    }

    final offending =
        _coerceLuaNumber(leftRaw) == null && _coerceLuaNumber(rightRaw) != null
        ? left
        : right;
    final offendingType = getLuaType(offending);
    if (!_shouldUseArithmeticSourceLabel(offendingType)) {
      return error;
    }
    final label = identical(offending, left)
        ? leftLabel ?? _valueSourceLabel(frame, offending)
        : rightLabel ?? _valueSourceLabel(frame, offending);
    if (_debugFileOps) {
      final offendingRaw = rawLuaSlot(offending);
      _debugFileLog(
        'binary-error left=${leftRaw.runtimeType} right=${rightRaw.runtimeType} '
        'offending=${offendingRaw.runtimeType} label=$label',
      );
    }
    if (label == null) {
      return error;
    }

    return LuaError(
      "attempt to perform arithmetic on $label (a $offendingType value)",
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: error.suppressAutomaticLocation,
    );
  }

  LuaError _rewriteIndexOperandError(
    _LuaBytecodeFrame frame,
    Value receiver,
    LuaError error, {
    String? labelOverride,
  }) {
    final message = error.message;
    if (!message.startsWith('attempt to index a ')) {
      return error;
    }

    final label = labelOverride ?? _valueSourceLabel(frame, receiver);
    if (label == null) {
      return error;
    }

    return LuaError(
      "attempt to index $label (a ${getLuaType(receiver)} value)",
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: error.suppressAutomaticLocation,
    );
  }

  String? _valueSourceLabel(_LuaBytecodeFrame frame, Value value) {
    final rawValue = rawLuaSlot(value);
    for (
      var registerIndex = 0;
      registerIndex < frame.registers.length;
      registerIndex++
    ) {
      final registerValue = frame.registers[registerIndex];
      if (identical(registerValue, value) ||
          (rawValue != null &&
              identical(rawLuaSlot(registerValue), rawValue))) {
        if (_activeLocalSourceLabel(frame, registerIndex) case final label?) {
          return label;
        }
        return _inferRegisterSourceLabel(
          frame,
          registerIndex,
          beforePc: frame.pc - 2,
          visitedRegisters: <int>{},
        );
      }
    }
    return null;
  }

  (String?, String?) _binaryOperandSourceLabelsForPreviousInstruction(
    _LuaBytecodeFrame frame,
  ) {
    final word = _previousInstruction(frame);
    final operandBeforePc = frame.pc - 3;
    final opcode = word.opcode;
    return switch (opcode) {
      Opcode.addI ||
      Opcode.addK ||
      Opcode.subK ||
      Opcode.mulK ||
      Opcode.modK ||
      Opcode.powK ||
      Opcode.divK ||
      Opcode.idivK ||
      Opcode.bandK ||
      Opcode.borK ||
      Opcode.bxorK ||
      Opcode.shrI => (
        _registerSourceLabelBefore(frame, word.b, beforePc: operandBeforePc),
        null,
      ),
      Opcode.shlI => (
        null,
        _registerSourceLabelBefore(frame, word.b, beforePc: operandBeforePc),
      ),
      Opcode.add ||
      Opcode.sub ||
      Opcode.mul ||
      Opcode.mod ||
      Opcode.pow ||
      Opcode.div ||
      Opcode.idiv ||
      Opcode.band ||
      Opcode.bor ||
      Opcode.bxor ||
      Opcode.shl ||
      Opcode.shr => (
        _registerSourceLabelBefore(frame, word.b, beforePc: operandBeforePc),
        _registerSourceLabelBefore(frame, word.c, beforePc: operandBeforePc),
      ),
      _ => (null, null),
    };
  }

  String? _registerSourceLabel(
_LuaBytecodeFrame frame, int? register) {
    return _registerSourceLabelBefore(frame, register, beforePc: frame.pc - 2);
  }

  String? _registerSourceLabelBefore(
    _LuaBytecodeFrame frame,
    int? register, {
    required int beforePc,
  }) {
    if (register == null) {
      return null;
    }
    if (_registerHoldsLogicalMergeValue(frame, register, beforePc: beforePc)) {
      return null;
    }
    final activeLocal = _activeLocalSourceLabel(frame, register);
    if (activeLocal != null) {
      return activeLocal;
    }
    return _inferRegisterSourceLabel(
      frame,
      register,
      beforePc: beforePc,
      visitedRegisters: <int>{},
    );
  }

  bool _registerHoldsLogicalMergeValue(
    _LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
  }) {
    for (var pc = beforePc; pc >= 0; pc--) {
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }
      final result = _isLogicalMergeWrite(
        frame,
        register,
        pc,
        usePc: beforePc + 1,
      );
      return result;
    }
    return false;
  }

  String? _inferRegisterSourceLabel(
    _LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (!visitedRegisters.add(register)) {
      return null;
    }
    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }
      if (_isLogicalMergeWrite(frame, register, pc, usePc: beforePc + 1)) {
        return null;
      }

      return switch (opcodeValue) {
        Opcode.move =>
          _isUnambiguousMoveAlias(frame, register, beforePc: beforePc)
              ? (_activeLocalSourceLabel(frame, word.b) ??
                    _inferRegisterSourceLabel(
                      frame,
                      word.b,
                      beforePc: pc - 1,
                      visitedRegisters: visitedRegisters,
                    ))
              : null,
        Opcode.getTable => switch (_stringKeyForRegister(
          frame,
          word.c,
          beforePc: pc - 1,
          visitedRegisters: <int>{},
        )) {
          final String key => switch (_isEnvironmentRegister(
            frame,
            word.b,
            beforePc: pc - 1,
            visitedRegisters: <int>{},
          )) {
            true => "global '$key'",
            false => "field '$key'",
          },
          _ => null,
        },
        Opcode.getField => switch (_isEnvironmentRegister(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: <int>{},
        )) {
          true => "global '${_stringConstantRaw(prototype, word.c)}'",
          false => "field '${_stringConstantRaw(prototype, word.c)}'",
        },
        Opcode.self => "method '${_stringConstantRaw(prototype, word.c)}'",
        Opcode.getTabUp => "global '${_stringConstantRaw(prototype, word.c)}'",
        Opcode.getUpval => switch (frame.closure.upvalueName(word.b)) {
          final String name when name.isNotEmpty => "upvalue '$name'",
          _ => null,
        },
        _ => null,
      };
    }
    return null;
  }

  String? _activeLocalSourceLabel(_LuaBytecodeFrame frame, int register) {
    return switch (frame.visibleNamedLocals[register]) {
      final String name => "local '$name'",
      _ => null,
    };
  }

  String? _stringKeyForRegister(
    _LuaBytecodeFrame frame,
    int? register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (register == null) {
      return null;
    }
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = frame.closure.prototype.code[pc];
      final opcodeValue = word.opcode;
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }

      return switch (opcodeValue) {
        Opcode.move => _stringKeyForRegister(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: visitedRegisters,
        ),
        Opcode.loadK => _stringConstantFromRaw(
          _constantRaw(frame.closure.prototype, word.bx),
        ),
        Opcode.loadKx => _stringConstantFromRaw(
          _constantRaw(frame.closure.prototype, frame.closure.prototype.code[pc + 1].ax),
        ),
        _ => null,
      };
    }
    return null;
  }

  String? _stringConstantFromRaw(
Object? raw) {
    return switch (raw) {
      final String stringValue => stringValue,
      final LuaString stringValue => stringValue.toString(),
      _ => null,
    };
  }

  bool _isEnvironmentRegister(
    _LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (!visitedRegisters.add(register)) {
      return false;
    }

    if (frame.isEnvironmentLocalRegister(register)) {
      return true;
    }

    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }

      return switch (opcodeValue) {
        Opcode.move => _isEnvironmentRegister(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: visitedRegisters,
        ),
        Opcode.getUpval => frame.closure.upvalueName(word.b) == '_ENV',
        _ => false,
      };
    }

    return false;
  }

  bool _isUnambiguousMoveAlias(
    _LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
  }) {
    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      if (frame.instructionWritesRegister(pc, register)) {
        if (opcodeValue != Opcode.move) {
          return false;
        }
        for (var lookback = pc - 1; lookback >= 0; lookback--) {
          final previous = prototype.code[lookback];
          final previousOpcodeValue = previous.opcodeValue;
          if (previousOpcodeValue == Opcode.return_.code ||
              previousOpcodeValue == Opcode.tailCall.code) {
            return true;
          }
          if (frame.instructionWritesRegister(lookback, register)) {
            return true;
          }
        }
        return true;
      }
    }
    return false;
  }

  bool _isLogicalMergeWrite(

    _LuaBytecodeFrame frame,
    int register,
    int writePc, {
    required int usePc,
  }) {
    if (writePc < 2) {
      return false;
    }
    final prototype = frame.closure.prototype;
    final jumpWord = prototype.code[writePc - 1];
    if (jumpWord.opcodeValue != Opcode.jmp.code) {
      return false;
    }
    final testWord = prototype.code[writePc - 2];
    if (testWord.opcodeValue != Opcode.test.code || testWord.a != register) {
      return false;
    }
    final jumpTargetPc = (writePc - 1) + 1 + jumpWord.sJ;
    return usePc >= jumpTargetPc;
  }

  bool _instructionWritesRegisterByOpcodeValue(
    LuaBytecodeInstructionWord word,
    Opcode opcodeValue,
    int register,
  ) {
    return word.writesRegister(register);
  }

  LuaError _normalizeStrippedFrameError(

    _LuaBytecodeFrame frame,
    LuaError error,
  ) {
    final prototype = frame.closure.prototype;
    if (prototype.hasDebugInfo) {
      return error;
    }

    final withoutLabels = error.message
        .replaceAllMapped(
          RegExp(
            r"attempt to perform arithmetic on (?:local|global|upvalue|field|method) '[^']+' \(a ([^)]+) value\)",
          ),
          (match) =>
              'attempt to perform arithmetic on a ${match.group(1)} value',
        )
        .replaceAllMapped(
          RegExp(
            r"attempt to perform bitwise operation on (?:local|global|upvalue|field|method) '[^']+' \(a ([^)]+) value\)",
          ),
          (match) =>
              'attempt to perform bitwise operation on a ${match.group(1)} value',
        );
    final normalized = withoutLabels.startsWith('?:?:')
        ? withoutLabels
        : '?:?: $withoutLabels';
    return LuaError(
      normalized,
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: error.suppressAutomaticLocation,
    );
  }

  LuaError _rewriteNonClosableLocalError(
    _LuaBytecodeFrame frame,
    LuaError error,
  ) {
    const baseMessage =
        'to-be-closed variable value must have a __close metamethod';
    if (!error.message.endsWith(baseMessage)) {
      return error;
    }
    final prefix = error.message.substring(
      0,
      error.message.length - baseMessage.length,
    );

    for (final locals in [frame.activeNamedLocals, frame.visibleNamedLocals]) {
      for (final entry in locals.entries) {
        if (_registerHasNonClosableValue(frame, entry.key)) {
          return LuaError(
            "${prefix}variable '${entry.value}' got a non-closable value",
            cause: error.cause,
            stackTrace: error.stackTrace,
            luaStackTrace: error.luaStackTrace,
            suppressAutomaticLocation: error.suppressAutomaticLocation,
            suppressProtectedCallLocation: error.suppressProtectedCallLocation,
            lineNumber: error.lineNumber,
            hasBeenReported: error.hasBeenReported,
          );
        }
      }
    }

    for (final local in frame.closure.prototype.localVariables) {
      final name = local.name;
      final register = local.register;
      if (name == null ||
          name.isEmpty ||
          name.startsWith('(') ||
          register == null ||
          !_registerHasNonClosableValue(frame, register)) {
        continue;
      }
      return LuaError(
        "${prefix}variable '$name' got a non-closable value",
        cause: error.cause,
        stackTrace: error.stackTrace,
        luaStackTrace: error.luaStackTrace,
        suppressAutomaticLocation: error.suppressAutomaticLocation,
        suppressProtectedCallLocation: error.suppressProtectedCallLocation,
        lineNumber: error.lineNumber,
        hasBeenReported: error.hasBeenReported,
      );
    }

    return error;
  }

  bool _registerHasNonClosableValue(_LuaBytecodeFrame frame, int register) {
    if (register < 0 || register >= frame.registers.length) {
      return false;
    }
    final value = frame.slotValue(register);
    final raw = rawLuaSlot(value);
    return raw != null && raw != false && !value.hasMetamethod('__close');
  }

  LuaError _withFrameRuntimeLocation(_LuaBytecodeFrame frame, LuaError error) {
    error = _rewriteNonClosableLocalError(frame, error);
    if (error.suppressAutomaticLocation) {
      return error;
    }
    final rawCause = error.cause;
    if (rawCause != null &&
        rawCause is! LuaError &&
        error.message == rawCause.toString()) {
      // Lua's coroutine.resume moves the raw error object out of the coroutine,
      // and coroutine.wrap only prefixes location when that object is a string.
      // Keep bytecode frame-location decoration off non-string causes so
      // error(foo) still comes back as foo after a yield/resume round-trip.
      return error;
    }
    final message = error.message;
    if (RegExp(r'^.+:\d+: ').hasMatch(message)) {
      return error;
    }

    final source = frame.closure.prototype.source;
    final currentLine =
        runtime.callStack.top?.currentLine ??
        frame.closure.prototype.lineForPc(frame.pc > 0 ? frame.pc - 1 : 0);
    if (source == null ||
        source.isEmpty ||
        currentLine == null ||
        currentLine <= 0) {
      return error;
    }

    var strippedMessage = message;
    final locationPrefixMatch = RegExp(
      r'^([^:\n]+): (.*)$',
    ).firstMatch(message);
    if (locationPrefixMatch != null) {
      final prefix = locationPrefixMatch.group(1)!;
      final looksLikeLocation =
          prefix.startsWith('@') ||
          prefix.startsWith('=') ||
          prefix.startsWith('[') ||
          prefix.startsWith('file:///') ||
          looksLikeLuaFilePath(prefix);
      if (looksLikeLocation) {
        strippedMessage = locationPrefixMatch.group(2)!;
      }
    }
    return LuaError(
      '${_shortSource(source)}:$currentLine: $strippedMessage',
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: true,
    );
  }

  bool _shouldUseArithmeticSourceLabel(String type) => switch (type) {
    'nil' || 'boolean' || 'number' || 'string' || 'table' || 'function' => true,
    _ => false,
  };

  bool _hasIntegerRepresentation(Object? value) {
    if (value is Value) {
      value = rawLuaSlot(value);
    }
    if (value is String || value is LuaString) {
      try {
        value = LuaNumberParser.parse(value.toString());
      } catch (_) {
        return false;
      }
    }
    if (value is BigInt || value is int) {
      return true;
    }
    if (value is! double) {
      return false;
    }
    if (!value.isFinite || value.floorToDouble() != value) {
      return false;
    }
    try {
      final integer = BigInt.from(value);
      return integer >= BigInt.from(NumberLimits.minInteger) &&
          integer <= BigInt.from(NumberLimits.maxInteger);
    } on FormatException {
      return false;
    }
  }

  Future<void> _closeDiscardedCallResults(
    _LuaBytecodeFrame frame,
    List<Value> results,
  ) async {
    Object? closeError;
    StackTrace? closeStackTrace;

    for (var index = results.length - 1; index >= 0; index--) {
      final value = results[index];
      final rawValue = rawLuaSlot(value);
      if (_debugFileOps) {
        _debugFileLog(
          'discard-result index=$index tbc=${value.isToBeClose} '
          'raw=${rawValue.runtimeType} live=${frame._toBeClosedRegisters.toList()..sort()}',
        );
      }
      if (frame.isLiveToBeClosedAlias(value)) {
        if (_debugFileOps) {
          _debugFileLog('discard-result skip-live-alias index=$index');
        }
        continue;
      }
      if (!value.isToBeClose || rawValue == null || rawValue == false) {
        continue;
      }
      final closeValue = value.isToBeClose ? value : Value.toBeClose(value);
      closeValue.interpreter ??= runtime;
      try {
        await closeValue.close();
      } catch (error, stackTrace) {
        closeError ??= error;
        closeStackTrace ??= stackTrace;
      }
    }

    if (closeError != null && closeStackTrace != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace);
    }
  }

  int? _storeCallResults(
    _LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    List<Value> results,
  ) {
    if (resultSpec == 0) {
      for (var index = 0; index < results.length; index++) {
        frame.setRegister(register + index, results[index]);
      }
      frame.top = register + results.length;
      return frame.top;
    }

    final expectedCount = resultSpec - 1;
    for (var index = 0; index < expectedCount; index++) {
      final value = index < results.length
          ? results[index]
          : _runtimeValue(runtime, null);
      frame.setRegister(register + index, value);
    }
    frame.top = register + expectedCount;
    return null;
  }

  int? _storeVarargResults(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) {
    if (word.c == 0) {
      for (var index = 0; index < frame.varargCount; index++) {
        frame.setRegister(word.a + index, frame.varargAt(index)!);
      }
      frame.top = word.a + frame.varargCount;
      return frame.top;
    }

    final expectedCount = word.c - 1;
    for (var index = 0; index < expectedCount; index++) {
      final value = index < frame.varargCount
          ? frame.varargAt(index)!
          : _runtimeValue(runtime, null);
      frame.setRegister(word.a + index, value);
    }
    frame.top = word.a + expectedCount;
    return null;
  }

  bool _forPrep(_LuaBytecodeFrame frame, int base) {
    final initial = frame.register(base);
    final limit = frame.register(base + 1);
    final step = frame.register(base + 2);

    final coercedInitial = _forNumericOperand(initial, 'initial value');
    final coercedLimit = _forNumericOperand(limit, 'limit');
    final coercedStep = _forNumericOperand(step, 'step');

    final integerInitial = _exactForIntegerValue(coercedInitial);
    final integerStep = _exactForIntegerValue(coercedStep);
    if (integerInitial != null && integerStep != null) {
      final init = integerInitial;
      final stepValue = integerStep;
      if (stepValue == 0) {
        throw LuaError("'for' step is zero");
      }
      final limitInfo = _forIntegerLimit(init, coercedLimit, stepValue);
      if (limitInfo.skip) {
        return true;
      }
      final limitValue = limitInfo.limit;

      final count = stepValue > 0
          ? _unsignedDifference64(
                  _unsignedInt64(init: limitValue),
                  _unsignedInt64(init: init),
                ) ~/
                _unsignedInt64(init: stepValue)
          : _unsignedDifference64(
                  _unsignedInt64(init: init),
                  _unsignedInt64(init: limitValue),
                ) ~/
                _negativeStepDivisor(stepValue);
      frame.setRegister(
        base,
        _framePrimitiveValue(runtime, _signedInt64FromUnsigned(count)),
      );
      frame.setRegister(base + 1, _framePrimitiveValue(runtime, stepValue));
      frame.setRegister(base + 2, _framePrimitiveValue(runtime, init));
      return false;
    }

    final init = _numericForOperand(coercedInitial).toDouble();
    final limitValue = _numericForOperand(coercedLimit).toDouble();
    final stepValue = _numericForOperand(coercedStep).toDouble();
    if (stepValue == 0) {
      throw LuaError("'for' step is zero");
    }
    final shouldSkip = stepValue > 0 ? limitValue < init : init < limitValue;
    if (shouldSkip) {
      return true;
    }

    frame.setRegister(base, _runtimeValue(runtime, limitValue));
    frame.setRegister(base + 1, _framePrimitiveValue(runtime, stepValue));
    frame.setRegister(base + 2, _framePrimitiveValue(runtime, init));
    return false;
  }

  bool _forLoop(_LuaBytecodeFrame frame, int base) {
    if (_isInteger(frame.register(base + 1))) {
      final rawCount = rawLuaSlot(frame.slotValue(base));
      final rawStep = rawLuaSlot(frame.slotValue(base + 1));
      final rawIndex = rawLuaSlot(frame.slotValue(base + 2));
      if (rawCount is int &&
          rawCount > 0 &&
          rawStep is int &&
          rawIndex is int) {
        frame.setRegister(base, _framePrimitiveValue(runtime, rawCount - 1));
        frame.setRegister(
          base + 2,
          _framePrimitiveValue(runtime, rawIndex + rawStep),
        );
        return true;
      }
      final count = _unsignedForLoopCounter(frame.register(base));
      if (count <= BigInt.zero) {
        return false;
      }
      final step = _integerValue(frame.register(base + 1));
      final nextIndex = NumberUtils.add(
        _integerValue(frame.register(base + 2)),
        step,
      );
      frame.setRegister(
        base,
        _framePrimitiveValue(
          runtime,
          _signedInt64FromUnsigned(count - BigInt.one),
        ),
      );
      frame.setRegister(base + 2, _framePrimitiveValue(runtime, nextIndex));
      return true;
    }

    final step = _numericValue(frame.register(base + 1)).toDouble();
    final limit = _numericValue(frame.register(base)).toDouble();
    final nextIndex = _numericValue(frame.register(base + 2)).toDouble() + step;
    final shouldContinue = step > 0 ? nextIndex <= limit : nextIndex >= limit;
    if (!shouldContinue) {
      return false;
    }
    frame.setRegister(base + 2, _runtimeValue(runtime, nextIndex));
    return true;
  }

  Future<List<Value>> _genericForCall(
    _LuaBytecodeFrame frame,
    int base,
    int resultCount,
  ) async {
    if (platform.getEnvironmentVariable('LUALIKE_DEBUG_TFOR') == '1') {
      print(
        '[tfdebug] base=$base '
        'iterator=${frame.register(base)} '
        'state=${frame.register(base + 1)} '
        'control=${frame.register(base + 3)}',
      );
    }
    final iterator = frame.register(base);
    final state = frame.register(base + 1);
    final control = frame.register(base + 3);
    final results = await _invokePreparedCall(
      (callee: iterator, args: <Value>[state, control]),
      frame: frame,
      opcodeName: 'TFORCALL',
      callName: 'for iterator',
    );
    final expected = List<Value>.generate(
      resultCount,
      (index) => index < results.length
          ? results[index]
          : _runtimeValue(runtime, null),
      growable: false,
    );
    return expected;
  }

  Future<void> _setList(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) async {
    final table = frame.register(word.a);
    final count = word.vb == 0 ? frame.effectiveTop - word.a - 1 : word.vb;
    var last = word.vc + count;
    if (word.kFlag) {
      last +=
          _consumeExtraArg(frame).ax *
          (LuaBytecodeInstructionLayout.maxArgVC + 1);
    }
    for (var remaining = count; remaining > 0; remaining--) {
      final value = frame.register(word.a + remaining);
      final key = _runtimeValue(frame.runtime, last);
      if (!_tryFastTableSet(table, key, value)) {
        await _tableSet(table, key, value);
      }
      last--;
    }
  }

  void _docondjump(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    bool condition,
  ) {
    if (condition != word.kFlag) {
      frame.pc += 1;
    }
  }

  Future<Value> _tableGet(Value table, Value key) async {
    if (_tryFastTableGet(table, key) case final Value fastValue) {
      return fastValue;
    }
    table.interpreter ??= runtime;
    key.interpreter ??= runtime;
    final result = await table.getValueAsync(key);
    return _runtimeValue(runtime, result);
  }

  Value? _tryFastTableGet(Value table, Value key) {
    table.interpreter ??= runtime;
    key.interpreter ??= runtime;
    final rawTable = rawLuaSlot(table);
    if (_canFastPathGlobalProxyTableGet(table, key)) {
      final result = (rawTable as Map)[_plainTableStorageKey(key)];
      return _runtimeValue(runtime, result);
    }
    // Weak tables rely on Value's normal key normalization and memory-credit
    // bookkeeping. `__mode` is not a metamethod, so keep them off the raw
    // storage fast path even when `__index`/`__newindex` are absent.
    final hasWeakMode = table.tableWeakMode != null;
    if (rawTable is TableStorage &&
        !hasWeakMode &&
        !table.hasMetamethod('__index')) {
      final result = switch (_plainPositiveIntegerKey(key)) {
        final int index => rawTable.arrayValueAt(index),
        _ => rawTable[_plainTableStorageKey(key)],
      };
      return _runtimeValue(runtime, result);
    }
    if (rawTable is Map && !hasWeakMode && !table.hasMetamethod('__index')) {
      final result = rawTable[_plainTableStorageKey(key)];
      return _runtimeValue(runtime, result);
    }
    return null;
  }

  Value? _tryFastTableGetStringKey(Value table, String rawKey) {
    table.interpreter ??= runtime;
    final rawTable = rawLuaSlot(table);
    if (rawTable is Map &&
        table.globalProxyEnvironment != null &&
        table.tableWeakMode == null) {
      final result = rawTable[rawKey];
      if (result != null || rawTable.containsKey(rawKey)) {
        return _runtimeValue(runtime, result);
      }
    }
    final hasWeakMode = table.tableWeakMode != null;
    if (rawTable is TableStorage &&
        !hasWeakMode &&
        !table.hasMetamethod('__index')) {
      final result = rawTable[rawKey];
      return _runtimeValue(runtime, result);
    }
    if (rawTable is Map && !hasWeakMode && !table.hasMetamethod('__index')) {
      final result = rawTable[rawKey];
      return _runtimeValue(runtime, result);
    }
    return null;
  }

  bool _canFastPathGlobalProxyTableGet(Value table, Value key) {
    final rawTable = rawLuaSlot(table);
    if (rawTable is! Map || table.globalProxyEnvironment == null) {
      return false;
    }
    if (table.tableWeakMode != null) {
      return false;
    }
    final storageKey = _plainTableStorageKey(key);
    return rawTable.containsKey(storageKey);
  }

  bool _canFastPathGlobalProxyTableGetStringKey(Value table, String rawKey) {
    final rawTable = rawLuaSlot(table);
    if (rawTable is! Map || table.globalProxyEnvironment == null) {
      return false;
    }
    if (table.tableWeakMode != null) {
      return false;
    }
    return rawTable.containsKey(rawKey);
  }

  bool _tryFastTableSetStringKey(Value table, String rawKey, Value value) {
    table.interpreter ??= runtime;
    value.interpreter ??= runtime;
    final rawTable = rawLuaSlot(table);
    final rawValue = rawLuaSlot(value);
    final hasWeakMode = table.tableWeakMode != null;
    if (rawTable is TableStorage &&
        !hasWeakMode &&
        !table.hasMetamethod('__newindex') &&
        !table.hasMetamethod('__index') &&
        _isPlainPrimitiveValue(rawValue)) {
      if (rawValue == null) {
        rawTable.remove(rawKey);
      } else {
        rawTable[rawKey] = value;
      }
      table.markTableModified();
      return true;
    }
    if (rawTable is Map &&
        !hasWeakMode &&
        !table.hasMetamethod('__newindex') &&
        !table.hasMetamethod('__index') &&
        _isPlainPrimitiveValue(rawValue)) {
      if (rawValue == null) {
        rawTable.remove(rawKey);
      } else {
        rawTable[rawKey] = value;
      }
      table.markTableModified();
      return true;
    }
    return false;
  }

  bool _tryFastTableSet(Value table, Value key, Value value) {
    table.interpreter ??= runtime;
    key.interpreter ??= runtime;
    value.interpreter ??= runtime;
    final rawTable = rawLuaSlot(table);
    final rawValue = rawLuaSlot(value);
    final hasWeakMode = table.tableWeakMode != null;
    if (rawTable is TableStorage &&
        !hasWeakMode &&
        !table.hasMetamethod('__newindex') &&
        !table.hasMetamethod('__index')) {
      if (_plainPositiveIntegerKey(key) case final int index) {
        table.setNumericIndex(index, value);
        return true;
      }
      if (_canFastSetPlainPrimitiveEntry(key, value)) {
        final storageKey = _plainTableStorageKey(key);
        if (rawValue == null) {
          rawTable.remove(storageKey);
        } else {
          rawTable[storageKey] = value;
        }
        table.markTableModified();
        return true;
      }
      return false;
    }
    if (rawTable is Map &&
        !hasWeakMode &&
        !table.hasMetamethod('__newindex') &&
        !table.hasMetamethod('__index') &&
        _canFastSetPlainPrimitiveEntry(key, value)) {
      final storageKey = _plainTableStorageKey(key);
      if (rawValue == null) {
        rawTable.remove(storageKey);
      } else {
        rawTable[storageKey] = value;
      }
      table.markTableModified();
      return true;
    }
    return false;
  }

  Future<void> _tableSet(Value table, Value key, Value value) async {
    if (_tryFastTableSet(table, key, value)) {
      return;
    }
    final rawTable = rawLuaSlot(table);
    final hasWeakMode = table.tableWeakMode != null;
    if (rawTable is Map &&
        !hasWeakMode &&
        !table.hasMetamethod('__newindex') &&
        !table.hasMetamethod('__index')) {
      table[key] = value;
      return;
    }
    await table.setValueAsync(key, value);
  }

  Object? _plainTableStorageKey(Value key) {
    final rawKey = rawLuaSlot(key);
    return switch (rawKey) {
      final LuaString string => string.toString(),
      final num number => number == 0 ? 0.0 : number,
      final String string => string,
      final bool boolean => boolean,
      final BigInt integer => integer,
      _ => key,
    };
  }

  int? _plainPositiveIntegerKey(Value key) {
    final rawKey = rawLuaSlot(key);
    return switch (rawKey) {
      final int integer when integer > 0 => integer,
      final num number
          when number.isFinite &&
              number.toInt() > 0 &&
              number.toInt().toDouble() == number.toDouble() =>
        number.toInt(),
      _ => null,
    };
  }

  bool _canFastSetPlainPrimitiveEntry(Value key, Value value) {
    final rawKey = rawLuaSlot(key);
    final rawValue = rawLuaSlot(value);
    return _isPlainPrimitiveKey(rawKey) && _isPlainPrimitiveValue(rawValue);
  }

  bool _isPlainPrimitiveKey(Object? raw) =>
      raw != null && isLuaPrimitiveSlot(raw);

  bool _isPlainPrimitiveValue(Object? raw) => isLuaPrimitiveSlot(raw);

  LuaBytecodeInstructionWord _consumeExtraArg(_LuaBytecodeFrame frame) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      throw LuaError('missing EXTRAARG operand');
    }
    final extra = frame.closure.prototype.code[frame.pc++];
    if (extra.opcode != Opcode.extraArg) {
      throw LuaError('expected EXTRAARG after extending opcode');
    }
    return extra;
  }

  LuaBytecodeInstructionWord? _consumeOptionalZeroExtraArg(
    _LuaBytecodeFrame frame,
  ) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      return null;
    }
    final next = frame.closure.prototype.code[frame.pc];
    if (next.opcode == Opcode.extraArg &&
        next.ax == 0) {
      frame.pc++;
      return next;
    }
    return null;
  }

  List<Value> _normalizeResults(Object? result) {
    if (result == null) {
      return const <Value>[];
    }
    final resultValues = luaResultValues(result);
    if (resultValues != null) {
      return resultValues
          .map((item) => _runtimeValue(runtime, item))
          .toList(growable: false);
    }
    return switch (result) {
      final Value value => <Value>[_runtimeValue(runtime, value)],
      final List<Object?> values =>
        values
            .map((item) => _runtimeValue(runtime, item))
            .toList(growable: false),
      _ => <Value>[_runtimeValue(runtime, result)],
    };
  }
}

Object? _normalizeCloseErrorArgument(Object? error) {
  if (error case final Value value) {
    return switch (rawLuaSlot(value)) {
      final Value nested => _normalizeCloseErrorArgument(nested),
      _ => value,
    };
  }
  if (error case final LuaError luaError) {
    final cause = luaError.cause;
    if (cause != null && cause is! LuaError) {
      return _normalizeCloseErrorArgument(cause);
    }
    return luaError.message;
  }
  return error;
}

Object? _normalizeBytecodeCoroutineCloseError(Object error) {
  if (error is Value) {
    return error;
  }
  if (error is LuaError) {
    final cause = error.cause;
    if (cause != null &&
        cause is! LuaError &&
        cause.toString() == error.message) {
      return _normalizeBytecodeCoroutineCloseError(cause);
    }
    return error.message;
  }
  return error;
}

Object? _preserveCloseErrorObject(LuaRuntime runtime, Object? error) {
  if (error case LuaError(cause: final cause?) when cause is! LuaError) {
    return _preserveCloseErrorObject(runtime, cause);
  }
  if (error is Value) {
    return error;
  }
  if (error == null ||
      error is num ||
      error is BigInt ||
      error is bool ||
      error is String) {
    return valueFromLuaSlot(runtime, error);
  }
  return error;
}

Future<void> _closeFrameForCoroutine(
  _LuaBytecodeFrame frame, {
  int fromRegister = 0,
  required Object? error,
}) async {
  if (!frame.hasCloseWorkFrom(fromRegister)) {
    if (fromRegister == 0) {
      frame.closed = true;
    }
    return;
  }
  try {
    await frame.closeResources(fromRegister: fromRegister, error: error);
  } on LuaError catch (luaError) {
    final cause = luaError.cause;
    if (cause != null && cause is! LuaError && cause is! UnsupportedError) {
      throw cause;
    }
    rethrow;
  }
}

Future<T> _withProtectedCallResume<T>(
  LuaRuntime runtime,
  bool resumeInProtectedCall,
  Future<T> Function() action,
) async {
  if (!resumeInProtectedCall) {
    return action();
  }
  runtime.enterProtectedCall();
  try {
    return await action();
  } finally {
    runtime.exitProtectedCall();
  }
}

CoroutineContinuation _wrapFrameContinuation(
  LuaBytecodeVm vm,
  _LuaBytecodeFrame frame,
  bool resumeInProtectedCall,
  CoroutineContinuation? child,
) {
  if (child case final _LuaBytecodeFrameSuspension suspension
      when identical(suspension.frame, frame) &&
          suspension.resumeInProtectedCall == resumeInProtectedCall) {
    return suspension;
  }
  return _LuaBytecodeFrameSuspension(
    vm: vm,
    frame: frame,
    resumeInProtectedCall: resumeInProtectedCall,
    child: child,
  );
}

void _tmpDebugFrame(_LuaBytecodeFrame frame, String message) {
  if (platform.getEnvironmentVariable('LUALIKE_DEBUG_BYTECODE_CONT') == '1') {
    print(
      '[bc-cont] pc=${frame.pc} top=${frame.top} openTop=${frame.openTop} '
      'closed=${frame.closed} $message',
    );
  }
}

_LuaBytecodeFrame? _tmpContinuationFrame(CoroutineContinuation continuation) {
  return switch (continuation) {
    _LuaBytecodeCallSuspension(:final frame) => frame,
    _LuaBytecodeConcatSuspension(:final frame) => frame,
    _LuaBytecodeConditionalJumpSuspension(:final frame) => frame,
    _LuaBytecodeFrameSuspension(:final frame) => frame,
    _LuaBytecodeResumeOnlySuspension(:final frame) => frame,
    _LuaBytecodeStoreRegisterSuspension(:final frame) => frame,
    _LuaBytecodeCloseSuspension(:final frame) => frame,
    _LuaBytecodeReturnSuspension(:final frame) => frame,
    _LuaBytecodeTailCallSuspension(:final frame) => frame,
    _LuaBytecodeTForCallSuspension(:final frame) => frame,
    _ => null,
  };
}

CoroutineContinuation? _bytecodeContinuationChild(
  CoroutineContinuation continuation,
) {
  return switch (continuation) {
    _LuaBytecodeCallSuspension(:final child) => child,
    _LuaBytecodeConcatSuspension(:final child) => child,
    _LuaBytecodeProtectedCallSuspension(:final child) => child,
    _LuaBytecodeCloseSuspension(:final child) => child,
    _LuaBytecodeFrameSuspension(:final child) => child,
    _LuaBytecodeReturnSuspension(:final child) => child,
    _LuaBytecodeTailCallSuspension(:final child) => child,
    _LuaBytecodeTForCallSuspension(:final child) => child,
    _ => null,
  };
}

CallFrame _bytecodeSuspendedDebugFrame(_LuaBytecodeFrame frame) {
  final closure = frame.closure;
  final functionName = switch (frame.callName) {
    final String name when name.isNotEmpty => name,
    _ when closure.debugInfo.what == 'main' => 'main',
    _ => 'unknown',
  };
  final callable = Value(
    closure,
    functionBody: closure.debugFunctionBody,
    closureEnvironment: closure.environment,
    functionName: functionName,
  )..interpreter = frame.runtime;
  final currentPc = frame.pc <= 0 ? 0 : frame.pc - 1;
  final currentLine = closure.prototype.lineForPc(currentPc) ?? -1;
  final callFrame = CallFrame(
    functionName,
    scriptPath: closure.prototype.source,
    currentLine: currentLine,
    env: frame.debugEnvironment,
    debugName: frame.callName,
    debugNameWhat: frame.callNameWhat ?? '',
    callable: callable,
    extraArgs: frame.extraArgs,
    isDebugHook: frame.callName == 'hook' || frame.callNameWhat == 'hook',
    isTailCall: frame.isTailCall,
  );
  _bindBytecodeCallFrame(callFrame, frame);
  final activeLocals =
      <LuaBytecodeLocalVariableDebugInfo>[
        for (final local in closure.prototype.localVariables)
          if (local.register != null &&
              local.startPc <= frame.pc + 1 &&
              frame.pc + 1 < local.endPc)
            local,
      ]..sort((left, right) {
        final startOrder = left.startPc.compareTo(right.startPc);
        if (startOrder != 0) {
          return startOrder;
        }
        final leftRegister = left.register ?? -1;
        final rightRegister = right.register ?? -1;
        final registerOrder = leftRegister.compareTo(rightRegister);
        if (registerOrder != 0) {
          return registerOrder;
        }
        return (left.name ?? '').compareTo(right.name ?? '');
      });
  callFrame.debugLocals
    ..clear()
    ..addAll([
      for (final local in activeLocals)
        if (local.register case final register?)
          MapEntry(local.name ?? '(local)', frame.register(register)),
    ]);
  return callFrame;
}

List<CallFrame> _bytecodeSuspendedContinuationFrames(
  CoroutineContinuation? continuation, {
  int startLevel = 1,
}) {
  if (startLevel <= 0) {
    startLevel = 1;
  }
  if (continuation == null) {
    return const <CallFrame>[];
  }
  final frames = <CallFrame>[];
  final seenFrames = <_LuaBytecodeFrame>{};
  void walk(CoroutineContinuation? current) {
    if (current == null) {
      return;
    }
    if (_tmpContinuationFrame(current) case final frame?) {
      if (seenFrames.add(frame)) {
        frames.add(_bytecodeSuspendedDebugFrame(frame));
      }
    }
    walk(_bytecodeContinuationChild(current));
  }

  walk(continuation);
  final visibleFrames = frames
      .where((frame) => !frame.isDebugHook && frame.debugNameWhat != 'hook')
      .toList(growable: false)
      .reversed
      .toList(growable: false);
  if (startLevel > visibleFrames.length) {
    return const <CallFrame>[];
  }
  return visibleFrames.skip(startLevel - 1).toList(growable: false);
}

void _installBytecodeContinuation(
  Coroutine coroutine,
  CoroutineContinuation continuation,
) {
  coroutine.installContinuation(continuation);
}

List<CallFrame> bytecodeSuspendedCoroutineFrames(
  Coroutine coroutine, {
  int startLevel = 1,
}) {
  return _bytecodeSuspendedContinuationFrames(
    coroutine.debugContinuation,
    startLevel: startLevel,
  );
}

List<Object?>? _frameDebugVarargs(CallFrame frame) {
  if (_bytecodeFrameForCallFrame(frame) case final bytecodeFrame?) {
    if (!bytecodeFrame.closure.prototype.isVararg) {
      return null;
    }
    return List<Object?>.from(bytecodeFrame.expandedVarargs);
  }
  Environment? env = frame.env;
  final closureEnv = frame.callable?.closureEnvironment;
  while (env != null) {
    final value = env.values['...']?.value;
    final values = luaResultValues(value);
    if (values != null) {
      return List<Object?>.from(values);
    }
    if (identical(env, closureEnv) || identical(env.parent, closureEnv)) {
      break;
    }
    env = env.parent;
  }
  return null;
}

CallFrame? _resolveVisibleBytecodeFrame(LuaRuntime runtime, int level) {
  if (level <= 0) {
    return null;
  }
  Interpreter? debugInterpreter;
  try {
    final candidate = (runtime as dynamic).debugInterpreter;
    if (candidate is Interpreter) {
      debugInterpreter = candidate;
    }
  } catch (_) {
    // Leave null and fall back to the non-bytecode builtin path.
  }
  if (debugInterpreter == null) {
    return null;
  }

  // The bytecode fast path does not push a managed frame for `debug.getlocal`
  // itself, so stack levels here are already relative to the caller. Reuse the
  // interpreter's visible-frame walk so mixed bytecode/AST stacks keep hook
  // helpers, lexical wrappers, and hidden debug frames aligned with the
  // standard debug library semantics.
  return debugInterpreter.getVisibleFrameAtLevel(
    level,
    hideEnclosingDebugHooks: true,
  );
}

void _syncFrameDebugVarargs(CallFrame? frame, List<Object?> values) {
  if (frame == null) {
    return;
  }
  if (_bytecodeFrameForCallFrame(frame) case final bytecodeFrame?) {
    final normalized = values
        .map(
          (value) => value is Value
              ? value
              : _runtimeValue(bytecodeFrame.runtime, value),
        )
        .toList(growable: true);
    bytecodeFrame._materializedVarargs = normalized;
    bytecodeFrame._varargStart = 0;
    bytecodeFrame._varargCount = normalized.length;
    if (bytecodeFrame.debugVarargValue != null) {
      bytecodeFrame.updateDebugVarargValue(normalized);
    }
    return;
  }
  Environment? env = frame.env;
  final closureEnv = frame.callable?.closureEnvironment;
  while (env != null) {
    final box = env.values['...'];
    final value = box?.value;
    if (value is LuaResults) {
      box!.value = LuaResults(values);
      return;
    }
    if (value is Value && value.multiResults != null) {
      value.raw = values;
      return;
    }
    if (identical(env, closureEnv) || identical(env.parent, closureEnv)) {
      break;
    }
    env = env.parent;
  }
}

Value _bytecodeFrameNilValue(CallFrame frame) {
  return frame.env?.interpreter?.constantPrimitiveValue(null) ??
      frame.callable?.interpreter?.constantPrimitiveValue(null) ??
      Value.primitive(null);
}

List<MapEntry<String, Value>> _bytecodeFrameLocals(CallFrame frame) {
  final locals = <MapEntry<String, Value>>[];
  final nilValue = _bytecodeFrameNilValue(frame);
  final closure = rawLuaSlot(frame.callable);
  final isMainChunkFrame =
      closure is LuaBytecodeClosure && closure.debugInfo.what == 'main';
  if (!isMainChunkFrame && _frameDebugVarargs(frame) != null) {
    locals.add(MapEntry('(vararg table)', nilValue));
  }
  locals.addAll(frame.debugLocals);
  if (closure is LuaBytecodeClosure && frame.currentLine > 0) {
    final hasTemporaryPlaceholder = locals.any(
      (entry) => entry.key == '(temporary)',
    );
    if (!hasTemporaryPlaceholder &&
        closure.prototype.localVariables.any(
          (local) => _localHasPendingClosureTemporaryOnCurrentLine(
            closure.prototype,
            local,
            frame.currentLine,
          ),
        )) {
      locals.add(MapEntry('(temporary)', nilValue));
    }
    final seenNames = <String>{
      for (final entry in locals)
        if (entry.key != '(temporary)' && entry.key != '(vararg table)')
          entry.key,
    };
    final placeholders =
        <LuaBytecodeLocalVariableDebugInfo>[
          for (final local in closure.prototype.localVariables)
            if (local.name case final String name
                when name.isNotEmpty &&
                    !name.startsWith('(') &&
                    !seenNames.contains(name) &&
                    _localStartsOnCurrentLine(
                      closure.prototype,
                      local,
                      frame.currentLine,
                    ))
              local,
        ]..sort((left, right) {
          final startOrder = left.startPc.compareTo(right.startPc);
          if (startOrder != 0) {
            return startOrder;
          }
          final leftRegister = left.register ?? -1;
          final rightRegister = right.register ?? -1;
          final registerOrder = leftRegister.compareTo(rightRegister);
          if (registerOrder != 0) {
            return registerOrder;
          }
          return (left.name ?? '').compareTo(right.name ?? '');
        });
    for (final local in placeholders) {
      locals.add(MapEntry(local.name!, nilValue));
    }
  }
  return locals;
}

bool _localStartsOnCurrentLine(
  LuaBytecodePrototype prototype,
  LuaBytecodeLocalVariableDebugInfo local,
  int currentLine,
) {
  final startPc = local.startPc;
  if (startPc >= prototype.code.length) {
    return prototype.lineDefined > 0 && currentLine == prototype.lineDefined;
  }
  final directLine = startPc < prototype.code.length
      ? prototype.lineForPc(startPc)
      : null;
  if (directLine == currentLine) {
    return true;
  }
  if (startPc > 0) {
    final previousLine = prototype.lineForPc(startPc - 1);
    if (previousLine == currentLine) {
      return true;
    }
  }
  return false;
}

bool _localHasPendingClosureTemporaryOnCurrentLine(
  LuaBytecodePrototype prototype,
  LuaBytecodeLocalVariableDebugInfo local,
  int currentLine,
) {
  final register = local.register;
  if (register == null) {
    return false;
  }
  final closurePc = local.startPc - 2;
  if (closurePc < 0 || closurePc >= prototype.code.length) {
    return false;
  }
  if (prototype.lineForPc(closurePc) != currentLine) {
    return false;
  }
  final word = prototype.code[closurePc];
  return word.opcode == Opcode.closure && word.a == register;
}

void _overwriteValue(Value target, Value source) {
  target.raw = rawLuaSlot(source);
  target.metatable = source.metatable;
  target.metatableRef = source.metatableRef;
  target.upvalues = source.upvalues;
  target.interpreter = source.interpreter;
  target.functionBody = source.functionBody;
  target.closureEnvironment = source.closureEnvironment;
  target.functionName = source.functionName;
  target.debugLineDefined = source.debugLineDefined;
}

final class _LuaBytecodeFrame implements LuaBytecodeGCRootProvider {
  _LuaBytecodeFrame({
    required this.runtime,
    required this.closure,
    this.functionValue,
    required List<Object?> arguments,
    this.callName,
    this.callNameWhat,
    required this.isEntryFrame,
    this.isTailCall = false,
    this.extraArgs = 0,
  }) : registers = List<Value>.generate(
         closure.prototype.maxStackSize,
         (_) => runtime.constantPrimitiveValue(null),
         growable: true,
       ),
       _lastRegisterWritePc = List<int>.filled(
         closure.prototype.maxStackSize,
         -1,
         growable: true,
       ),
       _materializedVarargs = null {
    top = closure.prototype.parameterCount;
    final normalizedArgs = arguments
        .map((argument) => _runtimeValue(runtime, argument))
        .toList(growable: false);
    callArgs = normalizedArgs;
    final parameterCount = closure.prototype.parameterCount;
    for (var index = 0; index < parameterCount; index++) {
      final value = index < normalizedArgs.length
          ? normalizedArgs[index]
          : _runtimeValue(runtime, null);
      setRegister(index, value);
    }
    if (closure.prototype.isVararg) {
      _varargStart = parameterCount;
      _varargCount = normalizedArgs.length > parameterCount
          ? normalizedArgs.length - parameterCount
          : 0;
      if (closure.prototype.needsVarargTable) {
        _materializedVarargs = List<Value>.of(
          normalizedArgs.skip(parameterCount),
          growable: true,
        );
      }
    }
    if (closure.prototype.needsVarargTable) {
      final packed = packVarargsTable(varargs, runtime: runtime);
      setRegister(parameterCount, packed);
      if (rawLuaSlot(packed) case final PackedVarargTable table) {
        namedVarargTable = table;
        namedVarargTableValue = packed;
      }
    }
  }

  final LuaRuntime runtime;
  final LuaBytecodeClosure closure;
  final Value? functionValue;
  final String? callName;
  final String? callNameWhat;
  final bool isEntryFrame;
  final bool isTailCall;
  final int extraArgs;
  late final List<Value> callArgs;
  late final Iterable<Object?> Function() externalGcRootProvider = gcReferences;
  final List<Value> registers;
  final List<int> _lastRegisterWritePc;
  List<Value>? _materializedVarargs;
  LuaResults? debugVarargValue;
  Environment? _debugEnvironment;
  PackedVarargTable? namedVarargTable;
  Value? namedVarargTableValue;
  late final List<bool> _localExpiryFlags = () {
    final flags = List<bool>.filled(
      closure.prototype.code.length,
      false,
      growable: false,
    );
    for (final local in closure.prototype.localVariables) {
      if (local.register == null || local.endPc <= local.startPc) {
        continue;
      }
      final endPc = local.endPc;
      if (endPc >= 0 && endPc < flags.length) {
        flags[endPc] = true;
      }
    }
    return flags;
  }();
  late final List<List<({int register, int endPc})>>
  _expiredRegisterCandidatesByPc = () {
    final codeLength = closure.prototype.code.length;
    final startRegistersByPc = List<List<int>>.generate(
      codeLength,
      (_) => <int>[],
      growable: false,
    );
    final endRegistersByPc = List<List<({int register, int endPc})>>.generate(
      codeLength,
      (_) => <({int register, int endPc})>[],
      growable: false,
    );
    for (final local in closure.prototype.localVariables) {
      final register = local.register;
      if (register == null) {
        continue;
      }
      final startPc = local.startPc;
      if (startPc >= 0 && startPc < codeLength) {
        startRegistersByPc[startPc].add(register);
      }
      final endPc = local.endPc;
      if (endPc >= 0 && endPc < codeLength) {
        endRegistersByPc[endPc].add((register: register, endPc: endPc));
      }
    }

    final activeCounts = <int, int>{};
    final latestExpiredEndPcByRegister = <int, int>{};
    final candidatesByPc = List<List<({int register, int endPc})>>.generate(
      codeLength,
      (_) => <({int register, int endPc})>[],
      growable: false,
    );

    for (var pc = 0; pc < codeLength; pc++) {
      for (final (:register, :endPc) in endRegistersByPc[pc]) {
        final nextCount = (activeCounts[register] ?? 0) - 1;
        if (nextCount > 0) {
          activeCounts[register] = nextCount;
        } else {
          activeCounts.remove(register);
        }
        final previousEndPc = latestExpiredEndPcByRegister[register];
        if (previousEndPc == null || endPc > previousEndPc) {
          latestExpiredEndPcByRegister[register] = endPc;
        }
      }
      for (final register in startRegistersByPc[pc]) {
        activeCounts[register] = (activeCounts[register] ?? 0) + 1;
      }
      if (!_localExpiryFlags[pc]) {
        continue;
      }
      candidatesByPc[pc] = <({int register, int endPc})>[
        for (final entry in latestExpiredEndPcByRegister.entries)
          if ((activeCounts[entry.key] ?? 0) == 0)
            (register: entry.key, endPc: entry.value),
      ];
    }
    return candidatesByPc;
  }();
  late final List<bool> _trackedRegisterWriteFlags = () {
    final flags = List<bool>.filled(
      closure.prototype.maxStackSize,
      false,
      growable: true,
    );
    for (final local in closure.prototype.localVariables) {
      final register = local.register;
      if (register == null) {
        continue;
      }
      if (register >= flags.length) {
        flags.addAll(
          List<bool>.filled(
            register - flags.length + 1,
            false,
            growable: false,
          ),
        );
      }
      flags[register] = true;
    }
    return flags;
  }();
  late final List<({int start, int? end})?> _writtenRegisterRangesByPc =
      _writtenRegisterRangesByPcFor(closure.prototype);
  late final List<LuaBytecodeLocalVariableDebugInfo> sortedDebugLocals =
      _sortedDebugLocalsFor(closure.prototype);
  late final List<Map<int, String>> _activeNamedLocalsByPc =
      _activeNamedLocalsByPcFor(closure.prototype);
  late final List<_LuaBytecodeDebugLocalWindow> _activeDebugLocalsByPc =
      _activeDebugLocalsByPcFor(closure.prototype);
  late final List<Map<int, String>> _visibleNamedLocalsByPc = () {
    final codeLength = closure.prototype.code.length;
    final startsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
      codeLength,
      (_) => <LuaBytecodeLocalVariableDebugInfo>[],
      growable: false,
    );
    final endsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
      codeLength,
      (_) => <LuaBytecodeLocalVariableDebugInfo>[],
      growable: false,
    );
    for (final local in closure.prototype.localVariables) {
      if (local.register == null) {
        continue;
      }
      final startPc = local.startPc;
      if (startPc >= 0 && startPc < codeLength) {
        startsByPc[startPc].add(local);
      }
      final endPc = local.endPc;
      if (endPc >= 0 && endPc < codeLength) {
        endsByPc[endPc].add(local);
      }
    }

    final activeLocalsByRegister =
        <int, List<LuaBytecodeLocalVariableDebugInfo>>{};
    var currentVisibleLocals = const <int, String>{};
    final snapshots = List<Map<int, String>>.filled(
      codeLength,
      const <int, String>{},
      growable: false,
    );

    Map<int, String> snapshotVisibleLocals() {
      if (activeLocalsByRegister.isEmpty) {
        return const <int, String>{};
      }
      final visibleLocals = <int, String>{};
      for (final entry in activeLocalsByRegister.entries) {
        for (final local in entry.value) {
          final name = local.name;
          if (name == null || name.isEmpty || name.startsWith('(')) {
            continue;
          }
          visibleLocals[entry.key] = name;
          break;
        }
      }
      return visibleLocals.isEmpty ? const <int, String>{} : visibleLocals;
    }

    for (var pc = 0; pc < codeLength; pc++) {
      var changed = false;
      for (final local in endsByPc[pc]) {
        final register = local.register!;
        final locals = activeLocalsByRegister[register];
        if (locals == null) {
          continue;
        }
        locals.remove(local);
        if (locals.isEmpty) {
          activeLocalsByRegister.remove(register);
        }
        changed = true;
      }
      for (final local in startsByPc[pc]) {
        final register = local.register!;
        activeLocalsByRegister
            .putIfAbsent(register, () => <LuaBytecodeLocalVariableDebugInfo>[])
            .add(local);
        changed = true;
      }
      if (changed) {
        currentVisibleLocals = snapshotVisibleLocals();
      }
      snapshots[pc] = currentVisibleLocals;
    }

    return snapshots;
  }();
  late final List<Set<int>> _environmentRegistersByPc =
      _environmentRegistersByPcFor(closure.prototype);
  final List<_LuaBytecodeUpvalue> _openUpvalues = <_LuaBytecodeUpvalue>[];
  final Set<int> _toBeClosedRegisters = <int>{};
  var _varargStart = 0;
  var _varargCount = 0;

  var pc = 0;
  var top = 0;
  int? openTop;
  var safePointCounter = 0;
  var debugStateVersion = 0;
  var loopGcCounter = 0;
  var closed = false;
  var didFireEntryCallHook = false;
  var forceNextLineHook = false;

  int get effectiveTop => openTop ?? top;

  Environment get debugEnvironment {
    final existing = _debugEnvironment;
    if (existing != null) {
      return existing;
    }
    final environment = Environment(
      parent: closure.environment,
      interpreter: runtime,
    );
    if (_materializeDebugVarargValue() case final LuaResults varargValue) {
      environment.declare('...', varargValue);
    }
    _debugEnvironment = environment;
    return environment;
  }

  LuaResults? _materializeDebugVarargValue() {
    final existing = debugVarargValue;
    if (existing != null) {
      return existing;
    }
    if (!closure.prototype.isVararg) {
      return null;
    }
    final value = LuaResults(varargs);
    debugVarargValue = value;
    return value;
  }

  void updateDebugVarargValue(Iterable<Object?> values) {
    final value = LuaResults(values);
    debugVarargValue = value;
    _debugEnvironment?.values['...']?.value = value;
  }

  int get varargCount => switch (namedVarargTable) {
    final PackedVarargTable table => table.expandedCount(),
    _ => _materializedVarargs?.length ?? _varargCount,
  };

  Value? varargAt(int index) {
    if (index < 0 || index >= varargCount) {
      return null;
    }
    if (namedVarargTable case final PackedVarargTable table) {
      final value = table[index + 1];
      return _runtimeValue(runtime, value);
    }
    final materialized = _materializedVarargs;
    if (materialized != null) {
      return materialized[index];
    }
    return callArgs[_varargStart + index];
  }

  List<Value> get varargs => _materializedVarargs ??= List<Value>.generate(
    _varargCount,
    (index) => callArgs[_varargStart + index],
    growable: true,
  );

  Value register(int index) => slotValue(index);

  Value slotValue(int index) => index < registers.length
      ? registers[index]
      : _runtimeValue(runtime, null);

  void setRegister(int index, Value value) {
    if (index >= registers.length) {
      registers.addAll(
        List<Value>.generate(
          index - registers.length + 1,
          (_) => runtime.constantPrimitiveValue(null),
          growable: false,
        ),
      );
      _lastRegisterWritePc.addAll(
        List<int>.filled(index - _lastRegisterWritePc.length + 1, -1),
      );
      _trackedRegisterWriteFlags.addAll(
        List<bool>.filled(
          index - _trackedRegisterWriteFlags.length + 1,
          false,
          growable: false,
        ),
      );
    }
    // Always clone shared runtime constants before storing them in a
    // register even when they wrap a scalar primitive.  The resulting
    // Value must be mutable because later operations such as
    // debug.setlocal rely on _overwriteValue to mutate the register
    // value in-place (target.raw = …).  Skipping the clone for scalar
    // primitives would leave a shared-primitive Value in the register,
    // and _overwriteValue would throw when it tries to set `raw` on a
    // shared primitive.
    final storedValue =
        !value.skipAllocationDebt && _isSharedRuntimeConstant(runtime, value)
        ? _cloneBytecodeValue(value)
        : value;
    storedValue.interpreter ??= runtime;
    registers[index] = storedValue;
    debugStateVersion++;
    final gc = runtime.gc;
    if (gc.isCycleActive) {
      gc.noteRootWrite(storedValue);
    }
    if (index < _trackedRegisterWriteFlags.length &&
        _trackedRegisterWriteFlags[index]) {
      _lastRegisterWritePc[index] = pc;
    }
    if (index + 1 > top) {
      top = index + 1;
    }
  }

  List<Value> resultsFrom(int start, int count) {
    if (count <= 0) {
      return const <Value>[];
    }
    final end = start + count;
    if (start >= registers.length) {
      return List<Value>.generate(
        count,
        (_) => _runtimeValue(runtime, null),
        growable: false,
      );
    }
    if (end <= registers.length) {
      return registers.sublist(start, end);
    }
    final values = registers.sublist(start);
    values.addAll(
      List<Value>.generate(
        end - registers.length,
        (_) => _runtimeValue(runtime, null),
        growable: false,
      ),
    );
    return values;
  }

  List<Value> get expandedVarargs {
    if (namedVarargTable case final PackedVarargTable table) {
      final count = table.expandedCount();
      if (count == varargs.length) {
        return varargs;
      }
      final expanded = table
          .expandedValues()
          .map((value) => _runtimeValue(runtime, value))
          .toList(growable: false);
      if (debugVarargValue != null) {
        updateDebugVarargValue(expanded);
      }
      return expanded;
    }
    if (debugVarargValue case final LuaResults rawVarargs) {
      final rawList = rawVarargs.values;
      if (identical(rawList, varargs)) {
        return varargs;
      }
      final normalized = rawList
          .map((value) => _runtimeValue(runtime, value))
          .toList(growable: false);
      updateDebugVarargValue(normalized);
      return normalized;
    }
    return varargs;
  }

  String? activeLocalName(int registerIndex) {
    return activeLocalNameAt(registerIndex, pc);
  }

  String? localNameForError(int registerIndex) {
    for (final targetPc in <int>[pc, pc - 1, pc + 1]) {
      final localName = activeLocalNameAt(registerIndex, targetPc);
      if (localName != null) {
        return localName;
      }
      var inferredRegister = 0;
      for (final local in sortedDebugLocals) {
        if (local.register != null ||
            targetPc < local.startPc - 1 ||
            targetPc >= local.endPc) {
          continue;
        }
        final name = local.name;
        if (name == null || name.isEmpty || name.startsWith('(')) {
          continue;
        }
        if (inferredRegister == registerIndex) {
          return name;
        }
        inferredRegister++;
      }
    }
    LuaBytecodeLocalVariableDebugInfo? fallback;
    for (final local in sortedDebugLocals) {
      if (local.register != registerIndex || local.name == null) {
        continue;
      }
      final name = local.name!;
      if (name.isEmpty || name.startsWith('(')) {
        continue;
      }
      fallback ??= local;
      if (pc >= local.startPc - 1 && pc <= local.endPc) {
        return name;
      }
    }
    if (fallback case final local?) {
      return local.name;
    }
    return null;
  }

  String? activeLocalNameAt(int registerIndex, int targetPc) {
    if (targetPc < 0 || targetPc >= _activeNamedLocalsByPc.length) {
      return null;
    }
    return _activeNamedLocalsByPc[targetPc][registerIndex];
  }

  Map<int, String> get activeNamedLocals {
    return activeNamedLocalsAt(pc);
  }

  Map<int, String> activeNamedLocalsAt(int targetPc) {
    if (targetPc < 0 || targetPc >= _activeNamedLocalsByPc.length) {
      return const <int, String>{};
    }
    return _activeNamedLocalsByPc[targetPc];
  }

  Map<int, String> get visibleNamedLocals {
    final currentPc = pc;
    if (currentPc < 0 || currentPc >= _visibleNamedLocalsByPc.length) {
      return const <int, String>{};
    }
    return _visibleNamedLocalsByPc[currentPc];
  }

  _LuaBytecodeDebugLocalWindow activeDebugLocalWindowAt(int targetPc) {
    if (targetPc < 0 || targetPc >= _activeDebugLocalsByPc.length) {
      return _debugLocalWindowForPc(sortedDebugLocals, targetPc);
    }
    return _activeDebugLocalsByPc[targetPc];
  }

  bool isEnvironmentLocalRegister(int registerIndex) {
    final currentPc = pc;
    if (currentPc < 0 || currentPc >= _environmentRegistersByPc.length) {
      return false;
    }
    return _environmentRegistersByPc[currentPc].contains(registerIndex);
  }

  bool instructionWritesRegister(int instructionPc, int registerIndex) {
    if (instructionPc < 0 ||
        instructionPc >= _writtenRegisterRangesByPc.length) {
      return false;
    }
    final range = _writtenRegisterRangesByPc[instructionPc];
    if (range == null) {
      return false;
    }
    final start = range.start;
    final end = range.end;
    return end == null
        ? registerIndex >= start
        : registerIndex >= start && registerIndex <= end;
  }

  void expireDeadLocals() {
    final currentPc = pc;
    if (currentPc < 0 ||
        currentPc >= _localExpiryFlags.length ||
        !_localExpiryFlags[currentPc]) {
      return;
    }
    final registersToClear = _expiredRegisterCandidatesByPc[currentPc];
    if (registersToClear.isEmpty) {
      return;
    }

    for (final (:register, :endPc) in registersToClear) {
      final registerIndex = register;
      if (registerIndex >= registers.length) {
        continue;
      }
      if (_toBeClosedRegisters.contains(registerIndex)) {
        continue;
      }
      if (_openUpvalues.any(
        (upvalue) => upvalue.isOpen && upvalue.registerIndex == registerIndex,
      )) {
        continue;
      }
      if (_lastRegisterWritePc[registerIndex] >= endPc) {
        continue;
      }
      final value = registers[registerIndex];
      if (rawLuaSlot(value) == null && !value.isToBeClose) {
        continue;
      }
      registers[registerIndex] = _runtimeValue(runtime, null);
    }
  }

  _LuaBytecodeUpvalue captureUpvalue(int registerIndex) {
    for (final upvalue in _openUpvalues) {
      if (upvalue.registerIndex == registerIndex && upvalue.isOpen) {
        return upvalue;
      }
    }
    final upvalue = _LuaBytecodeUpvalue.open(this, registerIndex);
    _openUpvalues.add(upvalue);
    return upvalue;
  }

  void markToBeClosed(int registerIndex) {
    final rawValue = _detachSharedRuntimeConstantInFrameRegister(
      this,
      registerIndex,
    );
    if (_debugFileOps) {
      final raw = rawLuaSlot(rawValue);
      _debugFileLog(
        'markToBeClosed register=$registerIndex '
        'tbc=${rawValue.isToBeClose} raw=${raw.runtimeType}',
      );
    }
    final raw = rawLuaSlot(rawValue);
    if (raw == null || raw == false) {
      _toBeClosedRegisters.add(registerIndex);
      return;
    }
    try {
      final closable = rawValue.isToBeClose
          ? rawValue
          : Value.toBeClose(rawValue);
      setRegister(registerIndex, closable);
      _toBeClosedRegisters.add(registerIndex);
    } on UnsupportedError catch (error) {
      final localName = localNameForError(registerIndex);
      final baseMessage = error.message ?? error.toString();
      final message =
          localName != null &&
              baseMessage ==
                  'to-be-closed variable value must have a __close metamethod'
          ? "variable '$localName' got a non-closable value"
          : baseMessage;
      // Do NOT pass cause: the UnsupportedError as cause would be
      // unwrapped by the protected-call error path when isInProtectedCall
      // is true, causing pcall to surface the raw Dart exception instead
      // of the formatted Lua message.
      throw LuaError(message);
    }
  }

  Future<void> closeResources({
    required int fromRegister,
    Object? error,
  }) async {
    final registersToClose =
        _toBeClosedRegisters
            .where((registerIndex) => registerIndex >= fromRegister)
            .toList(growable: false)
          ..sort((left, right) => right.compareTo(left));

    var currentError = error;
    Object? closeError;
    StackTrace? closeStackTrace;
    for (final registerIndex in registersToClose) {
      if (!_toBeClosedRegisters.remove(registerIndex)) {
        continue;
      }
      final slotValue = this.slotValue(registerIndex);
      final rawSlotValue = rawLuaSlot(slotValue);
      if (rawSlotValue == null || rawSlotValue == false) {
        continue;
      }
      final Value closeValue;
      try {
        final mutableSlotValue = _detachSharedRuntimeConstantInFrameRegister(
          this,
          registerIndex,
        );
        closeValue = mutableSlotValue.isToBeClose
            ? mutableSlotValue
            : Value.toBeClose(mutableSlotValue);
      } on UnsupportedError catch (error, stackTrace) {
        final localName = localNameForError(registerIndex);
        final message = localName != null
            ? "variable '$localName' got a non-closable value"
            : (error.message ?? error.toString());
        // Do NOT pass cause: the UnsupportedError as cause would be
        // unwrapped by the protected-call error path when isInProtectedCall
        // is true, surfacing the raw Dart exception via pcall.
        Error.throwWithStackTrace(LuaError(message), stackTrace);
      }
      closeValue.interpreter ??= runtime;
      try {
        await closeValue.close(_normalizeCloseErrorArgument(currentError));
      } on YieldException {
        rethrow;
      } catch (caughtError, caughtStackTrace) {
        currentError = caughtError;
        closeError = caughtError;
        closeStackTrace = caughtStackTrace;
      }
    }
    closeUpvalues(fromRegister: fromRegister);
    if (fromRegister == 0) {
      closed = true;
    }
    if (closeError != null && closeStackTrace != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace);
    }
  }

  void closeUpvalues({required int fromRegister}) {
    final toClose = <_LuaBytecodeUpvalue>[
      for (final upvalue in _openUpvalues)
        if (upvalue.isOpen && upvalue.registerIndex >= fromRegister) upvalue,
    ];
    for (final upvalue in toClose) {
      upvalue.close();
    }
    _openUpvalues.removeWhere((upvalue) => !upvalue.isOpen);
  }

  bool hasCloseWorkFrom(int fromRegister) {
    if (_toBeClosedRegisters.any(
      (registerIndex) => registerIndex >= fromRegister,
    )) {
      return true;
    }
    return _openUpvalues.any(
      (upvalue) => upvalue.isOpen && upvalue.registerIndex >= fromRegister,
    );
  }

  bool isLiveToBeClosedAlias(Value value) {
    final rawValue = rawLuaSlot(value);
    for (final registerIndex in _toBeClosedRegisters) {
      if (registerIndex >= registers.length) {
        continue;
      }
      final liveValue = registers[registerIndex];
      if (identical(liveValue, value)) {
        return true;
      }
      if (rawValue != null && identical(rawLuaSlot(liveValue), rawValue)) {
        return true;
      }
    }
    return false;
  }

  @override
  Iterable<GCObject> gcReferences() sync* {
    yield closure.environment;
    if (_debugEnvironment case final Environment environment) {
      yield environment;
    }
    // Match Lua's stack-root model: keep only the live stack window, open
    // upvalues, to-be-closed slots, and locals whose debug scope is currently
    // active. Stale register contents outside those ranges should not keep
    // collectable values alive.
    final currentPc = pc;
    final liveRegisters = <int>{
      for (var index = 0; index < top; index++) index,
      if (openTop case final openTop?)
        for (var index = 0; index < openTop; index++) index,
      for (final upvalue in _openUpvalues)
        if (upvalue.isOpen) upvalue.registerIndex,
      ..._toBeClosedRegisters,
      for (final local in closure.prototype.localVariables)
        if (local.startPc <= currentPc && currentPc < local.endPc)
          ?local.register,
    };
    for (final registerIndex in liveRegisters.toList()..sort()) {
      if (registerIndex < registers.length) {
        yield slotValue(registerIndex);
      }
    }
    for (final value in expandedVarargs) {
      yield value;
    }
    if (namedVarargTableValue case final value?) {
      yield value;
    }
  }
}

final class _LuaBytecodeCallSuspension implements CoroutineContinuation {
  const _LuaBytecodeCallSuspension({
    required this.vm,
    required this.frame,
    required this.register,
    required this.resultSpec,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int register;
  final int resultSpec;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(vm.runtime, resumeInProtectedCall, () async {
      late final List<Value> results;
      try {
        results = await _resumeResults(args);
        _tmpDebugFrame(
          frame,
          'call-resume register=$register resultSpec=$resultSpec '
          'results=${results.map((v) => "${rawLuaSlot(v).runtimeType}:${v.isMulti}").join(",")} '
          'top=${frame.top} openTop=${frame.openTop} pc=${frame.pc}',
        );
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _installBytecodeContinuation(
            coroutine,
            _LuaBytecodeCallSuspension(
              vm: vm,
              frame: frame,
              register: register,
              resultSpec: resultSpec,
              resumeInProtectedCall: resumeInProtectedCall,
              child: nextChild,
            ),
          );
        }
        rethrow;
      }
      if (resultSpec == 1) {
        await vm._closeDiscardedCallResults(frame, results);
      }
      frame.openTop = vm._storeCallResults(
        frame,
        register,
        resultSpec,
        results,
      );
      try {
        _resetResumeLineHookState(vm.runtime, vm._debugInterpreter, frame);
        final resumedResults = await vm._runFrameWithTailCalls(frame);
        return _packCallResults(vm.runtime, resumedResults);
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        _tmpDebugFrame(
          frame,
          'call-resume-yield register=$register resultSpec=$resultSpec '
          'values=${error.values} pc=${frame.pc}',
        );
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _tmpDebugFrame(
            frame,
            'call-resume-yield-next child=${nextChild.runtimeType} pc=${frame.pc}',
          );
          _installBytecodeContinuation(
            coroutine,
            _wrapFrameContinuation(vm, frame, resumeInProtectedCall, nextChild),
          );
        }
        rethrow;
      }
    });
  }

  Future<List<Value>> _resumeResults(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      _tmpDebugFrame(
        frame,
        'call-resume-results child=${nested.runtimeType} '
        'resultType=${result.runtimeType} '
        'result=${_debugResultPayload(result)}',
      );
      return vm._normalizeResults(result);
    }
    return args
        .map((arg) => _runtimeValue(vm.runtime, arg))
        .toList(growable: false);
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeConditionalJumpSuspension
    implements CoroutineContinuation {
  const _LuaBytecodeConditionalJumpSuspension({
    required this.vm,
    required this.frame,
    required this.word,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final LuaBytecodeInstructionWord word;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(vm.runtime, resumeInProtectedCall, () async {
      late final Value resultValue;
      try {
        resultValue = await _resumeResult(args);
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _installBytecodeContinuation(
            coroutine,
            _LuaBytecodeConditionalJumpSuspension(
              vm: vm,
              frame: frame,
              word: word,
              resumeInProtectedCall: resumeInProtectedCall,
              child: nextChild,
            ),
          );
        }
        rethrow;
      }
      // Match luaV_finishOp for yielded EQ/LT/LE-family opcodes: resume with
      // the metamethod's boolean result and only then advance the pending JMP.
      vm._docondjump(frame, word, isLuaTruthy(resultValue));
      try {
        final resumedResults = await vm._runFrameWithTailCalls(frame);
        return _packCallResults(vm.runtime, resumedResults);
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _installBytecodeContinuation(
            coroutine,
            _wrapFrameContinuation(vm, frame, resumeInProtectedCall, nextChild),
          );
        }
        rethrow;
      }
    });
  }

  Future<Value> _resumeResult(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return _firstResultValue(vm.runtime, result);
    }
    return args.isEmpty
        ? _runtimeValue(vm.runtime, null)
        : _runtimeValue(vm.runtime, args.first);
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeConcatSuspension implements CoroutineContinuation {
  const _LuaBytecodeConcatSuspension({
    required this.vm,
    required this.frame,
    required this.startRegister,
    required this.nextOffset,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int startRegister;
  final int nextOffset;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        late final Value resumedValue;
        try {
          resumedValue = await _resumeResult(args);
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _LuaBytecodeConcatSuspension(
                vm: vm,
                frame: frame,
                startRegister: startRegister,
                nextOffset: nextOffset,
                resumeInProtectedCall: resumeInProtectedCall,
                child: nextChild,
              ),
            );
          }
          rethrow;
        }
        try {
          final concatValue = await vm._continueConcatInstruction(
            frame,
            startRegister: startRegister,
            nextOffset: nextOffset,
            current: resumedValue,
          );
          frame.setRegister(startRegister, concatValue);
        } on YieldException {
          rethrow;
        }
        try {
          final resumedResults = await vm._runFrameWithTailCalls(frame);
          return _packCallResults(vm.runtime, resumedResults);
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _wrapFrameContinuation(
                vm,
                frame,
                resumeInProtectedCall,
                nextChild,
              ),
            );
          }
          rethrow;
        }
      },
    );
  }

  Future<Value> _resumeResult(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return _firstResultValue(vm.runtime, result);
    }
    return args.isEmpty
        ? _runtimeValue(vm.runtime, null)
        : _runtimeValue(vm.runtime, args.first);
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeStoreRegisterSuspension
    implements CoroutineContinuation {
  const _LuaBytecodeStoreRegisterSuspension({
    required this.vm,
    required this.frame,
    required this.register,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int register;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        late final Value resultValue;
        try {
          resultValue = await _resumeResult(args);
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _LuaBytecodeStoreRegisterSuspension(
                vm: vm,
                frame: frame,
                register: register,
                resumeInProtectedCall: resumeInProtectedCall,
                child: nextChild,
              ),
            );
          }
          rethrow;
        }
        frame.setRegister(register, resultValue);
        try {
          final resumedResults = await vm._runFrameWithTailCalls(frame);
          return _packCallResults(vm.runtime, resumedResults);
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _wrapFrameContinuation(
                vm,
                frame,
                resumeInProtectedCall,
                nextChild,
              ),
            );
          }
          rethrow;
        }
      },
    );
  }

  Future<Value> _resumeResult(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return _firstResultValue(vm.runtime, result);
    }
    return args.isEmpty
        ? _runtimeValue(vm.runtime, null)
        : _runtimeValue(vm.runtime, args.first);
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeResumeOnlySuspension implements CoroutineContinuation {
  const _LuaBytecodeResumeOnlySuspension({
    required this.vm,
    required this.frame,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.resume(args);
          }
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _LuaBytecodeResumeOnlySuspension(
                vm: vm,
                frame: frame,
                resumeInProtectedCall: resumeInProtectedCall,
                child: nextChild,
              ),
            );
          }
          rethrow;
        }
        try {
          final resumedResults = await vm._runFrameWithTailCalls(frame);
          return _packCallResults(vm.runtime, resumedResults);
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _wrapFrameContinuation(
                vm,
                frame,
                resumeInProtectedCall,
                nextChild,
              ),
            );
          }
          rethrow;
        }
      },
    );
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeProtectedCallSuspension
    implements CoroutineContinuation {
  const _LuaBytecodeProtectedCallSuspension({required this.vm, this.child});

  final LuaBytecodeVm vm;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) async {
    vm.runtime.enterProtectedCall();
    try {
      try {
        final result = await _resumeChild(args);
        return LuaResults(vm._packBytecodeProtectedCallSuccess(result));
      } on CoroutineCloseSignal {
        rethrow;
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _installBytecodeContinuation(
            coroutine,
            _LuaBytecodeProtectedCallSuspension(vm: vm, child: nextChild),
          );
        }
        rethrow;
      } catch (error) {
        return LuaResults(vm._packBytecodeProtectedCallFailure(error));
      }
    } finally {
      vm.runtime.exitProtectedCall();
    }
  }

  Future<Object?> _resumeChild(List<Object?> args) async {
    if (child case final nested?) {
      return nested.resume(args);
    }
    final values = args
        .map<Object?>((arg) => valueFromLuaSlot(vm.runtime, arg))
        .toList(growable: false);
    return LuaResults(values);
  }

  @override
  Future<void> close([Object? error]) async {
    try {
      if (child case final nested?) {
        await nested.close(error);
      }
    } on CoroutineCloseSignal {
      return;
    }
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeCloseSuspension implements CoroutineContinuation {
  const _LuaBytecodeCloseSuspension({
    required this.vm,
    required this.frame,
    required this.fromRegister,
    required this.savedTop,
    required this.savedOpenTop,
    required this.resumeInProtectedCall,
    required this.pendingError,
    required this.pendingErrorStackTrace,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int fromRegister;
  final int savedTop;
  final int? savedOpenTop;
  final bool resumeInProtectedCall;
  final Object? pendingError;
  final StackTrace? pendingErrorStackTrace;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(vm.runtime, resumeInProtectedCall, () async {
      var activeError = pendingError;
      var activeErrorStackTrace = pendingErrorStackTrace;
      try {
        if (child case final nested?) {
          try {
            _tmpDebugFrame(
              frame,
              'close-resume child=${nested.runtimeType} closed=${frame.closed} pc=${frame.pc}',
            );
            final nestedResult = await nested.resume(args);
            _tmpDebugFrame(
              frame,
              'close-resume-result child=${nested.runtimeType} frameClosed=${frame.closed} '
              'resultType=${nestedResult.runtimeType}',
            );
            if (_continuationCompletesFrame(nested, frame)) {
              return nestedResult;
            }
          } on YieldException {
            rethrow;
          } catch (error, stackTrace) {
            final pendingError = _preserveCloseErrorObject(
              frame.runtime,
              error,
            );
            activeError = pendingError;
            activeErrorStackTrace = stackTrace;
            frame.top = savedTop;
            frame.openTop = savedOpenTop;
            await _closeFrameForCoroutine(
              frame,
              fromRegister: fromRegister,
              error: pendingError,
            );
            if (pendingError != null) {
              Error.throwWithStackTrace(pendingError, stackTrace);
            }
            rethrow;
          }
        }
        frame.top = savedTop;
        frame.openTop = savedOpenTop;
        if (activeError == null) {
          final resumedResults = await vm._runFrameWithTailCalls(frame);
          return _packCallResults(vm.runtime, resumedResults);
        }
        await _closeFrameForCoroutine(
          frame,
          fromRegister: fromRegister,
          error: activeError,
        );
        if (activeErrorStackTrace != null) {
          Error.throwWithStackTrace(activeError, activeErrorStackTrace);
        }
        throw activeError;
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        _tmpDebugFrame(
          frame,
          'close-resume-yield fromRegister=$fromRegister values=${error.values} pc=${frame.pc}',
        );
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _tmpDebugFrame(
            frame,
            'close-resume-yield-next child=${nextChild.runtimeType} pc=${frame.pc}',
          );
          _installBytecodeContinuation(
            coroutine,
            _LuaBytecodeCloseSuspension(
              vm: vm,
              frame: frame,
              fromRegister: fromRegister,
              savedTop: savedTop,
              savedOpenTop: savedOpenTop,
              resumeInProtectedCall: resumeInProtectedCall,
              pendingError: activeError,
              pendingErrorStackTrace: activeErrorStackTrace,
              child: nextChild,
            ),
          );
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final Expando<List<({int start, int? end})?>>
_prototypeWrittenRegisterRangesByPc = Expando<List<({int start, int? end})?>>(
  'luaBytecodePrototypeWrittenRegisterRangesByPc',
);

List<({int start, int? end})?> _writtenRegisterRangesByPcFor(
  LuaBytecodePrototype prototype,
) {
  final cached = _prototypeWrittenRegisterRangesByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final ranges = List<({int start, int? end})?>.generate(
    prototype.code.length,
    (pc) {
      final word = prototype.code[pc];
      return switch (word.opcode) {
        Opcode.move ||
        Opcode.loadI ||
        Opcode.loadF ||
        Opcode.loadK ||
        Opcode.loadKx ||
        Opcode.loadFalse ||
        Opcode.lFalseSkip ||
        Opcode.loadTrue ||
        Opcode.getUpval ||
        Opcode.getTabUp ||
        Opcode.getTable ||
        Opcode.getI ||
        Opcode.getField ||
        Opcode.newTable ||
        Opcode.self ||
        Opcode.closure ||
        Opcode.varArgPrep ||
        Opcode.varArg => (start: word.a, end: word.a),
        Opcode.loadNil => (start: word.a, end: word.a + word.b),
        Opcode.call || Opcode.tailCall => (
          start: word.a,
          end: word.c == 0 ? null : word.a + word.c - 2,
        ),
        _ => null,
      };
    },
    growable: false,
  );
  _prototypeWrittenRegisterRangesByPc[prototype] = ranges;
  return ranges;
}

final Expando<List<Map<int, String>>> _prototypeActiveNamedLocalsByPc =
    Expando<List<Map<int, String>>>(
      'luaBytecodePrototypeActiveNamedLocalsByPc',
    );

List<Map<int, String>> _activeNamedLocalsByPcFor(
  LuaBytecodePrototype prototype,
) {
  final cached = _prototypeActiveNamedLocalsByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final codeLength = prototype.code.length;
  final startsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  final endsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  for (final local in prototype.localVariables) {
    if (local.register == null || local.endPc <= local.startPc) {
      continue;
    }
    final startPc = local.startPc;
    if (startPc >= 0 && startPc < codeLength) {
      startsByPc[startPc].add(local);
    }
    final endPc = local.endPc;
    if (endPc >= 0 && endPc < codeLength) {
      endsByPc[endPc].add(local);
    }
  }

  final activeLocalsByRegister =
      <int, List<LuaBytecodeLocalVariableDebugInfo>>{};
  var currentNamedLocals = const <int, String>{};
  final snapshots = List<Map<int, String>>.filled(
    codeLength,
    const <int, String>{},
    growable: false,
  );

  Map<int, String> snapshotNamedLocals() {
    if (activeLocalsByRegister.isEmpty) {
      return const <int, String>{};
    }
    final namedLocals = <int, String>{};
    for (final entry in activeLocalsByRegister.entries) {
      for (final local in entry.value.reversed) {
        final name = local.name;
        if (name == null || name.isEmpty || name.startsWith('(')) {
          continue;
        }
        namedLocals[entry.key] = name;
        break;
      }
    }
    return namedLocals.isEmpty ? const <int, String>{} : namedLocals;
  }

  for (var pc = 0; pc < codeLength; pc++) {
    var changed = false;
    for (final local in endsByPc[pc]) {
      final register = local.register!;
      final locals = activeLocalsByRegister[register];
      if (locals == null) {
        continue;
      }
      locals.remove(local);
      if (locals.isEmpty) {
        activeLocalsByRegister.remove(register);
      }
      changed = true;
    }
    for (final local in startsByPc[pc]) {
      final register = local.register!;
      activeLocalsByRegister
          .putIfAbsent(register, () => <LuaBytecodeLocalVariableDebugInfo>[])
          .add(local);
      changed = true;
    }
    if (changed) {
      currentNamedLocals = snapshotNamedLocals();
    }
    snapshots[pc] = currentNamedLocals;
  }

  _prototypeActiveNamedLocalsByPc[prototype] = snapshots;
  return snapshots;
}

typedef _LuaBytecodeDebugLocalWindow = ({
  List<LuaBytecodeLocalVariableDebugInfo> locals,
  Set<int> registers,
});

const _emptyLuaBytecodeDebugLocalWindow = (
  locals: <LuaBytecodeLocalVariableDebugInfo>[],
  registers: <int>{},
);

final Expando<List<_LuaBytecodeDebugLocalWindow>>
_prototypeActiveDebugLocalsByPc = Expando<List<_LuaBytecodeDebugLocalWindow>>(
  'luaBytecodePrototypeActiveDebugLocalsByPc',
);

List<_LuaBytecodeDebugLocalWindow> _activeDebugLocalsByPcFor(
  LuaBytecodePrototype prototype,
) {
  final cached = _prototypeActiveDebugLocalsByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final sortedLocals = _sortedDebugLocalsFor(prototype);
  final windows = List<_LuaBytecodeDebugLocalWindow>.generate(
    prototype.code.length,
    (pc) => _debugLocalWindowForPc(sortedLocals, pc),
    growable: false,
  );
  _prototypeActiveDebugLocalsByPc[prototype] = windows;
  return windows;
}

_LuaBytecodeDebugLocalWindow _debugLocalWindowForPc(
  List<LuaBytecodeLocalVariableDebugInfo> sortedLocals,
  int pc,
) {
  final locals = <LuaBytecodeLocalVariableDebugInfo>[];
  final registers = <int>{};
  for (final local in sortedLocals) {
    final register = local.register;
    if (register == null || local.startPc > pc || pc >= local.endPc) {
      continue;
    }
    locals.add(local);
    registers.add(register);
  }
  if (locals.isEmpty) {
    return _emptyLuaBytecodeDebugLocalWindow;
  }
  return (
    locals: List<LuaBytecodeLocalVariableDebugInfo>.unmodifiable(locals),
    registers: Set<int>.unmodifiable(registers),
  );
}

List<LuaBytecodeLocalVariableDebugInfo> _sortedDebugLocalsFor(
  LuaBytecodePrototype prototype,
) {
  return List<LuaBytecodeLocalVariableDebugInfo>.of(
    prototype.localVariables,
    growable: false,
  )..sort(_compareDebugLocals);
}

int _compareDebugLocals(
  LuaBytecodeLocalVariableDebugInfo left,
  LuaBytecodeLocalVariableDebugInfo right,
) {
  final startOrder = left.startPc.compareTo(right.startPc);
  if (startOrder != 0) {
    return startOrder;
  }
  final leftRegister = left.register ?? -1;
  final rightRegister = right.register ?? -1;
  final registerOrder = leftRegister.compareTo(rightRegister);
  if (registerOrder != 0) {
    return registerOrder;
  }
  return (left.name ?? '').compareTo(right.name ?? '');
}

final Expando<List<Set<int>>> _prototypeEnvironmentRegistersByPc =
    Expando<List<Set<int>>>('luaBytecodePrototypeEnvironmentRegistersByPc');

List<Set<int>> _environmentRegistersByPcFor(LuaBytecodePrototype prototype) {
  final cached = _prototypeEnvironmentRegistersByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final codeLength = prototype.code.length;
  final startsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  final endsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  for (final local in prototype.localVariables) {
    if (local.register == null) {
      continue;
    }
    final startPc = local.startPc;
    if (startPc >= 0 && startPc < codeLength) {
      startsByPc[startPc].add(local);
    }
    final endPc = local.endPc;
    if (endPc >= 0 && endPc < codeLength) {
      endsByPc[endPc].add(local);
    }
  }

  final activeLocalsByRegister =
      <int, List<LuaBytecodeLocalVariableDebugInfo>>{};
  var currentEnvironmentRegisters = const <int>{};
  final snapshots = List<Set<int>>.filled(
    codeLength,
    const <int>{},
    growable: false,
  );

  Set<int> snapshotEnvironmentRegisters() {
    if (activeLocalsByRegister.isEmpty) {
      return const <int>{};
    }
    final envRegisters = <int>{};
    for (final entry in activeLocalsByRegister.entries) {
      if (entry.value.any((local) => local.name == '_ENV')) {
        envRegisters.add(entry.key);
      }
    }
    return envRegisters.isEmpty ? const <int>{} : envRegisters;
  }

  for (var pc = 0; pc < codeLength; pc++) {
    var changed = false;
    for (final local in endsByPc[pc]) {
      final register = local.register!;
      final locals = activeLocalsByRegister[register];
      if (locals == null) {
        continue;
      }
      locals.remove(local);
      if (locals.isEmpty) {
        activeLocalsByRegister.remove(register);
      }
      changed = true;
    }
    for (final local in startsByPc[pc]) {
      final register = local.register!;
      activeLocalsByRegister
          .putIfAbsent(register, () => <LuaBytecodeLocalVariableDebugInfo>[])
          .add(local);
      changed = true;
    }
    if (changed) {
      currentEnvironmentRegisters = snapshotEnvironmentRegisters();
    }
    snapshots[pc] = currentEnvironmentRegisters;
  }

  _prototypeEnvironmentRegistersByPc[prototype] = snapshots;
  return snapshots;
}

final class _LuaBytecodeFrameArgsView extends ListBase<Object?> {
  _LuaBytecodeFrameArgsView(
    this._frame, {
    required this.start,
    required this.count,
  });

  final _LuaBytecodeFrame _frame;
  final int start;
  final int count;

  Iterable<Value> get gcRoots sync* {
    for (var index = 0; index < count; index++) {
      yield _frame.slotValue(start + index);
    }
  }

  @override
  int get length => count;

  @override
  set length(int value) {
    throw UnsupportedError('Bytecode call args are read-only');
  }

  @override
  Object? operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', count);
    return _frame.slotValue(start + index);
  }

  @override
  void operator []=(int index, Object? value) {
    throw UnsupportedError('Bytecode call args are read-only');
  }
}

final class _LuaBytecodeFrameSuspension implements CoroutineContinuation {
  const _LuaBytecodeFrameSuspension({
    required this.vm,
    required this.frame,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(vm.runtime, resumeInProtectedCall, () async {
      try {
        if (child case final nested?) {
          final nestedFrame = _tmpContinuationFrame(nested);
          _tmpDebugFrame(
            frame,
            'frame-resume child=${nested.runtimeType} sameFrame=${identical(nestedFrame, frame)} '
            'childClosed=${nestedFrame?.closed} closed=${frame.closed} pc=${frame.pc}',
          );
          final nestedChild = _bytecodeContinuationChild(nested);
          final suspendedCallerFrame =
              !identical(nestedFrame, frame) ||
                  (nested is _LuaBytecodeCallSuspension &&
                      nestedChild is _LuaBytecodeCallSuspension)
              ? _bytecodeSuspendedDebugFrame(frame)
              : null;
          if (suspendedCallerFrame != null) {
            vm.runtime.callStack.pushFrame(suspendedCallerFrame);
          }
          try {
            final nestedResult = await nested.resume(args);
            if (frame.closed) {
              return nestedResult;
            }
          } finally {
            if (suspendedCallerFrame != null) {
              _clearBytecodeCallFrame(suspendedCallerFrame);
              if (identical(vm.runtime.callStack.top, suspendedCallerFrame)) {
                vm.runtime.callStack.pop();
              } else {
                vm.runtime.callStack.removeFrame(suspendedCallerFrame);
              }
            }
          }
        }
        _tmpDebugFrame(frame, 'frame-resume direct pc=${frame.pc}');
        final resumedResults = await vm._runFrameWithTailCalls(frame);
        _tmpDebugFrame(
          frame,
          'frame-resume direct-result count=${resumedResults.length} closed=${frame.closed} pc=${frame.pc}',
        );
        return _packCallResults(vm.runtime, resumedResults);
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _installBytecodeContinuation(
            coroutine,
            _wrapFrameContinuation(vm, frame, resumeInProtectedCall, nextChild),
          );
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeReturnSuspension implements CoroutineContinuation {
  const _LuaBytecodeReturnSuspension({
    required this.vm,
    required this.frame,
    required this.register,
    required this.resultSpec,
    required this.savedTop,
    required this.savedOpenTop,
    required this.resumeInProtectedCall,
    required this.pendingError,
    required this.pendingErrorStackTrace,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int register;
  final int resultSpec;
  final int savedTop;
  final int? savedOpenTop;
  final bool resumeInProtectedCall;
  final Object? pendingError;
  final StackTrace? pendingErrorStackTrace;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(vm.runtime, resumeInProtectedCall, () async {
      var activeError = pendingError;
      var activeErrorStackTrace = pendingErrorStackTrace;
      try {
        if (child case final nested?) {
          try {
            _tmpDebugFrame(
              frame,
              'return-resume-child child=${nested.runtimeType} closed=${frame.closed} pc=${frame.pc}',
            );
            final nestedResult = await nested.resume(args);
            _tmpDebugFrame(
              frame,
              'return-resume-child-result child=${nested.runtimeType} frameClosed=${frame.closed} '
              'resultType=${nestedResult.runtimeType}',
            );
            if (_continuationCompletesFrame(nested, frame)) {
              return nestedResult;
            }
          } on YieldException {
            rethrow;
          } catch (error, stackTrace) {
            final pendingError = _preserveCloseErrorObject(
              frame.runtime,
              error,
            );
            activeError = pendingError;
            activeErrorStackTrace = stackTrace;
            frame.top = savedTop;
            frame.openTop = savedOpenTop;
            await _closeFrameForCoroutine(frame, error: pendingError);
            if (pendingError != null) {
              Error.throwWithStackTrace(pendingError, stackTrace);
            }
            rethrow;
          }
        }
        frame.top = savedTop;
        frame.openTop = savedOpenTop;
        await _closeFrameForCoroutine(frame, error: activeError);
        if (activeError != null) {
          if (activeErrorStackTrace != null) {
            Error.throwWithStackTrace(activeError, activeErrorStackTrace);
          }
          throw activeError;
        }
        final resumedResults = await vm._runFrameWithTailCalls(frame);
        return _packCallResults(vm.runtime, resumedResults);
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        _tmpDebugFrame(
          frame,
          'return-resume-yield register=$register resultSpec=$resultSpec '
          'values=${error.values} pc=${frame.pc}',
        );
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _tmpDebugFrame(
            frame,
            'return-resume-yield-next child=${nextChild.runtimeType} pc=${frame.pc}',
          );
          _installBytecodeContinuation(
            coroutine,
            _LuaBytecodeReturnSuspension(
              vm: vm,
              frame: frame,
              register: register,
              resultSpec: resultSpec,
              savedTop: savedTop,
              savedOpenTop: savedOpenTop,
              resumeInProtectedCall: resumeInProtectedCall,
              pendingError: activeError,
              pendingErrorStackTrace: activeErrorStackTrace,
              child: nextChild,
            ),
          );
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

bool _continuationCompletesFrame(
  CoroutineContinuation continuation,
  _LuaBytecodeFrame currentFrame,
) {
  if (!currentFrame.closed) {
    return false;
  }
  if (continuation case _LuaBytecodeFrameSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  if (continuation case _LuaBytecodeReturnSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  if (continuation case _LuaBytecodeTailCallSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  return false;
}

final class _LuaBytecodeTailCallSuspension implements CoroutineContinuation {
  const _LuaBytecodeTailCallSuspension({
    required this.vm,
    required this.frame,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(vm.runtime, resumeInProtectedCall, () async {
      try {
        _tmpDebugFrame(
          frame,
          'tail-resume child=${child.runtimeType} closed=${frame.closed} pc=${frame.pc}',
        );
        final results = await _resumeResults(args);
        _tmpDebugFrame(
          frame,
          'tail-resume-results '
          'results=${results.map((v) => "${rawLuaSlot(v).runtimeType}:${v.isMulti}").join(",")} '
          'closed=${frame.closed} pc=${frame.pc}',
        );
        await _closeFrameForCoroutine(frame, error: null);
        return _packCallResults(vm.runtime, results);
      } on YieldException catch (error) {
        final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
        _tmpDebugFrame(
          frame,
          'tail-resume-yield values=${error.values} pc=${frame.pc}',
        );
        if (coroutine != null) {
          final nextChild = coroutine.takeContinuation();
          _tmpDebugFrame(
            frame,
            'tail-resume-yield-next child=${nextChild.runtimeType} pc=${frame.pc}',
          );
          _installBytecodeContinuation(
            coroutine,
            _LuaBytecodeTailCallSuspension(
              vm: vm,
              frame: frame,
              resumeInProtectedCall: resumeInProtectedCall,
              child: nextChild,
            ),
          );
        }
        rethrow;
      }
    });
  }

  Future<List<Value>> _resumeResults(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      _tmpDebugFrame(
        frame,
        'tail-resume-results-child child=${nested.runtimeType} '
        'resultType=${result.runtimeType} '
        'result=${_debugResultPayload(result)}',
      );
      return vm._normalizeResults(result);
    }
    return args
        .map((arg) => _runtimeValue(vm.runtime, arg))
        .toList(growable: false);
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeTForCallSuspension implements CoroutineContinuation {
  const _LuaBytecodeTForCallSuspension({
    required this.vm,
    required this.frame,
    required this.base,
    required this.resultCount,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int base;
  final int resultCount;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        late final List<Value> results;
        try {
          results = await _resumeResults(args);
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _LuaBytecodeTForCallSuspension(
                vm: vm,
                frame: frame,
                base: base,
                resultCount: resultCount,
                resumeInProtectedCall: resumeInProtectedCall,
                child: nextChild,
              ),
            );
          }
          rethrow;
        }
        for (var index = 0; index < results.length; index++) {
          frame.setRegister(base + 3 + index, results[index]);
        }
        frame.top = base + 3 + results.length;
        try {
          final resumedResults = await vm._runFrameWithTailCalls(frame);
          return _packCallResults(vm.runtime, resumedResults);
        } on YieldException catch (error) {
          final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
          if (coroutine != null) {
            final nextChild = coroutine.takeContinuation();
            _installBytecodeContinuation(
              coroutine,
              _wrapFrameContinuation(
                vm,
                frame,
                resumeInProtectedCall,
                nextChild,
              ),
            );
          }
          rethrow;
        }
      },
    );
  }

  Future<List<Value>> _resumeResults(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return _padResults(vm._normalizeResults(result));
    }
    final resumed = args
        .map((arg) => _runtimeValue(vm.runtime, arg))
        .toList(growable: false);
    return _padResults(resumed);
  }

  List<Value> _padResults(List<Value> results) {
    // TFORLOOP always inspects the control slot written by TFORCALL. When the
    // resumed iterator returns no values, we still must overwrite that slot
    // with nil; otherwise the stale control variable keeps the loop alive.
    return List<Value>.generate(
      resultCount,
      (index) => index < results.length
          ? results[index]
          : _runtimeValue(vm.runtime, null),
      growable: false,
    );
  }

  @override
  Future<void> close([Object? error]) {
    return _withProtectedCallResume(
      vm.runtime,
      resumeInProtectedCall,
      () async {
        try {
          if (child case final nested?) {
            await nested.close(error);
          }
          if (!frame.closed) {
            await _closeFrameForCoroutine(frame, error: error);
          }
        } on CoroutineCloseSignal {
          return;
        }
      },
    );
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeUpvalue {
  _LuaBytecodeUpvalue.open(this._frame, this.registerIndex);

  _LuaBytecodeUpvalue.closed(Value value)
    : _closedValue = value,
      registerIndex = -1;

  _LuaBytecodeFrame? _frame;
  final int registerIndex;
  Value? _closedValue;
  Box<dynamic>? _identity;

  bool get isOpen => _frame != null;

  Box<dynamic> get identity => _identity ??= Box<dynamic>(
    null,
    isTransient: true,
    interpreter: _frame?.runtime ?? _closedValue?.interpreter,
  );

  Value read() => _frame?.register(registerIndex) ?? _closedValue!;

  void write(Value value) {
    final frame = _frame;
    if (frame != null) {
      frame.setRegister(registerIndex, value);
      return;
    }
    _closedValue = value;
  }

  void close() {
    final frame = _frame;
    if (frame == null) {
      return;
    }
    _closedValue = frame.register(registerIndex);
    _frame = null;
  }
}

Object? _packCallResults(LuaRuntime _, List<Value> results) {
  if (results.isEmpty) {
    return null;
  }
  if (results.length == 1) {
    return results.single;
  }
  return LuaResults(results);
}

Object? _debugResultPayload(Object? result) {
  final resultValues = luaResultValues(result);
  if (resultValues != null) {
    return resultValues.map(rawLuaSlot).toList();
  }
  return switch (result) {
    Value() => rawLuaSlot(result),
    List<Object?>() => result,
    _ => result,
  };
}

Value _detachSharedRuntimeConstantInFrameRegister(
  _LuaBytecodeFrame frame,
  int registerIndex,
) {
  final current = frame.slotValue(registerIndex);
  if (!_isSharedRuntimeConstant(frame.runtime, current)) {
    return current;
  }
  final detached = _cloneBytecodeValue(current);
  frame.registers[registerIndex] = detached;
  final gc = frame.runtime.gc;
  if (gc.isCycleActive) {
    gc.noteRootWrite(detached);
  }
  return detached;
}

Value _wrapClosure(LuaBytecodeClosure closure) {
  final value = Value(
    closure,
    closureEnvironment: closure.environment,
    strippedDebugInfo: !closure.prototype.hasDebugInfo,
  );
  value.interpreter ??= closure.runtime;
  return value;
}

Value _hydrateClosureCallableValue(
  Value value,
  LuaBytecodeClosure closure, {
  String? fallbackName,
}) {
  value.functionBody ??= closure.debugFunctionBody;
  value.closureEnvironment ??= closure.environment;
  value.functionName ??= fallbackName;
  value.strippedDebugInfo = !closure.prototype.hasDebugInfo;
  value.interpreter ??= closure.runtime;
  return value;
}

Value _constantValue(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
  int index,
) {
  if (index < 0 || index >= prototype.constants.length) {
    throw RangeError.range(index, 0, prototype.constants.length - 1, 'index');
  }
  final cache = _constantValueCacheFor(runtime, prototype);
  if (cache[index] case final cached?) {
    return cached;
  }
  final value = switch (prototype.constants[index]) {
    LuaBytecodeNilConstant() => runtime.constantPrimitiveValue(null),
    LuaBytecodeBooleanConstant(:final value) => runtime.constantPrimitiveValue(
      value,
    ),
    LuaBytecodeIntegerConstant(:final value) => runtime.constantPrimitiveValue(
      value,
    ),
    LuaBytecodeFloatConstant(:final value) => runtime.constantPrimitiveValue(
      value,
    ),
    LuaBytecodeStringConstant(:final value) => runtime.constantStringValue(
      value.codeUnits,
    ),
  };
  cache[index] = value;
  return value;
}

final Expando<Map<LuaBytecodePrototype, List<Value?>>>
_runtimeConstantValueCaches = Expando<Map<LuaBytecodePrototype, List<Value?>>>(
  'luaBytecodeRuntimeConstantValueCaches',
);

List<Value?> _constantValueCacheFor(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
) {
  final caches = _runtimeConstantValueCaches[runtime] ??=
      <LuaBytecodePrototype, List<Value?>>{};
  return caches.putIfAbsent(
    prototype,
    () =>
        List<Value?>.filled(prototype.constants.length, null, growable: false),
  );
}

Object? _constantRaw(LuaBytecodePrototype prototype, int index) {
  if (index < 0 || index >= prototype.constants.length) {
    throw RangeError.range(index, 0, prototype.constants.length - 1, 'index');
  }
  return switch (prototype.constants[index]) {
    LuaBytecodeNilConstant() => null,
    LuaBytecodeBooleanConstant(:final value) => value,
    LuaBytecodeIntegerConstant(:final value) => value,
    LuaBytecodeFloatConstant(:final value) => value,
    LuaBytecodeStringConstant(:final value) => value,
  };
}

Value _stringConstant(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
  int index,
) => _constantValue(runtime, prototype, index);

String _stringConstantRaw(LuaBytecodePrototype prototype, int index) {
  if (index < 0 || index >= prototype.constants.length) {
    throw RangeError.range(index, 0, prototype.constants.length - 1, 'index');
  }
  return switch (prototype.constants[index]) {
    LuaBytecodeStringConstant(:final value) => value,
    _ => throw StateError('constant $index is not a string'),
  };
}

Future<bool> _explicitGlobalIsAlreadyDefined(
  Value envValue,
  Environment environment,
  String name,
) async {
  if (name == '_ENV') {
    final current = environment.root.get(name);
    return current != null &&
        (current is! Value || rawLuaSlot(current) != null);
  }

  if (rawLuaSlot(envValue) != null) {
    final current = await envValue.getValueAsync(name);
    return rawLuaSlot(current) != null;
  }

  final current = environment.readRootGlobal(name);
  return rawLuaSlot(current) != null;
}

Value _rkValue(_LuaBytecodeFrame frame, int operand, bool isConstant) {
  return isConstant
      ? _constantValue(frame.runtime, frame.closure.prototype, operand)
      : frame.register(operand);
}

Value _runtimeValue(LuaRuntime runtime, Object? value) {
  final wrapped = switch (value) {
    final Value existing => _canonicalizeBytecodeValue(existing),
    final LuaResults results => valueMultiFromLuaResults(
      results.values,
      runtime: runtime,
    ),
    null ||
    bool() ||
    num() ||
    BigInt() => runtime.constantPrimitiveValue(value),
    final LuaString string => runtime.constantStringValue(string.bytes),
    final String string => runtime.constantRawStringValue(string),
    final Map map => valueFromLuaSlot(runtime, map),
    final LuaFile file => _trackedLuaFileWrapper(file, runtime),
    final LuaBytecodeClosure closure => Value(
      closure,
      closureEnvironment: closure.environment,
      interpreter: runtime,
    ),
    _ => Value(value, interpreter: runtime),
  };
  wrapped.interpreter ??= runtime;
  return wrapped;
}

Value _framePrimitiveValue(LuaRuntime runtime, Object? value) {
  if (isLuaScalarPrimitiveSlot(value)) {
    return runtime.constantPrimitiveValue(value);
  }
  return Value.primitive(
    value,
    interpreter: runtime,
    skipAllocationDebt: true,
    skipGcRegistration: isLuaScalarPrimitiveSlot(value),
  );
}

bool _isSharedRuntimeConstant(LuaRuntime runtime, Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    null ||
    bool() ||
    num() ||
    BigInt() => identical(value, runtime.constantPrimitiveValue(raw)),
    final LuaString string => identical(
      value,
      runtime.constantStringValue(string.bytes),
    ),
    _ => false,
  };
}

Value _cloneBytecodeValue(Value source) {
  final raw = rawLuaSlot(source);
  if (_canUsePrimitiveBytecodeClone(source)) {
    final clone = Value.primitive(
      raw,
      isMulti: source.isMulti,
      isConst: source.isConst,
      isToBeClose: source.isToBeClose,
      isTempKey: source.isTempKey,
      skipAllocationDebt: source.skipAllocationDebt || isLuaPrimitiveSlot(raw),
      skipGcRegistration:
          source.skipGcRegistration || isLuaScalarPrimitiveSlot(raw),
      upvalues: source.upvalues,
      interpreter: source.interpreter,
      functionBody: source.functionBody,
      closureEnvironment: source.closureEnvironment,
      functionName: source.functionName,
      debugLineDefined: source.debugLineDefined,
      strippedDebugInfo: source.strippedDebugInfo,
    );
    clone.metatableRef = source.metatableRef;
    clone.globalProxyEnvironment = source.globalProxyEnvironment;
    return clone;
  }
  final clone = Value(
    raw,
    metatable: source.metatable,
    isMulti: source.isMulti,
    isConst: source.isConst,
    isToBeClose: source.isToBeClose,
    isTempKey: source.isTempKey,
    skipAllocationDebt: source.skipAllocationDebt || isLuaPrimitiveSlot(raw),
    skipGcRegistration:
        source.skipGcRegistration || isLuaScalarPrimitiveSlot(raw),
    upvalues: source.upvalues,
    interpreter: source.interpreter,
    functionBody: source.functionBody,
    closureEnvironment: source.closureEnvironment,
    functionName: source.functionName,
    debugLineDefined: source.debugLineDefined,
    strippedDebugInfo: source.strippedDebugInfo,
  );
  clone.metatableRef = source.metatableRef;
  clone.globalProxyEnvironment = source.globalProxyEnvironment;
  return clone;
}

bool _canUsePrimitiveBytecodeClone(Value source) {
  final raw = rawLuaSlot(source);
  if (isLuaScalarPrimitiveSlot(raw)) {
    return true;
  }
  if (raw is! String && raw is! LuaString) {
    return false;
  }
  return source.metatable == null && source.metatableRef == null;
}

Value _canonicalizeBytecodeValue(Value value) {
  final raw = rawLuaSlot(value);
  if (raw is! LuaFile) {
    return value;
  }

  final tracked = IOLib.trackedOpenFileWrapper(
    raw,
    interpreter: value.interpreter,
  );
  if (tracked == null || identical(tracked, value)) {
    return value;
  }

  tracked.interpreter ??= value.interpreter;
  if (value.isToBeClose) {
    tracked.isToBeClose = true;
  }
  return tracked;
}

Value _trackedLuaFileWrapper(LuaFile file, LuaRuntime runtime) {
  final tracked = IOLib.trackedOpenFileWrapper(file, interpreter: runtime);
  if (tracked != null) {
    tracked.interpreter ??= runtime;
    return tracked;
  }

  return wrapLuaFileValue(file, interpreter: runtime);
}

Value _firstResultValue(LuaRuntime runtime, Object? result) {
  final resultValues = luaResultValues(result);
  if (resultValues != null) {
    return resultValues.isEmpty
        ? _runtimeValue(runtime, null)
        : _runtimeValue(runtime, resultValues.first);
  }
  if (result case final List<Object?> values) {
    return values.isEmpty
        ? _runtimeValue(runtime, null)
        : _runtimeValue(runtime, values.first);
  }
  if (result case final Value value) {
    return valueFromLuaSlot(runtime, value);
  }
  return _runtimeValue(runtime, result);
}

bool _canFastPathNumeric(Value value) =>
    _coerceLuaNumber(rawLuaSlot(value)) != null;

bool _canFastPathInteger(Value value) =>
    _coerceLuaInteger(rawLuaSlot(value)) != null;

bool _canFastPathConcat(Value value) {
  return switch (rawLuaSlot(value)) {
    num() || String() || LuaString() => true,
    _ => false,
  };
}

bool _canFastPathLength(Value value) =>
    !value.hasMetamethod('__len') &&
    switch (rawLuaSlot(value)) {
      LuaString() ||
      String() ||
      List<dynamic>() ||
      Map<dynamic, dynamic>() => true,
      _ => false,
    };

Object? _coerceLuaNumber(Object? value) {
  return switch (value) {
    int() || double() || BigInt() => value,
    final String stringValue => _tryParseLuaNumber(stringValue),
    final LuaString stringValue => _tryParseLuaNumber(stringValue.toString()),
    _ => null,
  };
}

Object? _coerceLuaInteger(Object? value) {
  return switch (_coerceLuaNumber(value)) {
    final int number => number,
    final BigInt number
        when number >= BigInt.from(NumberLimits.minInteger) &&
            number <= BigInt.from(NumberLimits.maxInteger) =>
      number,
    final double number
        when number.isFinite &&
            number.truncateToDouble() == number &&
            number >= NumberLimits.minInteger &&
            number <= NumberLimits.maxInteger =>
      number,
    _ => null,
  };
}

Object? _tryParseLuaNumber(String text) {
  try {
    return LuaNumberParser.parse(text);
  } catch (_) {
    return null;
  }
}

String _metamethodName(int event) => switch (event) {
  0 => '__index',
  1 => '__newindex',
  2 => '__gc',
  3 => '__mode',
  4 => '__len',
  5 => '__eq',
  6 => '__add',
  7 => '__sub',
  8 => '__mul',
  9 => '__mod',
  10 => '__pow',
  11 => '__div',
  12 => '__idiv',
  13 => '__band',
  14 => '__bor',
  15 => '__bxor',
  16 => '__shl',
  17 => '__shr',
  18 => '__unm',
  19 => '__bnot',
  20 => '__lt',
  21 => '__le',
  22 => '__concat',
  23 => '__call',
  24 => '__close',
  _ => throw LuaError('unknown lua_bytecode metamethod event $event'),
};

_LuaBinaryOperation _binaryOperationForMetamethod(String metamethod) {
  return switch (metamethod) {
    '__add' => _LuaBinaryOperation.add,
    '__sub' => _LuaBinaryOperation.sub,
    '__mul' => _LuaBinaryOperation.mul,
    '__mod' => _LuaBinaryOperation.mod,
    '__pow' => _LuaBinaryOperation.pow,
    '__div' => _LuaBinaryOperation.div,
    '__idiv' => _LuaBinaryOperation.idiv,
    '__band' => _LuaBinaryOperation.band,
    '__bor' => _LuaBinaryOperation.bor,
    '__bxor' => _LuaBinaryOperation.bxor,
    '__shl' => _LuaBinaryOperation.shl,
    '__shr' => _LuaBinaryOperation.shr,
    '__concat' => _LuaBinaryOperation.concat,
    _ => throw LuaError('unsupported lua_bytecode metamethod $metamethod'),
  };
}

String _shortSource(String source) {
  if (source.startsWith('file:///')) {
    try {
      return path.basename(Uri.parse(source).path);
    } catch (_) {
      return source;
    }
  }
  if (source.startsWith('@') || source.startsWith('=')) {
    return luaChunkId(source);
  }
  if (looksLikeLuaFilePath(source)) {
    try {
      return path.basename(source);
    } catch (_) {
      return source;
    }
  }
  try {
    return luaChunkId(source);
  } catch (_) {
    return source;
  }
}

bool _isInteger(Value value) => rawLuaSlot(value) is int;

enum _PrimitiveCompare {
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual;

  bool apply(Value left, Value right) {
    return switch (this) {
          lessThan => left < right,
          lessThanOrEqual => left <= right,
          greaterThan => left > right,
          greaterThanOrEqual => left >= right,
        }
        as bool;
  }
}

int _integerValue(Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    final int integer => integer,
    final num numeric => numeric.toInt(),
    _ => throw LuaError('expected integer, got ${raw.runtimeType}'),
  };
}

num _numericValue(Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    final num numeric => numeric,
    _ => throw LuaError(
      'attempt to perform arithmetic on a ${raw.runtimeType} value',
    ),
  };
}

bool _rawEquals(Value left, Value right) {
  return left.equals(right);
}

bool? _tryPrimitiveOrdering(
  Value left,
  Value right,
  _PrimitiveCompare primitiveCompare,
) {
  final leftRaw = rawLuaSlot(left);
  final rightRaw = rawLuaSlot(right);
  final leftString = _stringLike(leftRaw);
  final rightString = _stringLike(rightRaw);
  return switch ((leftRaw, rightRaw)) {
    (num() || BigInt(), num() || BigInt()) => primitiveCompare.apply(
      left,
      right,
    ),
    _ when leftString != null && rightString != null => primitiveCompare.apply(
      left,
      right,
    ),
    _ => null,
  };
}

bool _compareImmediateEquals(Value left, int right) {
  final leftRaw = rawLuaSlot(left);
  return switch (leftRaw) {
    final int integer => integer == right,
    final double doubleValue => doubleValue == right,
    final BigInt integer => integer == BigInt.from(right),
    _ => false,
  };
}

bool? _tryPrimitiveImmediateOrdering(
  Value left,
  int right,
  _PrimitiveCompare primitiveCompare,
) {
  final leftRaw = rawLuaSlot(left);
  return switch (leftRaw) {
    final int integer => switch (primitiveCompare) {
      _PrimitiveCompare.lessThan => integer < right,
      _PrimitiveCompare.lessThanOrEqual => integer <= right,
      _PrimitiveCompare.greaterThan => integer > right,
      _PrimitiveCompare.greaterThanOrEqual => integer >= right,
    },
    final double number => switch (primitiveCompare) {
      _PrimitiveCompare.lessThan => number < right,
      _PrimitiveCompare.lessThanOrEqual => number <= right,
      _PrimitiveCompare.greaterThan => number > right,
      _PrimitiveCompare.greaterThanOrEqual => number >= right,
    },
    final BigInt integer => switch (primitiveCompare) {
      _PrimitiveCompare.lessThan => integer < BigInt.from(right),
      _PrimitiveCompare.lessThanOrEqual => integer <= BigInt.from(right),
      _PrimitiveCompare.greaterThan => integer > BigInt.from(right),
      _PrimitiveCompare.greaterThanOrEqual => integer >= BigInt.from(right),
    },
    _ => null,
  };
}

int _lengthOf(Value value) {
  return switch (rawLuaSlot(value)) {
    final LuaString stringValue => stringValue.length,
    final String stringValue => stringValue.length,
    final List<dynamic> listValue => listValue.length,
    final Map<dynamic, dynamic> mapValue => _tableBoundaryLength(mapValue),
    _ => throw LuaError(
      'attempt to get length of a ${getLuaType(value)} value',
    ),
  };
}

extension on LuaBytecodeVm {
  Future<bool> _compareEquals(Value left, Value right) async {
    if (_rawEquals(left, right)) {
      return true;
    }
    if (!_supportsEqualityMetamethod(left, right)) {
      return false;
    }
    final metamethodResult = await _invokeBinaryMetamethod('__eq', left, right);
    return metamethodResult != null && isLuaTruthy(metamethodResult);
  }

  Future<bool> _compareOrdering(
    Value left,
    Value right, {
    required String metamethod,
    required _PrimitiveCompare primitiveCompare,
  }) async {
    final primitiveResult = _tryPrimitiveOrdering(
      left,
      right,
      primitiveCompare,
    );
    if (primitiveResult != null) {
      return primitiveResult;
    }

    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      left,
      right,
    );
    if (metamethodResult != null) {
      return isLuaTruthy(metamethodResult);
    }

    throw LuaError(_orderComparisonError(left, right));
  }

  Future<bool> _compareImmediateOrdering(
    Value left,
    int right, {
    required String metamethod,
    required _PrimitiveCompare primitiveCompare,
    bool flipOperands = false,
  }) async {
    final primitiveResult = _tryPrimitiveImmediateOrdering(
      left,
      right,
      primitiveCompare,
    );
    if (primitiveResult != null) {
      return primitiveResult;
    }

    final rightValue = _runtimeValue(runtime, right);
    final (metamethodLeft, metamethodRight) = flipOperands
        ? (rightValue, left)
        : (left, rightValue);
    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      metamethodLeft,
      metamethodRight,
    );
    if (metamethodResult != null) {
      return isLuaTruthy(metamethodResult);
    }

    throw LuaError(_orderComparisonError(metamethodLeft, metamethodRight));
  }
}

bool _supportsEqualityMetamethod(Value left, Value right) {
  return getLuaType(left) == 'table' && getLuaType(right) == 'table';
}

String _orderComparisonError(Value left, Value right) {
  final leftType = getLuaType(left);
  final rightType = getLuaType(right);
  return leftType == rightType
      ? 'attempt to compare two $leftType values'
      : 'attempt to compare $leftType with $rightType';
}

int _tableBoundaryLength(Map<dynamic, dynamic> mapValue) {
  final occupiedPositiveIndices = <int>{};
  for (final MapEntry(:key, :value) in mapValue.entries) {
    final index = _positiveIntegerKey(key);
    if (index == null || isLuaNilSlot(value)) {
      continue;
    }
    occupiedPositiveIndices.add(index);
  }

  var length = 0;
  while (occupiedPositiveIndices.contains(length + 1)) {
    length += 1;
  }
  return length;
}

int? _positiveIntegerKey(Object? key) {
  final rawKey = switch (key) {
    final Value value => rawLuaSlot(value),
    _ => key,
  };
  return switch (rawKey) {
    final int value when value > 0 => value,
    final num value
        when value.isFinite &&
            value > 0 &&
            value.toInt().toDouble() == value.toDouble() =>
      value.toInt(),
    _ => null,
  };
}

String? _stringLike(Object? value) => switch (value) {
  final LuaString stringValue => stringValue.toString(),
  final String stringValue => stringValue,
  _ => null,
};

int _signedB(LuaBytecodeInstructionWord word) =>
    word.b - LuaBytecodeInstructionLayout.offsetSB;

int _signedC(LuaBytecodeInstructionWord word) =>
    word.c - LuaBytecodeInstructionLayout.offsetSC;

Future<void>? _runGcLoopSafePoint(LuaRuntime runtime, _LuaBytecodeFrame frame) {
  frame.loopGcCounter += 1;
  final loopCounter = frame.loopGcCounter;
  final shouldRescue =
      !runtime.gc.isStopped &&
      runtime.gc.autoTriggerEnabled &&
      runtime.gc.allocationDebt <= 0 &&
      loopCounter >= 8192 &&
      loopCounter % 8192 == 0;
  if (!runtime.shouldRunLoopGcAtSafePoint(loopCounter)) {
    if (!shouldRescue) {
      return null;
    }
    runtime.gc.performGenerationalStep(runtime.getRoots());
    return null;
  }
  return _runGcLoopSafePointSlow(runtime, frame, shouldRescue);
}

Future<void> _runGcLoopSafePointSlow(
  LuaRuntime runtime,
  _LuaBytecodeFrame frame,
  bool shouldRescue,
) async {
  await runtime.runLoopGcAtSafePoint(frame.loopGcCounter);
  if (runtime.gc.isStopped ||
      !runtime.gc.autoTriggerEnabled ||
      runtime.gc.allocationDebt > 0 ||
      !shouldRescue) {
    return;
  }
  // Long-running bytecode loops sometimes need an extra generational nudge to
  // retire weak-table entries, but doing that every 1024 backedges makes
  // gc.lua spend most of its time in collector work. Keep the rescue path
  // sparse so closure-heavy loops still converge without regressing throughput.
  await runtime.gc.performGenerationalStep(runtime.getRoots());
}

void _resetBackedgeLineHookState(
  LuaRuntime runtime,
  Interpreter? debugInterpreter,
  _LuaBytecodeFrame frame, {
  required int loopLine,
}) {
  final targetLine = frame.closure.prototype.lineForPc(frame.pc);
  if (targetLine == null || targetLine != loopLine) {
    return;
  }
  runtime.callStack.top?.lastDebugHookLine = -1;
  debugInterpreter?.rememberDebugHookLine(
    -1,
    source: runtime.callStack.top?.scriptPath ?? runtime.currentScriptPath,
  );
}

void _resetResumeLineHookState(
  LuaRuntime runtime,
  Interpreter? debugInterpreter,
  _LuaBytecodeFrame frame,
) {
  runtime.callStack.top?.lastDebugHookLine = -1;
  debugInterpreter?.rememberDebugHookLine(
    -1,
    source: frame.closure.debugInfo.source,
  );
}

({bool skip, int limit}) _forIntegerLimit(
  int initial,
  Object rawLimit,
  int step,
) {
  if (rawLimit is int) {
    return (
      skip: step > 0 ? initial > rawLimit : initial < rawLimit,
      limit: rawLimit,
    );
  }
  if (rawLimit is BigInt) {
    if (NumberUtils.isInIntegerRange(rawLimit)) {
      final limit = rawLimit.toInt();
      return (skip: step > 0 ? initial > limit : initial < limit, limit: limit);
    }
    if (rawLimit.isNegative) {
      return step > 0
          ? (skip: true, limit: NumberLimits.minInteger)
          : (skip: false, limit: NumberLimits.minInteger);
    }
    return step < 0
        ? (skip: true, limit: NumberLimits.maxInteger)
        : (skip: false, limit: NumberLimits.maxInteger);
  }
  if (rawLimit is num) {
    if (!rawLimit.isFinite) {
      if (rawLimit.isNegative) {
        return step > 0
            ? (skip: true, limit: NumberLimits.minInteger)
            : (skip: false, limit: NumberLimits.minInteger);
      }
      return step < 0
          ? (skip: true, limit: NumberLimits.maxInteger)
          : (skip: false, limit: NumberLimits.maxInteger);
    }
    if (rawLimit < NumberLimits.minInteger) {
      return step > 0
          ? (skip: true, limit: NumberLimits.minInteger)
          : (skip: false, limit: NumberLimits.minInteger);
    }
    if (rawLimit > NumberLimits.maxInteger) {
      return step < 0
          ? (skip: true, limit: NumberLimits.maxInteger)
          : (skip: false, limit: NumberLimits.maxInteger);
    }
    final limit = step < 0 ? rawLimit.ceil() : rawLimit.floor();
    return (skip: step > 0 ? initial > limit : initial < limit, limit: limit);
  }
  throw LuaError("bad 'for' limit (${rawLimit.runtimeType})");
}

BigInt _unsignedInt64({required int init}) => NumberUtils.toUnsigned64(init);

BigInt _unsignedDifference64(BigInt left, BigInt right) {
  final mod = BigInt.one << NumberLimits.sizeInBits;
  var difference = left - right;
  if (difference.isNegative) {
    difference += mod;
  }
  return difference;
}

BigInt _negativeStepDivisor(int step) => BigInt.from(-(step + 1)) + BigInt.one;

BigInt _unsignedForLoopCounter(Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    final int integer => NumberUtils.toUnsigned64(integer),
    _ => throw LuaError('expected integer, got ${raw.runtimeType}'),
  };
}

int _signedInt64FromUnsigned(BigInt value) {
  final mod = BigInt.one << NumberLimits.sizeInBits;
  final masked = value & (mod - BigInt.one);
  if (masked > BigInt.from(NumberLimits.maxInteger)) {
    return (masked - mod).toInt();
  }
  return masked.toInt();
}

Object _forNumericOperand(Value value, String role) {
  final raw = rawLuaSlot(value);
  final coerced = _coerceLuaNumber(raw);
  if (coerced != null) {
    return coerced;
  }
  throw LuaError(
    "bad 'for' $role (number expected, got ${NumberUtils.typeName(raw)})",
  );
}

int? _exactForIntegerValue(Object value) {
  return switch (value) {
    final int integer => integer,
    final BigInt integer when NumberUtils.isInIntegerRange(integer) =>
      integer.toInt(),
    _ => null,
  };
}

num _numericForOperand(Object value) {
  return switch (value) {
    final int integer => integer,
    final double numeric => numeric,
    final BigInt integer when NumberUtils.isInIntegerRange(integer) =>
      integer.toInt(),
    final BigInt integer => integer.toDouble(),
    _ => throw LuaError(
      'attempt to perform arithmetic on a ${value.runtimeType} value',
    ),
  };
}
