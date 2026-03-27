import 'dart:async';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/extensions/value_extension.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/gc/gc_weights.dart';
import 'package:lualike/src/call_stack.dart';
// GC access occurs via environment.interpreter.gc
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/value_class.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';

import 'exceptions.dart';

Value _packCoroutineVarargsTable(List<Object?> varargs) {
  final table = TableStorage();
  for (var i = 0; i < varargs.length; i++) {
    final value = varargs[i];
    final wrapped = value is Value ? value : Value(value);
    if (!wrapped.isNil) {
      table.setDense(i + 1, wrapped);
    }
  }
  table['n'] = Value(varargs.length);
  return ValueClass.table(table);
}

Object? _normalizeCoroutineError(Object error) {
  if (error is Value) {
    if (error.raw is Value) {
      return _normalizeCoroutineError(error.raw as Value);
    }
    if (error.raw is Map || error.raw is TableStorage) {
      return error;
    }
    return error.unwrap();
  }
  if (error is LuaError) {
    final cause = error.cause;
    if (cause != null &&
        cause is! LuaError &&
        cause.toString() == error.message) {
      return _normalizeCoroutineError(cause);
    }
    return error.message;
  }
  return error;
}

Interpreter? _debugInterpreterForRuntime(LuaRuntime? runtime) {
  if (runtime is Interpreter) {
    return runtime;
  }
  if (runtime == null) {
    return null;
  }
  try {
    final debugInterpreter = (runtime as dynamic).debugInterpreter;
    return debugInterpreter is Interpreter ? debugInterpreter : null;
  } catch (_) {
    return null;
  }
}

/// Engine-owned suspended execution state for a coroutine.
abstract interface class CoroutineContinuation {
  Future<Object?> resume(List<Object?> args);

  Future<void> close([Object? error]);

  Iterable<GCObject> getReferences();
}

final class CoroutineCloseSignal implements Exception {
  CoroutineCloseSignal(this.result);

  final List<Object?> result;
}

final class _AstReturnCloseContinuation implements CoroutineContinuation {
  _AstReturnCloseContinuation(this.coroutine, this.returnValue);

  final Coroutine coroutine;
  final Object? returnValue;

  @override
  Future<Object?> resume(List<Object?> args) async {
    final interpreter = coroutine.closureEnvironment.interpreter;
    if (interpreter != null) {
      interpreter.setCurrentCoroutine(coroutine);
      interpreter.setCurrentEnv(coroutine._resumeEnvironment);
    }
    coroutine.status = CoroutineStatus.running;
    try {
      await coroutine._closeCoroutineScope();
      return returnValue;
    } on YieldException {
      coroutine.installContinuation(
        _AstReturnCloseContinuation(coroutine, returnValue),
      );
      rethrow;
    }
  }

  @override
  Future<void> close([Object? error]) async {
    await coroutine._closeCoroutineScope(error);
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield coroutine;
  }
}

/// Represents a coroutine status as defined in Lua
enum CoroutineStatus {
  /// The coroutine is running (it is the one that called status)
  running,

  /// The coroutine is suspended in a call to yield, or it has not started running yet
  suspended,

  /// The coroutine is active but not running (it has resumed another coroutine)
  normal,

  /// The coroutine has finished its body function, or it has stopped with an error
  dead,
}

/// Represents a Lua coroutine that participates in garbage collection
class Coroutine extends GCObject {
  static final List<Coroutine> _activeStack = [];

  static Coroutine? get active {
    if (_activeStack.isEmpty) return null;
    return _activeStack.last;
  }

  /// The function that this coroutine executes (its Value wrapper)
  final Value functionValue;

  /// The AST node representing the function body
  final FunctionBody? functionBody;

  /// Per-coroutine debug hook state.
  Value? debugHookFunction;
  String debugHookMask = '';
  int debugHookCount = 0;
  int debugHookCountRemaining = 0;

  /// Current status of the coroutine
  CoroutineStatus status = CoroutineStatus.suspended;

  /// The environment that was active when the coroutine was defined (closure environment).
  /// This serves as the parent for the _executionEnvironment.
  final Environment closureEnvironment;

  /// The actual environment where the function's parameters and local variables reside.
  /// This environment is preserved across yields.
  final Environment _executionEnvironment;

  /// The environment active at the current suspension point.
  /// This is restored on resume so nested scope yields continue correctly.
  Environment _resumeEnvironment;

  /// Script path active at the current suspension point.
  /// This is restored on resume so new frames created after a yield retain
  /// the correct chunk/file name.
  String? _resumeScriptPath;

  /// Most recent source line active at the current suspension point (1-based).
  int _resumeLine = -1;

  /// Program counter: the index of the next statement to execute in functionBody.body.
  int _programCounter = 0;

  /// Completer used to pause/resume execution
  Completer<List<Object?>>? completer;

  /// Current execution task
  Future<void>? _executionTask;

  /// Error that caused the coroutine to die, if any
  Object? error;

  /// Saved call stack frames when the coroutine is suspended.
  List<CallFrame>? _savedCallStack;

  /// External GC root providers suspended with this coroutine.
  List<Iterable<Object?> Function()> _savedExternalGcRootProviders =
      const <Iterable<Object?> Function()>[];

  /// Snapshot of the objects exposed by [_savedExternalGcRootProviders].
  ///
  /// These keep the suspended call chain alive while the providers are removed
  /// from the interpreter-global root list.
  List<Object?> _savedExternalGcRoots = const <Object?>[];

  /// Base call stack depth snapshot taken when the coroutine begins/resumes execution.
  int _callStackBaseDepth = 0;

  int _externalGcRootBaseCount = 0;

  int get callStackBaseDepth => _callStackBaseDepth;

  bool _unregistered = false;
  bool _environmentCleared = false;
  CoroutineContinuation? _continuation;

  /// Whether the coroutine is being finalized
  final bool beingFinalized = false;

