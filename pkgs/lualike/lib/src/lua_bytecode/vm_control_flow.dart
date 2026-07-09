part of 'vm.dart';

extension LuaBytecodeVmControlFlow on LuaBytecodeVm {
  Never _suspendConditionalJump(
    LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      LuaBytecodeConditionalJumpSuspension(
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
    LuaBytecodeFrame frame,
    int register,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      LuaBytecodeStoreRegisterSuspension(
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
    LuaBytecodeFrame frame,
    int startRegister,
    int nextOffset,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      LuaBytecodeConcatSuspension(
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

  Never _suspendResumeOnly(LuaBytecodeFrame frame, YieldException error) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      LuaBytecodeResumeOnlySuspension(
        vm: this,
        frame: frame,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendCall(
    LuaBytecodeFrame frame,
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
      LuaBytecodeCallSuspension(
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

  Never _suspendTailCall(LuaBytecodeFrame frame, YieldException error) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _tmpDebugFrame(
      frame,
      'suspend-tailcall child=${child.runtimeType} pc=${frame.pc}',
    );
    _installBytecodeContinuation(
      coroutine,
      LuaBytecodeTailCallSuspension(
        vm: this,
        frame: frame,
        resumeInProtectedCall: runtime.isInProtectedCall,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendTForCall(
    LuaBytecodeFrame frame,
    int base,
    int resultCount,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      LuaBytecodeTForCallSuspension(
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
    LuaBytecodeFrame frame,
    int fromRegister,
    YieldException error,
  ) {
    frame.pc--;
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    _installBytecodeContinuation(
      coroutine,
      LuaBytecodeCloseSuspension(
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
    LuaBytecodeFrame frame,
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
      LuaBytecodeCloseSuspension(
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
    LuaBytecodeFrame frame,
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
      LuaBytecodeReturnSuspension(
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

  Future<void> _closeDiscardedCallResults(
    LuaBytecodeFrame frame,
    List<Value> results,
  ) async {
    Object? closeError;
    StackTrace? closeStackTrace;

    for (var index = results.length - 1; index >= 0; index--) {
      final value = results[index];
      final rawValue = rawLuaSlot(value);
      if (_debugFileOps) {
        debugFileLog(
          'discard-result index=$index tbc=${value.isToBeClose} '
          'raw=${rawValue.runtimeType} live=${frame.toBeClosedRegisters}',
        );
      }
      if (frame.isLiveToBeClosedAlias(value)) {
        if (_debugFileOps) {
          debugFileLog('discard-result skip-live-alias index=$index');
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
    LuaBytecodeFrame frame,
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
          : runtimeValue(runtime, null);
      frame.setRegister(register + index, value);
    }
    frame.top = register + expectedCount;
    return null;
  }

  int? _storeVarargResults(
    LuaBytecodeFrame frame,
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
          : runtimeValue(runtime, null);
      frame.setRegister(word.a + index, value);
    }
    frame.top = word.a + expectedCount;
    return null;
  }

  bool _forPrep(LuaBytecodeFrame frame, int base) {
    final initial = frame.register(base);
    final limit = frame.register(base + 1);
    final step = frame.register(base + 2);

    final coercedInitial = forNumericOperand(initial, 'initial value');
    final coercedLimit = forNumericOperand(limit, 'limit');
    final coercedStep = forNumericOperand(step, 'step');

    final integerInitial = exactForIntegerValue(coercedInitial);
    final integerStep = exactForIntegerValue(coercedStep);
    if (integerInitial != null && integerStep != null) {
      final init = integerInitial;
      final stepValue = integerStep;
      if (stepValue == 0) {
        throw LuaError("'for' step is zero");
      }
      final limitInfo = forIntegerLimit(init, coercedLimit, stepValue);
      if (limitInfo.skip) {
        return true;
      }
      final limitValue = limitInfo.limit;

      final count = stepValue > 0
          ? unsignedDifference64(
                  unsignedInt64(init: limitValue),
                  unsignedInt64(init: init),
                ) ~/
                unsignedInt64(init: stepValue)
          : unsignedDifference64(
                  unsignedInt64(init: init),
                  unsignedInt64(init: limitValue),
                ) ~/
                negativeStepDivisor(stepValue);
      frame.setRegister(
        base,
        framePrimitiveValue(runtime, signedInt64FromUnsigned(count)),
      );
      frame.setRegister(base + 1, framePrimitiveValue(runtime, stepValue));
      frame.setRegister(base + 2, framePrimitiveValue(runtime, init));
      return false;
    }

    final init = numericForOperand(coercedInitial).toDouble();
    final limitValue = numericForOperand(coercedLimit).toDouble();
    final stepValue = numericForOperand(coercedStep).toDouble();
    if (stepValue == 0) {
      throw LuaError("'for' step is zero");
    }
    final shouldSkip = stepValue > 0 ? limitValue < init : init < limitValue;
    if (shouldSkip) {
      return true;
    }

    frame.setRegister(base, runtimeValue(runtime, limitValue));
    frame.setRegister(base + 1, framePrimitiveValue(runtime, stepValue));
    frame.setRegister(base + 2, framePrimitiveValue(runtime, init));
    return false;
  }

  bool _forLoop(LuaBytecodeFrame frame, int base) {
    final countValue = frame.register(base);
    final stepValue = frame.register(base + 1);
    final indexValue = frame.register(base + 2);

    if (isInteger(stepValue)) {
      final rawCount = rawLuaSlot(countValue);
      final rawStep = rawLuaSlot(stepValue);
      final rawIndex = rawLuaSlot(indexValue);
      if (rawCount is int &&
          rawCount > 0 &&
          rawStep is int &&
          rawIndex is int) {
        frame.setRegister(base, framePrimitiveValue(runtime, rawCount - 1));
        frame.setRegister(
          base + 2,
          framePrimitiveValue(runtime, rawIndex + rawStep),
        );
        return true;
      }
      final count = unsignedForLoopCounter(countValue);
      if (count <= BigInt.zero) {
        return false;
      }
      final step = integerValue(stepValue);
      final nextIndex = NumberUtils.add(integerValue(indexValue), step);
      frame.setRegister(
        base,
        framePrimitiveValue(
          runtime,
          signedInt64FromUnsigned(count - BigInt.one),
        ),
      );
      frame.setRegister(base + 2, framePrimitiveValue(runtime, nextIndex));
      return true;
    }

    final step = numericValue(stepValue).toDouble();
    final limit = numericValue(countValue).toDouble();
    final nextIndex = numericValue(indexValue).toDouble() + step;
    final shouldContinue = step > 0 ? nextIndex <= limit : nextIndex >= limit;
    if (!shouldContinue) {
      return false;
    }
    frame.setRegister(base + 2, runtimeValue(runtime, nextIndex));
    return true;
  }

  Future<List<Value>> _genericForCall(
    LuaBytecodeFrame frame,
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
      (index) =>
          index < results.length ? results[index] : runtimeValue(runtime, null),
      growable: false,
    );
    return expected;
  }
}
