part of '../love_script_runtime.dart';

/// Joystick and gamepad callback helpers for [LoveScriptRuntime].
extension LoveScriptRuntimeJoystickCallbacks on LoveScriptRuntime {
  /// Calls `love.joystickpressed` when it is defined.
  Future<Object?> callJoystickPressedIfDefined(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return callLoveCallbackIfDefined(
      'joystickpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Calls `love.joystickreleased` when it is defined.
  Future<Object?> callJoystickReleasedIfDefined(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return callLoveCallbackIfDefined(
      'joystickreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Calls `love.joystickaxis` when it is defined.
  Future<Object?> callJoystickAxisIfDefined(
    LoveJoystickDevice joystick,
    int axis,
    double value,
  ) {
    return callLoveCallbackIfDefined(
      'joystickaxis',
      _joystickCallbackArgs(joystick, <Object?>[axis, value]),
    );
  }

  /// Calls `love.joystickhat` when it is defined.
  Future<Object?> callJoystickHatIfDefined(
    LoveJoystickDevice joystick,
    int hat,
    String value,
  ) {
    return callLoveCallbackIfDefined(
      'joystickhat',
      _joystickCallbackArgs(joystick, <Object?>[hat, value]),
    );
  }

  /// Calls `love.gamepadpressed` when it is defined.
  Future<Object?> callGamepadPressedIfDefined(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return callLoveCallbackIfDefined(
      'gamepadpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Calls `love.gamepadreleased` when it is defined.
  Future<Object?> callGamepadReleasedIfDefined(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return callLoveCallbackIfDefined(
      'gamepadreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Calls `love.gamepadaxis` when it is defined.
  Future<Object?> callGamepadAxisIfDefined(
    LoveJoystickDevice joystick,
    String axis,
    double value,
  ) {
    return callLoveCallbackIfDefined(
      'gamepadaxis',
      _joystickCallbackArgs(joystick, <Object?>[axis, value]),
    );
  }

  /// Calls `love.joystickadded` when it is defined.
  Future<Object?> callJoystickAddedIfDefined(LoveJoystickDevice joystick) {
    return callLoveCallbackIfDefined(
      'joystickadded',
      _joystickCallbackArgs(joystick),
    );
  }

  /// Calls `love.joystickremoved` when it is defined.
  Future<Object?> callJoystickRemovedIfDefined(LoveJoystickDevice joystick) {
    return callLoveCallbackIfDefined(
      'joystickremoved',
      _joystickCallbackArgs(joystick),
    );
  }

  /// Dispatches `joystickpressed` to the event queue and callback hook.
  Future<Object?> dispatchJoystickPressed(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Queues a `joystickpressed` event without calling the callback immediately.
  Future<Object?> queueJoystickPressed(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return _queueLoveEvent(
      'joystickpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Dispatches `joystickreleased` to the event queue and callback hook.
  Future<Object?> dispatchJoystickReleased(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Queues a `joystickreleased` event without calling the callback immediately.
  Future<Object?> queueJoystickReleased(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return _queueLoveEvent(
      'joystickreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Dispatches `joystickaxis` to the event queue and callback hook.
  Future<Object?> dispatchJoystickAxis(
    LoveJoystickDevice joystick,
    int axis,
    double value,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickaxis',
      _joystickCallbackArgs(joystick, <Object?>[axis, value]),
    );
  }

  /// Queues a `joystickaxis` event without calling the callback immediately.
  Future<Object?> queueJoystickAxis(
    LoveJoystickDevice joystick,
    int axis,
    double value,
  ) {
    return _queueLoveEvent(
      'joystickaxis',
      _joystickCallbackArgs(joystick, <Object?>[axis, value]),
    );
  }

  /// Dispatches `joystickhat` to the event queue and callback hook.
  Future<Object?> dispatchJoystickHat(
    LoveJoystickDevice joystick,
    int hat,
    String value,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickhat',
      _joystickCallbackArgs(joystick, <Object?>[hat, value]),
    );
  }

  /// Queues a `joystickhat` event without calling the callback immediately.
  Future<Object?> queueJoystickHat(
    LoveJoystickDevice joystick,
    int hat,
    String value,
  ) {
    return _queueLoveEvent(
      'joystickhat',
      _joystickCallbackArgs(joystick, <Object?>[hat, value]),
    );
  }

  /// Dispatches `gamepadpressed` to the event queue and callback hook.
  Future<Object?> dispatchGamepadPressed(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'gamepadpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Queues a `gamepadpressed` event without calling the callback immediately.
  Future<Object?> queueGamepadPressed(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return _queueLoveEvent(
      'gamepadpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Dispatches `gamepadreleased` to the event queue and callback hook.
  Future<Object?> dispatchGamepadReleased(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'gamepadreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Queues a `gamepadreleased` event without calling the callback immediately.
  Future<Object?> queueGamepadReleased(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return _queueLoveEvent(
      'gamepadreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  /// Dispatches `gamepadaxis` to the event queue and callback hook.
  Future<Object?> dispatchGamepadAxis(
    LoveJoystickDevice joystick,
    String axis,
    double value,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'gamepadaxis',
      _joystickCallbackArgs(joystick, <Object?>[axis, value]),
    );
  }

  /// Queues a `gamepadaxis` event without calling the callback immediately.
  Future<Object?> queueGamepadAxis(
    LoveJoystickDevice joystick,
    String axis,
    double value,
  ) {
    return _queueLoveEvent(
      'gamepadaxis',
      _joystickCallbackArgs(joystick, <Object?>[axis, value]),
    );
  }

  /// Dispatches `joystickadded` to the event queue and callback hook.
  Future<Object?> dispatchJoystickAdded(LoveJoystickDevice joystick) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickadded',
      _joystickCallbackArgs(joystick),
    );
  }

  /// Queues a `joystickadded` event without calling the callback immediately.
  Future<Object?> queueJoystickAdded(LoveJoystickDevice joystick) {
    return _queueLoveEvent('joystickadded', _joystickCallbackArgs(joystick));
  }

  /// Dispatches `joystickremoved` to the event queue and callback hook.
  Future<Object?> dispatchJoystickRemoved(LoveJoystickDevice joystick) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickremoved',
      _joystickCallbackArgs(joystick),
    );
  }

  /// Queues a `joystickremoved` event without calling the callback immediately.
  Future<Object?> queueJoystickRemoved(LoveJoystickDevice joystick) {
    return _queueLoveEvent('joystickremoved', _joystickCallbackArgs(joystick));
  }

  /// Returns the callback argument list for joystick and gamepad events.
  List<Object?> _joystickCallbackArgs(
    LoveJoystickDevice joystick, [
    List<Object?> tail = const <Object?>[],
  ]) {
    final wrapped = wrapLoveJoystickForRuntime(runtime, joystick);
    return <Object?>[wrapped, ...tail];
  }
}