  /// Constructor
  Coroutine(this.functionValue, this.functionBody, this.closureEnvironment)
    : _executionEnvironment = functionBody == null
          ? closureEnvironment
          : Environment(
              parent: closureEnvironment,
              interpreter: closureEnvironment.interpreter,
              isClosure: false,
            ),
      _resumeEnvironment = functionBody == null
          ? closureEnvironment
          : Environment(
              parent: closureEnvironment,
              interpreter: closureEnvironment.interpreter,
              isClosure: false,
            ),
      _resumeScriptPath = closureEnvironment.interpreter?.currentScriptPath,
      super() {
    _resumeEnvironment = _executionEnvironment;
    // Register with garbage collector
    closureEnvironment.interpreter?.gc.register(this);
  }

  @override
  int get estimatedSize {
    var size = GcWeights.gcObjectHeader + GcWeights.coroutineBase;
    size += GcWeights.coroutineEnvironmentRef; // closure environment
    size += GcWeights.coroutineEnvironmentRef; // execution environment snapshot
    if (completer != null) {
      size += GcWeights.coroutineEnvironmentRef;
    }
    return size;
  }

  /// Resumes the coroutine with the given arguments
  Future<Value> resume(List<Object?> args) async {
    Logger.debugLazy(
      () => 'Coroutine.resume: Called with status: $status, args: $args',
      category: 'Coroutine',
    );
    if (status == CoroutineStatus.dead) {
      Logger.debugLazy(
        () => 'Coroutine.resume: Coroutine is dead',
        category: 'Coroutine',
      );
      return Value.multi([Value(false), Value("cannot resume dead coroutine")]);
    }

    if (status == CoroutineStatus.running) {
      Logger.debugLazy(
        () => 'Coroutine.resume: Coroutine is running',
        category: 'Coroutine',
      );
      return Value.multi([
        Value(false),
        Value("cannot resume non-suspended coroutine"),
      ]);
    }

    // Get the interpreter from the environment
    final runtime = closureEnvironment.interpreter;
    final previousCoroutine = runtime?.getCurrentCoroutine();
    final previousEnv = runtime?.getCurrentEnv();
    final interpreter = _debugInterpreterForRuntime(runtime);
    // Coroutine resumes can pass through helpers such as pcall/xpcall and
    // iterator frames that yield on behalf of the caller. Save the caller's
    // visible function/local context up front so every resume path can restore
    // the exact lookup state seen before entering the coroutine.
    final previousFunction = interpreter?.getCurrentFunction();
    final previousFastLocals = interpreter?.getCurrentFastLocals();
    final previousHookFunction = interpreter?.debugHookFunction;
    final previousHookMask = interpreter?.debugHookMask;
    final previousHookCount = interpreter?.debugHookCount;
    final previousHookCountRemaining = interpreter?.debugHookCountRemaining;

    try {
      _activeStack.add(this);
      // Set this coroutine as the current one
      if (runtime != null) {
        _restoreCallStack();
        runtime.setCurrentCoroutine(this);
        if (interpreter != null) {
          applyDebugHookStateTo(interpreter);
          _restoreExternalGcRoots(interpreter);
        }
        // When resuming from a yield, restore the saved execution environment
        final resumedEnv = switch (runtime) {
          final Interpreter astInterpreter =>
            astInterpreter.getVisibleFrameAtLevel(1)?.env ?? _resumeEnvironment,
          _ => _resumeEnvironment,
        };
        runtime.setCurrentEnv(resumedEnv); // Restore the saved environment
        runtime.currentScriptPath = _resumeScriptPath;
        runtime.callStack.setScriptPath(_resumeScriptPath);
        Logger.debugLazy(
          () =>
              'Coroutine.resume: Restored saved execution environment: '
              '${runtime.getCurrentEnv().hashCode}',
          category: 'Coroutine',
        );
      }

      if (status == CoroutineStatus.suspended && _executionTask == null) {
        // Initial execution
        Logger.debugLazy(
          () => 'Coroutine.resume: Initial execution',
          category: 'Coroutine',
        );
        status = CoroutineStatus.running;

        // Start the coroutine function with initial arguments
        final initialCompleter = Completer<List<Object?>>();
        completer = initialCompleter;
        _executionTask = _executeCoroutine(args);
        Logger.debugLazy(
          () =>
              'Coroutine.resume: Waiting for _executionTask completion '
              '(initial)',
          category: 'Coroutine',
        );
        final result = await initialCompleter.future;
        Logger.debugLazy(
          () => 'Coroutine.resume: _executionTask completed (initial)',
          category: 'Coroutine',
        );
        if (status == CoroutineStatus.dead) {
          if (interpreter != null) {
            await _finalizeLiveRootFrame(interpreter);
          }
          _finalizeTermination();
          return Value.multi(result);
        }
        _detachCallStack();
        if (interpreter != null) {
          _detachExternalGcRoots(interpreter);
        }
        return Value.multi([Value(true), ...result]);
      } else if (status == CoroutineStatus.suspended) {
        // Resuming from a yield point
        Logger.debugLazy(
          () => 'Coroutine.resume: Resuming from yield',
          category: 'Coroutine',
        );
        status = CoroutineStatus.running;

        // Process arguments for consistency
        final processedArgs = _normalizeValues(args);

        final continuation = takeContinuation();
        if (continuation != null) {
          final currentCompleter = completer;
          final nextCompleter = Completer<List<Object?>>();
          completer = nextCompleter;
          currentCompleter?.complete(processedArgs);

          try {
            final result = await continuation.resume(processedArgs);
            status = CoroutineStatus.dead;
            if (interpreter != null) {
              await _finalizeLiveRootFrame(interpreter);
            }
            _finalizeTermination();
            return _handleReturnValue(result);
          } on YieldException catch (e) {
            status = CoroutineStatus.suspended;
            _detachCallStack();
            if (interpreter != null) {
              _detachExternalGcRoots(interpreter);
            }
            return Value.multi([Value(true), ...e.values]);
          }
        }

        // Resume execution by completing the completer
        final currentCompleter = completer;
        final nextCompleter = Completer<List<Object?>>();
        completer = nextCompleter;

        Logger.debugLazy(
          () =>
              'Coroutine.resume: Completing previous completer with: '
              '$processedArgs',
          category: 'Coroutine',
        );
        currentCompleter?.complete(processedArgs);

        // Wait for the next yield or completion
        Logger.debugLazy(
          () => 'Coroutine.resume: Waiting for next yield or completion',
          category: 'Coroutine',
        );
        final result = await nextCompleter.future;
        Logger.debugLazy(
          () => 'Coroutine.resume: Next yield or completion received',
          category: 'Coroutine',
        );
        if (status == CoroutineStatus.dead) {
          if (interpreter != null) {
            await _finalizeLiveRootFrame(interpreter);
          }
          _finalizeTermination();
          return Value.multi(result);
        }
        _detachCallStack();
        if (interpreter != null) {
          _detachExternalGcRoots(interpreter);
        }
        return Value.multi([Value(true), ...result]);
      } else {
        // This shouldn't happen, but just in case
        Logger.debugLazy(
          () => 'Coroutine.resume: Unexpected state: $status',
          category: 'Coroutine',
        );
        return Value.multi([Value(false), Value("unexpected coroutine state")]);
      }
    } on YieldException catch (e) {
      Logger.debugLazy(
        () => 'Coroutine.resume: Caught YieldException',
        category: 'Coroutine',
      );
      // The coroutine has yielded, it's now suspended. Return the yielded values.
      status = CoroutineStatus.suspended;
      _detachCallStack();
      if (interpreter != null) {
        _detachExternalGcRoots(interpreter);
      }
      return Value.multi([Value(true), ...e.values]);
    } on ReturnException catch (e) {
      Logger.debugLazy(
        () => 'Coroutine.resume: Caught ReturnException',
        category: 'Coroutine',
      );
      // Normal return from the coroutine function
      status = CoroutineStatus.dead;
      _finalizeTermination();
      return _handleReturnValue(e.value);
    } catch (e) {
      Logger.debugLazy(
        () => 'Coroutine.resume: Propagating coroutine error: $e',
        category: 'Coroutine',
      );
      // Unexpected error
      error = e;
      status = CoroutineStatus.dead;
      _finalizeTermination();
      final normalizedError = _normalizeCoroutineError(e);
      return Value.multi([
        Value(false),
        normalizedError is Value ? normalizedError : Value(normalizedError),
      ]);
    } finally {
      if (_activeStack.isNotEmpty && identical(_activeStack.last, this)) {
        _activeStack.removeLast();
      } else {
        _activeStack.removeWhere((c) => identical(c, this));
      }
      Logger.debugLazy(
        () => 'Coroutine.resume: Finally block executed',
        category: 'Coroutine',
      );
      // Restore the previous coroutine and environment
      if (runtime != null) {
        if (interpreter != null) {
          captureDebugHookStateFrom(interpreter);
          interpreter.debugHookFunction = previousHookFunction;
          interpreter.debugHookMask = previousHookMask ?? '';
          interpreter.debugHookCount = previousHookCount ?? 0;
          interpreter.debugHookCountRemaining = previousHookCountRemaining ?? 0;
          interpreter.setCurrentFunction(previousFunction);
          interpreter.setCurrentFastLocals(previousFastLocals);
        }
        runtime.setCurrentCoroutine(previousCoroutine);
        if (previousEnv != null) {
          runtime.setCurrentEnv(previousEnv);
        }

        if (previousCoroutine != null) {
          previousCoroutine._callStackBaseDepth = runtime.callStack.depth;
        }

        // If the previous coroutine exists, update its status
        if (previousCoroutine != null && previousCoroutine != this) {
          if (previousCoroutine.status == CoroutineStatus.normal) {
            previousCoroutine.status = CoroutineStatus.running;
          }
        }
      }
    }
  }

