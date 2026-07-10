part of 'vm.dart';

Future<void>? _runGcLoopSafePoint(LuaRuntime runtime, LuaBytecodeFrame frame) {
  frame.loopGcCounter += 1;
  final loopCounter = frame.loopGcCounter;
  final gc = runtime.gc;
  // Fast early-out checks inlined from shouldRunLoopGcAtSafePoint
  // to avoid function call overhead on the hot backedge path.
  if (gc.isStopped || !gc.autoTriggerEnabled) {
    return null;
  }
  // Periodically rescue idle GC even when below threshold.
  if (gc.allocationDebt <= 0 &&
      loopCounter >= 8192 &&
      loopCounter % 8192 == 0) {
    gc.performGenerationalStep(runtime.getRoots());
  }
  // Now check whether GC actually needs to run.
  if (gc.isManualCollectRunning || gc.isFinalizerActive) {
    return null;
  }
  if (gc.needsAsyncFinalizerDrain) {
    return _runGcLoopSafePointSlow(runtime, frame);
  }
  final threshold = gc.autoTriggerDebtThreshold;
  final debt = gc.allocationDebt;
  if (debt >= threshold) {
    return _runGcLoopSafePointSlow(runtime, frame);
  }
  if (gc.shouldForceAsyncLoopRescue(loopCounter, debt, threshold) ||
      gc.shouldAdvanceIncrementalLoopCycle(loopCounter)) {
    return _runGcLoopSafePointSlow(runtime, frame);
  }
  return null;
}

Future<void> _runGcLoopSafePointSlow(
  LuaRuntime runtime,
  LuaBytecodeFrame frame,
) async {
  await runtime.runLoopGcAtSafePoint(frame.loopGcCounter);
}
