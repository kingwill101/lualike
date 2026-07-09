part of 'vm.dart';

Future<void>? _runGcLoopSafePoint(LuaRuntime runtime, LuaBytecodeFrame frame) {
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
  LuaBytecodeFrame frame,
  bool shouldRescue,
) async {
  await runtime.runLoopGcAtSafePoint(frame.loopGcCounter);
  if (runtime.gc.isStopped ||
      !runtime.gc.autoTriggerEnabled ||
      runtime.gc.allocationDebt > 0 ||
      !shouldRescue) {
    return;
  }
  await runtime.gc.performGenerationalStep(runtime.getRoots());
}