  /// Helper method to handle return values from coroutine
  Value _handleReturnValue(Object? value) {
    if (value == null) {
      return Value.multi([Value(true)]);
    } else if (value is Value) {
      if (value.isMulti) {
        // Extract multiple return values
        final values = value.raw as List<Object?>;
        return Value.multi([Value(true), ...values]);
      } else {
        // Single return value
        return Value.multi([Value(true), value]);
      }
    } else {
      // Wrap raw value
      return Value.multi([Value(true), Value(value)]);
    }
  }

  Future<void> _handleTailCallCompletion(TailCallException t) async {
    final interpreter = closureEnvironment.interpreter;
    if (interpreter == null) {
      await _completeWithError(t);
      return;
    }

    final callee = t.functionValue is Value
        ? t.functionValue as Value
        : Value(t.functionValue);
    final normalizedArgs = t.args
        .map((arg) => arg is Value ? arg : Value(arg))
        .toList();
    final callResult = await interpreter.callFunction(callee, normalizedArgs);
    try {
      await _completeWithReturn(callResult);
    } catch (e) {
      await _completeWithError(e);
    }
  }

  Future<void> _handleTailCallSignalCompletion(TailCallSignal t) async {
    final interpreter = closureEnvironment.interpreter;
    if (interpreter == null) {
      await _completeWithError(t);
      return;
    }

    final callee = t.functionValue is Value
        ? t.functionValue as Value
        : Value(t.functionValue);
    final normalizedArgs = t.args
        .map((arg) => arg is Value ? arg : Value(arg))
        .toList();
    final callResult = await interpreter.callFunction(callee, normalizedArgs);
    try {
      await _completeWithReturn(callResult);
    } catch (e) {
      await _completeWithError(e);
    }
  }

