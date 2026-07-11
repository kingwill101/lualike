part of 'vm.dart';

final Expando<List<LuaBytecodeFrame>> _bytecodeFramePoolByClosure =
    Expando<List<LuaBytecodeFrame>>('luaBytecodeFramePool');

extension LuaBytecodeVmCallEntry on LuaBytecodeVm {
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
        ? (_activeProfile = LuaBytecodeProfile(
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

        // Reuse a previously closed frame when possible; bytecode calls are
        // frequent enough that constructor allocation shows up in profiles.
        final frame = _acquireBytecodeFrame(
          currentClosure,
          functionValue: currentFunctionValue,
          arguments: currentArgs,
          callName: currentCallName,
          callNameWhat: currentCallNameWhat,
          isEntryFrame: currentIsEntryFrame,
          isTailCall: currentIsTailCall,
          extraArgs: currentExtraArgs,
        );

        try {
          final result = await _runFrame(frame);
          _releaseBytecodeFrameIfReusable(frame);
          return result;
        } on TailCallException catch (tail) {
          _releaseBytecodeFrameIfReusable(frame);
          // Fast path: when the tail-call target is already a
          // LuaBytecodeClosure (the hot path) and no debug hooks are
          // active, skip _flattenTailCallable and name resolution.
          final tailRawCallee = rawLuaSlot(tail.functionValue);
          if (tailRawCallee is LuaBytecodeClosure &&
              _debugInterpreter?.debugHookFunction == null) {
            currentClosure = tailRawCallee;
            currentArgs = tail.args;
            currentFunctionValue = tail.functionValue;
            currentCallName = null;
            currentCallNameWhat = null;
            currentIsTailCall = true;
            currentExtraArgs = 0;
            continue;
          }
          final prepared = _flattenTailCallable(tail.functionValue, tail.args);
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
        } on YieldException {
          rethrow;
        } catch (error) {
          _releaseBytecodeFrameIfReusable(frame);
          rethrow;
        }
      }
    } finally {
      if (startedProfile != null && identical(_activeProfile, startedProfile)) {
        startedProfile.printSummary();
        _activeProfile = null;
      }
    }
  }

  LuaBytecodeFrame _acquireBytecodeFrame(
    LuaBytecodeClosure closure, {
    Value? functionValue,
    required List<Object?> arguments,
    String? callName,
    String? callNameWhat,
    required bool isEntryFrame,
    bool isTailCall = false,
    int extraArgs = 0,
  }) {
    final pool = _bytecodeFramePoolByClosure[closure];
    if (pool != null && pool.isNotEmpty) {
      final frame = pool.removeLast();
      frame.reset(
        functionValue: functionValue,
        callName: callName,
        callNameWhat: callNameWhat,
        isEntryFrame: isEntryFrame,
        isTailCall: isTailCall,
        extraArgs: extraArgs,
        arguments: arguments,
      );
      frame.isInPool = false;
      return frame;
    }
    return LuaBytecodeFrame(
      runtime: runtime,
      closure: closure,
      functionValue: functionValue,
      arguments: arguments,
      callName: callName,
      callNameWhat: callNameWhat,
      isEntryFrame: isEntryFrame,
      isTailCall: isTailCall,
      extraArgs: extraArgs,
    );
  }

  void _releaseBytecodeFrameIfReusable(LuaBytecodeFrame frame) {
    if (!frame.closed || frame.isInPool) {
      return;
    }
    // Only fully unwound frames can be recycled; suspended continuations
    // still need their live frame state. Guard against double-releasing a
    // frame that is already back in the pool.
    frame.clearForPool();
    frame.isInPool = true;
    (_bytecodeFramePoolByClosure[frame.closure] ??= <LuaBytecodeFrame>[]).add(
      frame,
    );
  }

  ({Value callee, List<Object?> args, int extraArgs}) _flattenTailCallable(
    Object? callee,
    List<Object?> args,
  ) {
    var currentCallee = callee is Value
        ? callee
        : valueFromLuaSlot(runtime, callee);
    var extraArgs = 0;
    while (true) {
      currentCallee.interpreter ??= runtime;
      final rawCallee = rawLuaSlot(currentCallee);
      switch (rawCallee) {
        case LuaBytecodeClosure():
        case Function():
        case BuiltinFunction():
        case FunctionDef():
        case FunctionLiteral():
        case FunctionBody():
        case LuaCallableArtifact():
          return (callee: currentCallee, args: args, extraArgs: extraArgs);
        case final String name:
          final rebound = runtime.globals.get(name);
          if (rebound != null) {
            currentCallee = rebound;
            continue;
          }
          return (callee: currentCallee, args: args, extraArgs: extraArgs);
        default:
          if (!currentCallee.hasMetamethod('__call')) {
            return (callee: currentCallee, args: args, extraArgs: extraArgs);
          }
          final callMeta = currentCallee.getMetamethod('__call');
          if (callMeta == null) {
            return (callee: currentCallee, args: args, extraArgs: extraArgs);
          }
          if (extraArgs >= 15) {
            throw LuaError("'__call' chain too long");
          }
          final originalCallee = currentCallee;
          currentCallee = valueFromLuaSlot(runtime, callMeta);
          args = <Object?>[originalCallee, ...args];
          extraArgs += 1;
      }
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

  bool _isCallTypeErrorMessage(String message) =>
      message.startsWith('attempt to call ') ||
      message.contains("attempt to call a ");

  bool _looksFormattedBytecodeLuaErrorMessage(String message) =>
      _bytecodeFormattedLuaErrorPattern.hasMatch(message);

  int? _callSiteLine(LuaBytecodeFrame? frame) => switch (frame) {
    final LuaBytecodeFrame caller when caller.pc > 0 =>
      caller.closure.prototype.lineForPc(caller.pc - 1),
    _ => null,
  };

  Future<List<Value>> _callAt(
    LuaBytecodeFrame frame,
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
    ({Value callee, List<Object?> args}) call, {
    LuaBytecodeFrame? frame,
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

  Future<List<Value>> _invokeValueWithName(
    Value callee,
    List<Object?> args, {
    String? callName,
    String? callNameWhat,
    int extraArgs = 0,
    LuaBytecodeFrame? callerFrame,
    bool isTailCall = false,
  }) async {
    // Fast path: bytecode-to-bytecode direct call with no debug hooks.
    // Skips tail-call flattening, builtin checks, and debug local handling.
    if (_debugInterpreter?.debugHookFunction == null) {
      final rawCallee = rawLuaSlot(callee);
      if (rawCallee is LuaBytecodeClosure) {
        return invoke(
          rawCallee,
          args,
          functionValue: callee,
          callName: callName ?? _callableName(callee),
          callNameWhat: callNameWhat,
          isTailCall: isTailCall,
          extraArgs: extraArgs,
        );
      }
      if (rawCallee is BuiltinFunction &&
          _canInlineBuiltinWithoutManagedFrame(rawCallee) &&
          !(runtime.isInProtectedCall && rawCallee.isBytecodeAssertBuiltin)) {
        final valueArgs = args.cast<Value>();
        return _invokeInlineBuiltin(callee, valueArgs, builtin: rawCallee);
      }
    }
    final prepared = _flattenTailCallable(callee, args);
    callee = prepared.callee;
    args = prepared.args;
    final valueArgs = args.cast<Value>();
    extraArgs += prepared.extraArgs;
    if (callerFrame case final parentBytecodeFrame?) {
      final callerCallFrame = runtime.callStack.top;
      if (callerCallFrame != null) {
        // Coroutine resume restores cloned CallFrame objects. Before any
        // nested bytecode call, reattach the live bytecode frame so traceback
        // and hook stack walks see current registers/PC rather than state
        // snapshotted at the last yield point.
        bindBytecodeCallFrame(callerCallFrame, parentBytecodeFrame);
        _syncDebugLocals(parentBytecodeFrame, callFrame: callerCallFrame);
      }
    }
    // `debug.getlocal` / `debug.setlocal` need the paused caller's live local
    // window, not just whatever snapshot the shared debug library last saw on
    // the stack. Keep the bytecode-specific path so we can resync the caller
    // frame against the exact paused PC before delegating to the builtin.
    final debugLocalHandled = _tryHandleDebugLocalBuiltin(
      callee,
      valueArgs,
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
      valueArgs,
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
        valueArgs,
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
    final rewrittenArgs = _rewriteCoroutineFactoryArgs(
      callee,
      valueArgs,
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
      _setTransferInfo(runtime.callStack.top, rewrittenArgs);
      final interpreter = callDebugInterpreter;
      await interpreter.fireDebugHook('call');
      _clearTransferInfo(runtime.callStack.top);
    }
    Iterable<Value> tempRootProvider() sync* {
      yield callee;
      for (final arg in rewrittenArgs) {
        yield arg;
      }
    }

    runtime.pushExternalGcRoots(tempRootProvider);
    final yieldableAtCallEntry = runtime.isYieldable;
    List<Value> returnTransferValues = const <Value>[];
    try {
      final result = await runtime.callFunction(callee, rewrittenArgs);
      final normalized = _normalizeResults(result);
      returnTransferValues = normalized;
      return normalized;
    } on CoroutineCloseSignal catch (signal) {
      closeSignalYieldableStates[signal] =
          (closeSignalYieldableStates[signal] ?? true) && yieldableAtCallEntry;
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

  bool _canInlineBuiltinWithoutManagedFrame(BuiltinFunction builtin) {
    return builtin.canBytecodeInlineWithoutManagedFrame &&
        !builtin.isBytecodeAssertBuiltin;
  }

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
    LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word, {
    required BuiltinFunction builtin,
  }) {
    final args = LuaBytecodeFrameArgsView(
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
    LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word, {
    required BuiltinFunction builtin,
  }) {
    if (!builtin.isBytecodeAssertBuiltin) {
      return inlineBuiltinUnhandled;
    }
    final count = word.b == 0 ? frame.effectiveTop - (word.a + 1) : word.b - 1;
    if (count <= 0) {
      return inlineBuiltinUnhandled;
    }

    final firstArg = frame.slotValue(word.a + 1);
    final firstArgResults = luaResultValues(firstArg);
    final primaryCondition =
        firstArgResults != null && firstArgResults.isNotEmpty
        ? firstArgResults.first is Value
              ? firstArgResults.first as Value
              : runtimeValue(runtime, firstArgResults.first)
        : firstArg;
    if (!isLuaTruthy(primaryCondition)) {
      return inlineBuiltinUnhandled;
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
          : framePrimitiveValue(runtime, null);
      frame.setRegister(word.a + index, value);
    }
    return null;
  }

  Object? _tryHandleFixedArityInlineBuiltinCall(
    LuaBytecodeFrame frame,
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
      if (!identical(fastAssertResult, inlineBuiltinUnhandled)) {
        return fastAssertResult;
      }
      return inlineBuiltinUnhandled;
    }
    if (!_canInlineBuiltinWithoutManagedFrame(builtin)) {
      return inlineBuiltinUnhandled;
    }
    final rawFastResult = _tryInlineBuiltinFastArityRawFromFrame(
      frame,
      word,
      builtin: builtin,
    );
    if (identical(rawFastResult, BuiltinFunction.fastCallUnsupported)) {
      return inlineBuiltinUnhandled;
    }
    return _tryStoreFastInlineResult(frame, word.a, word.c, rawFastResult);
  }

  Object? _tryStoreInlineAssertSuccessFast(
    LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word, {
    required BuiltinFunction builtin,
  }) {
    if (!builtin.isBytecodeAssertBuiltin || word.b != 2 || word.c != 1) {
      return inlineBuiltinUnhandled;
    }
    final firstArg = frame.slotValue(word.a + 1);
    if (luaResultValues(firstArg) != null) {
      return inlineBuiltinUnhandled;
    }
    return isLuaTruthy(firstArg) ? null : inlineBuiltinUnhandled;
  }

  Value _normalizeInlineAssertSuccessValue(Value value) {
    if (luaResultValues(value) == null) {
      final raw = rawLuaSlot(value);
      if (isLuaPrimitiveSlot(raw)) {
        return switch (raw) {
          null ||
          bool() ||
          num() ||
          BigInt() => framePrimitiveValue(runtime, raw),
          _ => runtimeValue(runtime, raw),
        };
      }
    }
    return value;
  }

  Object? _tryInlineBuiltinFastArityRawFromFrame(
    LuaBytecodeFrame frame,
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
    LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    Object? result,
  ) {
    if (isLuaResults(result)) {
      return inlineBuiltinUnhandled;
    }
    final normalizedValue = switch (result) {
      null => framePrimitiveValue(runtime, null),
      final Value value when isSharedRuntimeConstant(runtime, value) =>
        switch (rawLuaSlot(value)) {
          null ||
          bool() ||
          num() ||
          BigInt() => framePrimitiveValue(runtime, rawLuaSlot(value)),
          _ => value,
        },
      final Value value when luaResultValues(value) == null => value,
      final raw => switch (raw) {
        bool() || num() || BigInt() => framePrimitiveValue(runtime, raw),
        _ => runtimeValue(runtime, raw),
      },
    };
    if (luaResultValues(normalizedValue) != null) {
      return inlineBuiltinUnhandled;
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
      frame.setRegister(register + index, runtimeValue(runtime, null));
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
    LuaBytecodeFrame? callerFrame,
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
        ? coerceLuaInteger(rawLuaSlot(args[0]))
        : null;
    final index = args.length >= 2
        ? coerceLuaInteger(rawLuaSlot(args[1]))
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
              runtimeValue(runtime, value),
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
            overwriteValue(entry.value, args[2]);
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
    LuaBytecodeFrame? callerFrame,
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
        final callArgs = args.length == 1
            ? const <Object?>[]
            : args.sublist(1).cast<Object?>();
        return _invokeBytecodePCall(func, callArgs);
      },
    );
  }

  Future<List<Value>> _invokeBytecodePCall(
    Value func,
    List<Object?> callArgs,
  ) async {
    runtime.enterProtectedCall();
    try {
      if (!func.isCallable()) {
        throw LuaError.typeError('attempt to call a ${getLuaType(func)} value');
      }

      final callResults = await _invokeValueWithName(func, callArgs);
      return <Value>[runtimeValue(runtime, true), ...callResults];
    } on TailCallException catch (tail) {
      final callee = valueFromLuaSlot(runtime, tail.functionValue);
      final awaitedResult = await runtime.callFunction(callee, tail.args);
      return _packBytecodeProtectedCallSuccess(awaitedResult);
    } on CoroutineCloseSignal {
      rethrow;
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? runtime.getCurrentCoroutine();
      if (coroutine != null) {
        final nextChild = coroutine.takeContinuation();
        _installBytecodeContinuation(
          coroutine,
          LuaBytecodeProtectedCallSuspension(vm: this, child: nextChild),
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
        runtimeValue(runtime, true),
        ...multiValues.map((value) => runtimeValue(runtime, value)),
      ];
    }
    if (result == null) {
      return <Value>[runtimeValue(runtime, true)];
    }
    return <Value>[runtimeValue(runtime, true), runtimeValue(runtime, result)];
  }

  List<Value> _packBytecodeProtectedCallFailure(Object error) {
    final normalizedError = _normalizeBytecodeProtectedCallError(error);
    return <Value>[
      runtimeValue(runtime, false),
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
    LuaBytecodeFrame? callerFrame,
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
      closeSignalYieldableStates[signal] =
          (closeSignalYieldableStates[signal] ?? true) && yieldableAtCallEntry;
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

  Future<void> _fireFrameCallHook(
    LuaBytecodeFrame frame,
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
    LuaBytecodeFrame frame,
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
    LuaBytecodeFrame frame,
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
            name: stringConstantRaw(prototype, word.c),
            namewhat: 'global',
          ),
          false => (
            name: stringConstantRaw(prototype, word.c),
            namewhat: 'field',
          ),
        },
        Opcode.self => (
          name: stringConstantRaw(prototype, word.c),
          namewhat: 'method',
        ),
        Opcode.getTabUp => (
          name: stringConstantRaw(prototype, word.c),
          namewhat: 'global',
        ),
        Opcode.getUpval => (
          name: frame.closure.upvalueName(word.b),
          namewhat: 'upvalue',
        ),
        Opcode.loadK => switch (constantRaw(prototype, word.bx)) {
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
        Opcode.loadKx => switch (constantRaw(
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
    LuaBytecodeFrame frame,
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
    LuaBytecodeFrame frame,
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
}
