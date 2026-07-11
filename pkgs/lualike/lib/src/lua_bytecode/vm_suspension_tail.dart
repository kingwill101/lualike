part of 'vm.dart';

final class LuaBytecodeProtectedCallSuspension
    implements CoroutineContinuation {
  const LuaBytecodeProtectedCallSuspension({required this.vm, this.child});

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
            LuaBytecodeProtectedCallSuspension(vm: vm, child: nextChild),
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

final class LuaBytecodeCloseSuspension implements CoroutineContinuation {
  const LuaBytecodeCloseSuspension({
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
  final LuaBytecodeFrame frame;
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
          return packCallResults(vm.runtime, resumedResults);
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
            LuaBytecodeCloseSuspension(
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

final class LuaBytecodeFrameSuspension implements CoroutineContinuation {
  LuaBytecodeFrameSuspension({
    required this.vm,
    required this.frame,
    required this.resumeInProtectedCall,
    this.child,
    this.compactState,
  });

  final LuaBytecodeVm vm;
  LuaBytecodeFrame frame;
  final bool resumeInProtectedCall;
  final CoroutineContinuation? child;
  final _CompactFrameState? compactState;

  /// Restore compacted frame before resuming.
  void _ensureFrame() {
    final cs = compactState;
    if (cs == null || !frame.closed) return;
    // Create fresh frame (registers initialized to nil)
    final newFrame = LuaBytecodeFrame(
      runtime: vm.runtime,
      closure: cs.closure,
      arguments: const <Object?>[],
      isEntryFrame: cs.isEntryFrame,
      isTailCall: cs.isTailCall,
      callName: cs.callName,
    );
    // Restore PC, top, and register values
    newFrame.pc = cs.pc;
    newFrame.top = cs.top;
    for (var i = 0; i < cs.registers.length && i < newFrame.registers.length; i++) {
      newFrame.registers[i] = cs.registers[i];
    }
    frame = newFrame;
  }

  @override
  Future<Object?> resume(List<Object?> args) {
    return _withProtectedCallResume(vm.runtime, resumeInProtectedCall, () async {
      // Restore from compact state if the frame was released to the pool
      if (compactState != null) _ensureFrame();
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
                  (nested is LuaBytecodeCallSuspension &&
                      nestedChild is LuaBytecodeCallSuspension)
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
              clearBytecodeCallFrame(suspendedCallerFrame);
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

final class LuaBytecodeReturnSuspension implements CoroutineContinuation {
  const LuaBytecodeReturnSuspension({
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
  final LuaBytecodeFrame frame;
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
        return packCallResults(vm.runtime, resumedResults);
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
            LuaBytecodeReturnSuspension(
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
  LuaBytecodeFrame currentFrame,
) {
  if (!currentFrame.closed) {
    return false;
  }
  if (continuation case LuaBytecodeFrameSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  if (continuation case LuaBytecodeReturnSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  if (continuation case LuaBytecodeTailCallSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  return false;
}

final class LuaBytecodeTailCallSuspension implements CoroutineContinuation {
  const LuaBytecodeTailCallSuspension({
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
        vm._releaseBytecodeFrameIfReusable(frame);
        return packCallResults(vm.runtime, results);
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
            LuaBytecodeTailCallSuspension(
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

final class LuaBytecodeTForCallSuspension implements CoroutineContinuation {
  const LuaBytecodeTForCallSuspension({
    required this.vm,
    required this.frame,
    required this.base,
    required this.resultCount,
    required this.resumeInProtectedCall,
    this.child,
  });

  final LuaBytecodeVm vm;
  final LuaBytecodeFrame frame;
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
              LuaBytecodeTForCallSuspension(
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

  Future<List<Value>> _resumeResults(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return _padResults(vm._normalizeResults(result));
    }
    final resumed = args
        .map((arg) => runtimeValue(vm.runtime, arg))
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
          : runtimeValue(vm.runtime, null),
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