  Future<void> _closeCoroutineScope([dynamic error]) async {
    if (_environmentCleared || functionBody == null) {
      return;
    }
    await _executionEnvironment.closeVariables(error);
  }

  Future<void> _completeWithReturn(Object? value) async {
    try {
      await _closeCoroutineScope();
    } on YieldException {
      installContinuation(_AstReturnCloseContinuation(this, value));
      rethrow;
    }
    status = CoroutineStatus.dead;
    _finalizeTermination();
    if (completer != null && !completer!.isCompleted) {
      final handledResult = _handleReturnValue(value);
      if (handledResult.isMulti) {
        completer!.complete(handledResult.raw as List<Object?>);
      } else {
        completer!.complete([handledResult.raw]);
      }
    }
  }

  Future<void> _completeWithError(Object errorObject) async {
    captureCurrentCallStack();
    error = errorObject;
    status = CoroutineStatus.dead;
    _finalizeTermination();
    if (completer != null && !completer!.isCompleted) {
      final normalizedError = _normalizeCoroutineError(errorObject);
      completer!.complete([
        Value(false),
        normalizedError is Value ? normalizedError : Value(normalizedError),
      ]);
    }
  }

  /// Yields from the coroutine with the given values
  Future<List<Object?>> yield_(List<Object?> values) async {
    final isActive = identical(this, Coroutine.active);
    if (!isActive &&
        status != CoroutineStatus.running &&
        status != CoroutineStatus.normal) {
      throw Exception("attempt to yield from outside a coroutine");
    }
    if (isActive && status != CoroutineStatus.running) {
      status = CoroutineStatus.running;
    }

    // Save the current execution environment before yielding
    final interpreter = closureEnvironment.interpreter;
    if (interpreter != null) {
      _resumeEnvironment = interpreter.getCurrentEnv();
      _resumeScriptPath =
          interpreter.currentScriptPath ?? interpreter.callStack.scriptPath;
      if (interpreter case final Interpreter astInterpreter) {
        final topFrame = astInterpreter.getVisibleFrameAtLevel(1);
        final luaFrame = topFrame?.callable?.functionBody == null
            ? astInterpreter.getVisibleFrameAtLevel(2)
            : topFrame;
        _resumeLine =
            luaFrame?.currentLine ??
            topFrame?.currentLine ??
            astInterpreter.callStack.top?.currentLine ??
            _resumeLine;
      }
      Logger.debugLazy(
        () =>
            'Coroutine.yield_: Saved current execution environment: '
            '${_resumeEnvironment.hashCode}',
        category: 'Coroutine',
      );
    }

    // Set status to suspended
    status = CoroutineStatus.suspended;

    // Complete the current completer with the yielded values
    final currentCompleter = completer;
    final nextCompleter = Completer<List<Object?>>();
    completer = nextCompleter;

    if (currentCompleter != null && !currentCompleter.isCompleted) {
      // Normalize values before yielding
      final normalizedValues = _normalizeValues(values);
      scheduleMicrotask(() {
        if (!currentCompleter.isCompleted) {
          currentCompleter.complete(normalizedValues);
        }
      });
      final yieldedValues = normalizedValues
          .map((value) => value is Value ? value : Value(value))
          .toList(growable: false);

      // Throw YieldException to pause execution and return control
      throw YieldException(
        yieldedValues,
        nextCompleter.future,
        functionBody == null ? this : null,
      );
    }

    throw YieldException(
      const <Value>[],
      nextCompleter.future,
      functionBody == null ? this : null,
    );
  }

  /// Normalize values for consistency between yields and resumes
  List<Object?> _normalizeValues(List<Object?> values) {
    final result = <Object?>[];

    for (final value in values) {
      if (value is Value && value.isMulti) {
        // Expand multi-value into individual values
        result.addAll(
          (value.raw as List<Object?>).map((v) => v is Value ? v : Value(v)),
        );
      } else if (value is List && values.length == 1) {
        // Special case: if the only argument is a list, it might be multi-return values
        // that need to be expanded
        result.addAll(value.map((v) => v is Value ? v : Value(v)));
      } else {
        // Regular value, ensure it's wrapped
        result.add(value is Value ? value : Value(value));
      }
    }

    return result;
  }

  void _restoreCallStack() {
    final interpreter = closureEnvironment.interpreter;
    if (interpreter == null) {
      return;
    }
    final baseDepth = interpreter.callStack.depth;
    if (_savedCallStack != null && _savedCallStack!.isNotEmpty) {
      for (final frame in _savedCallStack!) {
        interpreter.callStack.pushFrame(frame);
      }
      _savedCallStack = null;
    }
    _callStackBaseDepth = baseDepth;
  }

  // Suspended coroutines cannot leave their active-call providers registered on
  // the interpreter itself, because that would make a paused coroutine look
  // permanently reachable from the main thread. Instead we snapshot those
  // providers here and restore them only while the coroutine is actively
  // running again.
  void _restoreExternalGcRoots(Interpreter interpreter) {
    final baseCount = interpreter.externalGcRootProviderCount;
    // These providers were removed from the interpreter-wide root list when
    // the coroutine suspended. Reattaching them only while this coroutine is
    // running prevents a paused coroutine from staying reachable solely
    // through global GC bookkeeping.
    if (_savedExternalGcRootProviders.isNotEmpty) {
      interpreter.appendExternalGcRootProviders(_savedExternalGcRootProviders);
      _savedExternalGcRootProviders = const <Iterable<Object?> Function()>[];
    }
    _savedExternalGcRoots = const <Object?>[];
    _externalGcRootBaseCount = baseCount;
  }

