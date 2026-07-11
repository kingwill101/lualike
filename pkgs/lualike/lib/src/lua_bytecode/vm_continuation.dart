part of 'vm.dart';

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

/// Synchronous fast path for frame close when there's no close work.
/// Returns true if the close was handled synchronously (no close work).
@pragma('vm:prefer-inline')
bool _closeFrameForCoroutineSync(
  LuaBytecodeFrame frame, {
  int fromRegister = 0,
}) {
  if (!frame.hasCloseWorkFrom(fromRegister)) {
    if (fromRegister == 0) {
      frame.closed = true;
    }
    return true;
  }
  return false;
}

Future<void> _closeFrameForCoroutine(
  LuaBytecodeFrame frame, {
  int fromRegister = 0,
  required Object? error,
}) async {
  if (_closeFrameForCoroutineSync(frame, fromRegister: fromRegister)) {
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
  LuaBytecodeFrame frame,
  bool resumeInProtectedCall,
  CoroutineContinuation? child,
) {
  if (child case final LuaBytecodeFrameSuspension suspension
      when identical(suspension.frame, frame) &&
          suspension.resumeInProtectedCall == resumeInProtectedCall) {
    return suspension;
  }
  return LuaBytecodeFrameSuspension(
    vm: vm,
    frame: frame,
    resumeInProtectedCall: resumeInProtectedCall,
    child: child,
  );
}

void _tmpDebugFrame(LuaBytecodeFrame frame, String message) {
  if (platform.getEnvironmentVariable('LUALIKE_DEBUG_BYTECODE_CONT') == '1') {
    print(
      '[bc-cont] pc=${frame.pc} top=${frame.top} openTop=${frame.openTop} '
      'closed=${frame.closed} $message',
    );
  }
}

LuaBytecodeFrame? _tmpContinuationFrame(CoroutineContinuation continuation) {
  return switch (continuation) {
    LuaBytecodeCallSuspension(:final frame) => frame,
    LuaBytecodeConcatSuspension(:final frame) => frame,
    LuaBytecodeConditionalJumpSuspension(:final frame) => frame,
    LuaBytecodeFrameSuspension(:final frame) => frame,
    LuaBytecodeResumeOnlySuspension(:final frame) => frame,
    LuaBytecodeStoreRegisterSuspension(:final frame) => frame,
    LuaBytecodeCloseSuspension(:final frame) => frame,
    LuaBytecodeReturnSuspension(:final frame) => frame,
    LuaBytecodeTailCallSuspension(:final frame) => frame,
    LuaBytecodeTForCallSuspension(:final frame) => frame,
    _ => null,
  };
}

CoroutineContinuation? _bytecodeContinuationChild(
  CoroutineContinuation continuation,
) {
  return switch (continuation) {
    LuaBytecodeCallSuspension(:final child) => child,
    LuaBytecodeConcatSuspension(:final child) => child,
    LuaBytecodeProtectedCallSuspension(:final child) => child,
    LuaBytecodeCloseSuspension(:final child) => child,
    LuaBytecodeFrameSuspension(:final child) => child,
    LuaBytecodeReturnSuspension(:final child) => child,
    LuaBytecodeTailCallSuspension(:final child) => child,
    LuaBytecodeTForCallSuspension(:final child) => child,
    _ => null,
  };
}

CallFrame _bytecodeSuspendedDebugFrame(LuaBytecodeFrame frame) {
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
  bindBytecodeCallFrame(callFrame, frame);
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
  final seenFrames = <LuaBytecodeFrame>{};
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
  if (bytecodeFrameForCallFrame(frame) case final bytecodeFrame?) {
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
  }
  if (debugInterpreter == null) {
    return null;
  }

  return debugInterpreter.getVisibleFrameAtLevel(
    level,
    hideEnclosingDebugHooks: true,
  );
}

void _syncFrameDebugVarargs(CallFrame? frame, List<Object?> values) {
  if (frame == null) {
    return;
  }
  if (bytecodeFrameForCallFrame(frame) case final bytecodeFrame?) {
    final normalized = values
        .map(
          (value) => value is Value
              ? value
              : runtimeValue(bytecodeFrame.runtime, value),
        )
        .toList(growable: true);
    bytecodeFrame.setMaterializedVarargs(normalized);
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

List<MapEntry<String, Value>> _bytecodeFrameLocals(CallFrame frame) {
  final locals = <MapEntry<String, Value>>[];
  final nilValue = bytecodeFrameNilValue(frame);
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
          (local) => localHasPendingClosureTemporaryOnCurrentLine(
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
                    localStartsOnCurrentLine(
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

bool localStartsOnCurrentLine(
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

bool localHasPendingClosureTemporaryOnCurrentLine(
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

void overwriteValue(Value target, Value source) {
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
