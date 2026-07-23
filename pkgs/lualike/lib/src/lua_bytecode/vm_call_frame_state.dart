import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';

final Expando<bool> closeSignalYieldableStates = Expando<bool>();

/// Returns the bytecode frame bound to [callFrame], or null.
///
/// The engine frame is stored directly on [CallFrame.engineFrameState] so
/// no Expando lookup is needed — this avoids an identity-hash-map probe on
/// every bytecode-to-bytecode call return path.
@pragma('vm:prefer-inline')
dynamic bytecodeFrameForCallFrame(CallFrame? callFrame) {
  if (callFrame == null) return null;
  return callFrame.engineFrameState;
}

/// Binds [frame] to [callFrame] for the duration of the call.
@pragma('vm:prefer-inline')
void bindBytecodeCallFrame(CallFrame callFrame, dynamic frame) {
  callFrame.engineFrameState = frame;
}

/// Clears the bytecode frame binding for [callFrame].
@pragma('vm:prefer-inline')
void clearBytecodeCallFrame(CallFrame callFrame) {
  callFrame.engineFrameState = null;
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