  CallFrame _cloneCallFrame(CallFrame frame) {
    return CallFrame(
      frame.functionName,
      callNode: frame.callNode,
      scriptPath: frame.scriptPath,
      currentLine: frame.currentLine,
      env: frame.env,
      debugName: frame.debugName,
      debugNameWhat: frame.debugNameWhat,
      callable: frame.callable,
      lastDebugHookLine: frame.lastDebugHookLine,
      debugLocals: List<MapEntry<String, Value>>.from(frame.debugLocals),
      ftransfer: frame.ftransfer,
      ntransfer: frame.ntransfer,
      transferValues: List<Value>.from(frame.transferValues),
      extraArgs: frame.extraArgs,
      isDebugHook: frame.isDebugHook,
      isTailCall: frame.isTailCall,
      // Preserve engine-owned execution state so restored bytecode frames keep
      // their register/PC identity for debug APIs such as `debug.getlocal`.
      engineFrameState: frame.engineFrameState,
    );
  }

  List<CallFrame> _snapshotCallStackFrames(CallStack callStack, int base) {
    final frames = callStack.frames.toList(growable: false);
    if (base >= frames.length) {
      return const <CallFrame>[];
    }
    return frames
        .skip(base)
        .where((frame) => !frame.isDebugHook && frame.debugNameWhat != 'hook')
        .map(_cloneCallFrame)
        .toList(growable: false);
  }

  void captureCurrentCallStack() {
    final interpreter = closureEnvironment.interpreter;
    if (interpreter == null) {
      return;
    }
    final snapshot = _snapshotCallStackFrames(
      interpreter.callStack,
      _callStackBaseDepth,
    );
    if (snapshot.isEmpty) {
      return;
    }
    final existing = _savedCallStack;
    if (existing == null || snapshot.length >= existing.length) {
      _savedCallStack = snapshot;
    }
  }

  void _detachCallStack() {
    final interpreter = closureEnvironment.interpreter;
    if (interpreter == null) {
      return;
    }
    final callStack = interpreter.callStack;
    final base = _callStackBaseDepth;
    if (callStack.depth <= base) {
      return;
    }
    final snapshot = _snapshotCallStackFrames(callStack, base);
    while (callStack.depth > base) {
      final frame = callStack.pop();
      if (frame == null) {
        break;
      }
    }
    final existing = _savedCallStack;
    if (snapshot.isNotEmpty &&
        (existing == null || snapshot.length >= existing.length)) {
      _savedCallStack = snapshot;
    }
    _callStackBaseDepth = callStack.depth;
  }

  // Mirror _restoreExternalGcRoots: once the coroutine yields, move any
  // interpreter-owned providers back onto the coroutine object so GC still sees
  // the suspended call chain without also keeping it alive as a main-thread
  // root.
  void _detachExternalGcRoots(Interpreter interpreter) {
    final providers = interpreter.snapshotExternalGcRootProvidersFrom(
      _externalGcRootBaseCount,
    );
    if (providers.isEmpty) {
      return;
    }
    // Snapshot the concrete objects first, then remove the providers from the
    // interpreter-global list. This keeps the paused coroutine's live call
    // chain intact without accidentally rooting the whole suspended coroutine
    // forever from the main interpreter.
    final capturedRoots = <Object?>[];
    for (final provider in providers) {
      capturedRoots.addAll(provider());
    }
    _savedExternalGcRootProviders = providers;
    _savedExternalGcRoots = capturedRoots;
    interpreter.trimExternalGcRootProviders(_externalGcRootBaseCount);
  }

  // A coroutine can finish after having yielded earlier, which means the
  // original _executeCoroutine invocation may already be gone. When that
  // happens, its synthetic root frame still needs a matching debug 'return'
  // hook and stack removal here; otherwise hook traces lose the terminal
  // return event and stale frames leak into debug/GC views.
  Future<void> _finalizeLiveRootFrame(Interpreter interpreter) async {
    if (interpreter.callStack.depth <= _callStackBaseDepth) {
      return;
    }

    // The synthetic coroutine root frame is created by _executeCoroutine, but
    // completion may happen after one or more yield/resume hops. In those
    // cases the original _executeCoroutine invocation is no longer the code
    // performing final cleanup, so we must emit the final return hook and pop
    // the frame explicitly here to match Lua's debug-hook behavior.
    CallFrame? rootFrame;
    for (final frame in interpreter.callStack.frames.toList().reversed) {
      if (identical(frame.callable, functionValue)) {
        rootFrame = frame;
        break;
      }
    }
    if (rootFrame == null) {
      return;
    }

    if (!rootFrame.isDebugHook) {
      await interpreter.fireDebugHook('return');
    }

    if (identical(interpreter.callStack.top, rootFrame)) {
      interpreter.callStack.pop();
    } else {
      interpreter.callStack.removeFrame(rootFrame);
    }
  }

  CallFrame? debugFrameAtLevel(int level) {
    if (level <= 0) {
      return null;
    }

    final interpreter = closureEnvironment.interpreter;
    if (interpreter is Interpreter &&
        status == CoroutineStatus.running &&
        identical(interpreter.getCurrentCoroutine(), this)) {
      final liveFrames = _snapshotCallStackFrames(
        interpreter.callStack,
        _callStackBaseDepth,
      );
      final luaFrames = liveFrames
          .where((frame) => frame.callable?.functionBody != null)
          .toList(growable: false);
      if (luaFrames.isNotEmpty) {
        if (level <= luaFrames.length) {
          return luaFrames[luaFrames.length - level];
        }
        return null;
      }
      if (level == 1 && functionBody != null) {
        return CallFrame(
          functionValue.functionName ?? '?',
          scriptPath: _resumeScriptPath,
          currentLine: _resumeLine,
          env: _resumeEnvironment,
          callable: functionValue,
          lastDebugHookLine: _resumeLine,
        );
      }
      return null;
    }

    final savedFrames = _savedCallStack;
    if (savedFrames != null && savedFrames.isNotEmpty) {
      final luaFrames = savedFrames
          .where((frame) => frame.callable?.functionBody != null)
          .toList(growable: false);
      if (luaFrames.isNotEmpty) {
        if (level <= luaFrames.length) {
          return luaFrames[luaFrames.length - level];
        }
        return null;
      }
    }

    if (level == 1 &&
        functionBody != null &&
        status == CoroutineStatus.suspended) {
      return CallFrame(
        functionValue.functionName ?? '?',
        scriptPath: _resumeScriptPath,
        currentLine: _resumeLine,
        env: _resumeEnvironment,
        callable: functionValue,
        lastDebugHookLine: _resumeLine,
      );
    }
    return null;
  }

