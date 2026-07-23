part of 'vm.dart';

Future<void>? _runGcLoopSafePoint(LuaRuntime runtime, LuaBytecodeFrame frame) {
  frame.loopGcCounter += 1;
  final loopCounter = frame.loopGcCounter;
  final gc = runtime.gc;
  // Early-out: no GC work needed when stopped or auto-trigger disabled.
  if (gc.isStopped || !gc.autoTriggerEnabled) {
    return null;
  }
  // Inline the shouldRunLoopGcAtSafePoint check to avoid a function call.
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
  // Rescue: proactively run a short step so the collector doesn't stall.
  // Coarser cadence (16384): fine-grained rescue showed multi-percent
  // overhead on allocation-heavy bytecode workloads under profiling.
  if (debt <= 0 && loopCounter >= 16384 && loopCounter % 16384 == 0) {
    gc.performGenerationalStep(runtime.getRoots());
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
