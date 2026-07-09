part of 'vm.dart';

final class LuaBytecodeCallSuspension implements CoroutineContinuation {
  const LuaBytecodeCallSuspension({
    required this.vm,
    required this.frame,
    required this.register,
    required this.resultSpec,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final LuaBytecodeFrame frame;
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
            LuaBytecodeCallSuspension(
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
        return packCallResults(vm.runtime, resumedResults);
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
        'result=${debugResultPayload(result)}',
      );
      return vm._normalizeResults(result);
    }
    return args
        .map((arg) => runtimeValue(vm.runtime, arg))
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

final class LuaBytecodeConditionalJumpSuspension
    implements CoroutineContinuation {
  const LuaBytecodeConditionalJumpSuspension({
    required this.vm,
    required this.frame,
    required this.word,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final LuaBytecodeFrame frame;
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
            LuaBytecodeConditionalJumpSuspension(
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
        return packCallResults(vm.runtime, resumedResults);
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
      return firstResultValue(vm.runtime, result);
    }
    return args.isEmpty
        ? runtimeValue(vm.runtime, null)
        : runtimeValue(vm.runtime, args.first);
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

final class LuaBytecodeConcatSuspension implements CoroutineContinuation {
  const LuaBytecodeConcatSuspension({
    required this.vm,
    required this.frame,
    required this.startRegister,
    required this.nextOffset,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final LuaBytecodeFrame frame;
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
              LuaBytecodeConcatSuspension(
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
          return packCallResults(vm.runtime, resumedResults);
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
      return firstResultValue(vm.runtime, result);
    }
    return args.isEmpty
        ? runtimeValue(vm.runtime, null)
        : runtimeValue(vm.runtime, args.first);
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

final class LuaBytecodeStoreRegisterSuspension
    implements CoroutineContinuation {
  const LuaBytecodeStoreRegisterSuspension({
    required this.vm,
    required this.frame,
    required this.register,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final LuaBytecodeFrame frame;
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
              LuaBytecodeStoreRegisterSuspension(
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
          return packCallResults(vm.runtime, resumedResults);
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
      return firstResultValue(vm.runtime, result);
    }
    return args.isEmpty
        ? runtimeValue(vm.runtime, null)
        : runtimeValue(vm.runtime, args.first);
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

final class LuaBytecodeResumeOnlySuspension implements CoroutineContinuation {
  const LuaBytecodeResumeOnlySuspension({
    required this.vm,
    required this.frame,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final LuaBytecodeFrame frame;
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
              LuaBytecodeResumeOnlySuspension(
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
          return packCallResults(vm.runtime, resumedResults);
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