  CallFrame? rawDebugFrameAtLevel(int level) {
    if (level <= 0) {
      return null;
    }
    final interpreter = closureEnvironment.interpreter;
    if (interpreter is Interpreter &&
        status == CoroutineStatus.running &&
        identical(interpreter.getCurrentCoroutine(), this)) {
      final liveFrames = _snapshotCallStackFrames(
        interpreter.callStack,
        _callStackBaseDepth,
      );
      if (level > liveFrames.length) {
        return null;
      }
      return liveFrames[liveFrames.length - level];
    }
    final savedFrames = _savedCallStack;
    if (savedFrames == null || level > savedFrames.length) {
      return null;
    }
    return savedFrames[savedFrames.length - level];
  }

  Environment get debugEnvironment => _resumeEnvironment;

  int get debugCurrentLine => _resumeLine;

  int get debugCallStackBaseDepth => _callStackBaseDepth;

  void _finalizeTermination() {
    if (_unregistered) {
      return;
    }
    _continuation = null;
    _savedExternalGcRootProviders = const <Iterable<Object?> Function()>[];
    _savedExternalGcRoots = const <Object?>[];
    _externalGcRootBaseCount = 0;
    final interpreter = closureEnvironment.interpreter;
    if (!_environmentCleared) {
      _clearExecutionEnvironment();
      _environmentCleared = true;
    }
    interpreter?.unregisterCoroutine(this);
    if (error == null) {
      _savedCallStack = null;
    }
    _unregistered = true;
  }

  void _clearExecutionEnvironment() {
    if (identical(_executionEnvironment, closureEnvironment)) {
      return;
    }
    final sharedBoxes = <Box<dynamic>>{
      ...closureEnvironment.values.values,
      ...closureEnvironment.declaredGlobals.values,
    };
    try {
      for (final box in _executionEnvironment.values.values) {
        if (sharedBoxes.contains(box)) {
          continue;
        }
        // Boxes captured by an escaped closure still belong to live code even
        // if the coroutine itself is finishing. Clearing them here breaks
        // yielded closures that intentionally retain locals after the wrapper
        // or coroutine object becomes unreachable.
        if (box.hasUpvalueReferences) {
          continue;
        }
        final current = box.value;
        if (current is Value && current.isNil) {
          continue;
        }
        box.value = Value(null);
      }
      for (final box in _executionEnvironment.declaredGlobals.values) {
        if (sharedBoxes.contains(box)) {
          continue;
        }
        if (box.hasUpvalueReferences) {
          continue;
        }
        final current = box.value;
        if (current is Value && current.isNil) {
          continue;
        }
        box.value = Value(null);
      }
    } catch (_) {}
  }

