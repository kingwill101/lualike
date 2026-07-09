import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';

final Expando<Object> _callFrameBytecodeFrames = Expando<Object>();
final Expando<bool> closeSignalYieldableStates = Expando<bool>();

dynamic bytecodeFrameForCallFrame(CallFrame? callFrame) {
  if (callFrame == null) {
    return null;
  }
  final mapped = _callFrameBytecodeFrames[callFrame];
  if (mapped != null) {
    return mapped;
  }
  return callFrame.engineFrameState;
}

void bindBytecodeCallFrame(CallFrame callFrame, dynamic frame) {
  _callFrameBytecodeFrames[callFrame] = frame;
  callFrame.engineFrameState = frame;
}

void clearBytecodeCallFrame(CallFrame callFrame) {
  _callFrameBytecodeFrames[callFrame] = null;
  if (callFrame.engineFrameState != null) {
    callFrame.engineFrameState = null;
  }
}

void rememberCloseSignalYieldable(
  CoroutineCloseSignal signal,
  bool isYieldable,
) {
  final previous = closeSignalYieldableStates[signal];
  closeSignalYieldableStates[signal] = switch (previous) {
    null => isYieldable,
    final bool prior => prior && isYieldable,
  };
}