  /// Executes this coroutine's root function with an isolated interpreter view.
  ///
  /// A wrapped coroutine shares the underlying [Interpreter] instance with the
  /// caller, but it must not inherit the caller's active function metadata or
  /// fast-local bindings. The coroutine root body resolves identifiers before
  /// it has pushed its own ordinary call frame, so any leaked fast-local map
  /// lets those lookups hit caller locals before falling back to the
  /// coroutine's own upvalues and environment chain.
  ///
  /// This method therefore snapshots the caller's active function state,
  /// installs [functionValue] as the active callable, and clears fast locals
  /// until the coroutine finishes or yields. Restoring the saved state in the
  /// `finally` block keeps later caller-side lookups and debug hooks stable
  /// after the coroutine resumes, yields, or terminates with an error.
  Future<void> _executeCoroutine(List<Object?> initialArgs) async {
    Logger.debugLazy(
      () => '_executeCoroutine: Starting execution, PC: $_programCounter',
      category: 'Coroutine',
    );
    // Create initial environment for function parameters and locals
    final interpreter = closureEnvironment.interpreter;
    final astInterpreter = interpreter is Interpreter ? interpreter : null;
    final savedFunction = astInterpreter?.getCurrentFunction();
    final savedFastLocals = astInterpreter?.getCurrentFastLocals();
    CallFrame? coroutineRootFrame;
    var coroutineRootFrameNeedsReturnHook = false;
    if (astInterpreter != null) {
      astInterpreter.setCurrentFunction(functionValue);
      // A wrapped coroutine must not inherit the caller's fast-local map.
      // Otherwise identifiers in the coroutine root body can resolve against
      // caller locals before falling back to their own upvalues/env chain.
      astInterpreter.setCurrentFastLocals(null);
    }

    try {
      // Process arguments for the function call
      final processedArgs = initialArgs.map((arg) {
        return arg is Value ? arg : Value(arg);
      }).toList();

      final body = functionBody;
      if (body == null) {
        try {
          final interpreter = closureEnvironment.interpreter;
          if (interpreter == null) {
            throw LuaError('coroutine has no interpreter');
          }
          interpreter.setCurrentEnv(_executionEnvironment);
          final result = await interpreter.callFunction(
            functionValue,
            processedArgs,
          );
          await _completeWithReturn(result);
        } on CoroutineCloseSignal catch (signal) {
          if (completer != null && !completer!.isCompleted) {
            completer!.complete(signal.result);
          }
          return;
        } on YieldException {
          return;
        } on TailCallException catch (t) {
          await _handleTailCallCompletion(t);
        } catch (e) {
          await _completeWithError(e);
        }
        return;
      }

      // Bind regular parameters
      final hasVarargs = body.isVararg;
      final namedVararg = body.varargName?.name;
      int regularParamCount = body.parameters?.length ?? 0;

      for (var i = 0; i < regularParamCount; i++) {
        final paramName = (body.parameters![i]).name;
        if (i < processedArgs.length) {
          _executionEnvironment.declare(paramName, processedArgs[i]);
        } else {
          _executionEnvironment.declare(paramName, Value(null));
        }
      }

      // Handle varargs if present
      if (hasVarargs) {
        List<Object?> varargs = processedArgs.length > regularParamCount
            ? processedArgs.sublist(regularParamCount)
            : [];
        _executionEnvironment.declare("...", Value.multi(varargs));
        if (namedVararg != null) {
          _executionEnvironment.declare(
            namedVararg,
            _packCoroutineVarargsTable(varargs),
          );
        }
      }

      if (astInterpreter != null) {
        final topFrame = astInterpreter.callStack.top;
        final hasCoroutineRootFrame =
            topFrame != null &&
            identical(topFrame.callable, functionValue) &&
            identical(topFrame.env, _executionEnvironment);
        if (!hasCoroutineRootFrame) {
          coroutineRootFrame = CallFrame(
            functionValue.functionName ?? '?',
            scriptPath: _resumeScriptPath,
            currentLine: _resumeLine,
            env: _executionEnvironment,
            callable: functionValue,
          );
          astInterpreter.callStack.pushFrame(coroutineRootFrame);
          coroutineRootFrameNeedsReturnHook = true;
          if (!coroutineRootFrame.isDebugHook) {
            await astInterpreter.fireDebugHook('call');
          }
        } else {
          coroutineRootFrame = topFrame;
          coroutineRootFrameNeedsReturnHook = true;
        }
      }

      try {
        // Execute statements from the current program counter
        for (; _programCounter < body.body.length; _programCounter++) {
          final stmt = body.body[_programCounter];

          Logger.debugLazy(
            () =>
                '_executeCoroutine: Executing statement $_programCounter: '
                '${stmt.runtimeType}',
            category: 'Coroutine',
          );
          // Ensure the interpreter's environment is set to this coroutine's execution environment
          if (interpreter != null) {
            interpreter.setCurrentEnv(_executionEnvironment);
          }

          final astInterpreter = interpreter is Interpreter
              ? interpreter
              : null;
          astInterpreter?.recordTrace(stmt);
          final hookAfterExecution =
              astInterpreter?.shouldFireStatementHookAfterExecution(stmt) ??
              false;
          if (!hookAfterExecution) {
            await astInterpreter?.maybeFireStatementDebugHooks(stmt);
          }

          final result = await interpreter!.evaluateAst(stmt);
          if (hookAfterExecution &&
              astInterpreter != null &&
              !astInterpreter.consumeSuppressedPostExecutionHook(stmt)) {
            await astInterpreter.maybeFireStatementDebugHooks(stmt);
          }
          if (result is TailCallSignal) {
            await _handleTailCallSignalCompletion(result);
            Logger.debugLazy(
              () =>
                  '_executeCoroutine: Completer completed with tail-call signal result',
              category: 'Coroutine',
            );
            return;
          }
          Logger.debugLazy(
            () =>
                '_executeCoroutine: Statement $_programCounter executed. '
                'Current PC: $_programCounter',
            category: 'Coroutine',
          );
        }

        // Coroutine completed normally
        Logger.debugLazy(
          () => '_executeCoroutine: Coroutine completed normally',
          category: 'Coroutine',
        );
        status = CoroutineStatus.dead;
        await _closeCoroutineScope();
        _finalizeTermination();
        if (completer != null && !completer!.isCompleted) {
          completer!.complete([Value(true)]);
          Logger.debugLazy(
            () => '_executeCoroutine: Completer completed with success result',
            category: 'Coroutine',
          );
        }
      } on YieldException {
        Logger.debugLazy(
          () => '_executeCoroutine: Caught YieldException',
          category: 'Coroutine',
        );
        // YieldException is thrown by yield_ to pause execution.
        // It should be re-thrown here so resume can catch it and manage state.
        rethrow;
      } on ReturnException catch (e) {
        Logger.debugLazy(
          () => '_executeCoroutine: Caught ReturnException',
          category: 'Coroutine',
        );
        try {
          await _completeWithReturn(e.value);
        } on YieldException {
          return;
        } catch (closeError) {
          await _completeWithError(closeError);
          return;
        }
        Logger.debugLazy(
          () => '_executeCoroutine: Completer completed with return value',
          category: 'Coroutine',
        );
      } on TailCallException catch (t) {
        await _handleTailCallCompletion(t);
        Logger.debugLazy(
          () => '_executeCoroutine: Completer completed with tail-call result',
          category: 'Coroutine',
        );
      } on CoroutineCloseSignal catch (signal) {
        if (completer != null && !completer!.isCompleted) {
          completer!.complete(signal.result);
        }
        return;
      } catch (e) {
        var finalError = e;
        try {
          await _closeCoroutineScope(e);
        } catch (closeError) {
          finalError = closeError;
        }
        Logger.debugLazy(
          () => '_executeCoroutine: Propagating coroutine error: $e',
          category: 'Coroutine',
        );
        await _completeWithError(finalError);
        Logger.debugLazy(
          () => '_executeCoroutine: Completer completed with error',
          category: 'Coroutine',
        );
      }
    } finally {
      if (astInterpreter != null &&
          coroutineRootFrame != null &&
          status == CoroutineStatus.dead) {
        final topFrame = astInterpreter.callStack.top;
        if (identical(topFrame, coroutineRootFrame)) {
          if (coroutineRootFrameNeedsReturnHook &&
              !coroutineRootFrame.isDebugHook) {
            await astInterpreter.fireDebugHook('return');
          }
          astInterpreter.callStack.pop();
        }
      }
      astInterpreter?.setCurrentFastLocals(savedFastLocals);
      astInterpreter?.setCurrentFunction(savedFunction);
    }
  }

  /// Called to close the coroutine
  Future<List<Object?>> close([dynamic error]) async {
    if (status == CoroutineStatus.dead) {
      Logger.debugLazy(
        () => 'Coroutine already dead, nothing to close',
        category: 'Coroutine',
      );
      final pendingError = this.error;
      if (pendingError != null) {
        this.error = null;
        _finalizeTermination();
        final normalized = _normalizeCoroutineError(pendingError);
        return [
          Value(false),
          normalized is Value ? normalized : Value(normalized),
        ];
      }
      _finalizeTermination();
      return [Value(true)]; // Already dead, consider it successful close
    }

    Logger.debugLazy(
      () => 'Closing coroutine with status: $status',
      category: 'Coroutine',
    );

    final continuation = takeContinuation();
    if (continuation != null) {
      try {
        await continuation.close(error);
      } on YieldException {
        status = CoroutineStatus.dead;
        _finalizeTermination();
        return [
          Value(false),
          Value('attempt to yield across a C-call boundary'),
        ];
      } catch (caughtError) {
        status = CoroutineStatus.dead;
        _finalizeTermination();
        final normalized = _normalizeCoroutineError(caughtError);
        return [
          Value(false),
          normalized is Value ? normalized : Value(normalized),
        ];
      }
    }

    // Closing a suspended coroutine must unwind its to-be-closed variables
    // directly; it must not synthetically resume the pending yield future.
    // Completing the stored completer here lets suspended AST frames observe a
    // fake normal resume while close handlers are still unwinding, which breaks
    // nested __close error propagation.

    // Set status to dead
    status = CoroutineStatus.dead;
    try {
      await _closeCoroutineScope(error);
    } on YieldException {
      error = LuaError('attempt to yield across a C-call boundary');
    } catch (caughtError) {
      error = caughtError;
    }
    _finalizeTermination();

    // Propagate the error if provided
    if (error != null) {
      final normalized = _normalizeCoroutineError(error);
      return [
        Value(false),
        normalized is Value ? normalized : Value(normalized),
      ];
    }

    return [Value(true)]; // Successful close
  }

  /// Mark the coroutine as dead and release resources
  void markAsDead() {
    status = CoroutineStatus.dead;
    completer = null;
    _executionTask = null;
    _finalizeTermination();
  }

  /// Check if this coroutine is yieldable
  bool isYieldable(Coroutine mainThread) {
    if (identical(this, mainThread)) {
      return false;
    }
    if (identical(this, Coroutine.active)) {
      final runtime = closureEnvironment.interpreter;
      return runtime?.isYieldable ?? true;
    }
    return status != CoroutineStatus.dead && status != CoroutineStatus.normal;
  }

  void resetDebugHookCounter() {
    debugHookCountRemaining = debugHookCount;
  }

  void applyDebugHookStateTo(Interpreter interpreter) {
    interpreter.debugHookFunction = debugHookFunction;
    interpreter.debugHookMask = debugHookMask;
    interpreter.debugHookCount = debugHookCount;
    interpreter.debugHookCountRemaining = debugHookCountRemaining;
  }

  void captureDebugHookStateFrom(Interpreter interpreter) {
    debugHookFunction = interpreter.debugHookFunction;
    debugHookMask = interpreter.debugHookMask;
    debugHookCount = interpreter.debugHookCount;
    debugHookCountRemaining = interpreter.debugHookCountRemaining;
  }

  @override
  List<GCObject> getReferences() {
    final refs = <GCObject>[];
    refs.add(functionValue);
    refs.add(closureEnvironment);
    refs.add(_executionEnvironment);
    if (!identical(_resumeEnvironment, _executionEnvironment)) {
      refs.add(_resumeEnvironment);
    }
    final hook = debugHookFunction;
    if (hook != null) {
      refs.add(hook);
    }
    final continuation = _continuation;
    if (continuation != null) {
      refs.addAll(continuation.getReferences());
    }
    for (final root in _savedExternalGcRoots) {
      if (root is GCObject) {
        refs.add(root);
      }
    }
    // if (_originalArgs != null) {
    //   refs.addAll(_originalArgs!);
    // }
    return refs;
  }

  @override
  void free() {
    status = CoroutineStatus.dead;
    completer = null;
    _executionTask = null;
    _continuation = null;
    _savedExternalGcRootProviders = const <Iterable<Object?> Function()>[];
    _savedExternalGcRoots = const <Object?>[];
    _externalGcRootBaseCount = 0;
    _finalizeTermination();
  }

  /// Records an error that occurred in the coroutine
  void recordError(Object error, StackTrace trace) {
    this.error = error;
  }

  @override
  String toString() {
    return 'Coroutine(status: $status)';
  }

  /// Resets the coroutine to its initial state for reuse.
  void reset() {
    status = CoroutineStatus.suspended;
    completer = null;
    _executionTask = null;
    _continuation = null;
    _savedExternalGcRootProviders = const <Iterable<Object?> Function()>[];
    _savedExternalGcRoots = const <Object?>[];
    _externalGcRootBaseCount = 0;
    _programCounter = 0; // Reset program counter
    _resumeEnvironment = _executionEnvironment;
    _resumeScriptPath = closureEnvironment.interpreter?.currentScriptPath;
    // _executionEnvironment should be re-initialized from closureEnvironment
    // or explicitly cleared if not reused directly.
  }

  bool get hasContinuation => _continuation != null;

  CoroutineContinuation? get debugContinuation => _continuation;

  CoroutineContinuation? takeContinuation() {
    final continuation = _continuation;
    _continuation = null;
    return continuation;
  }

  void installContinuation(CoroutineContinuation continuation) {
    _continuation = continuation;
  }
}
