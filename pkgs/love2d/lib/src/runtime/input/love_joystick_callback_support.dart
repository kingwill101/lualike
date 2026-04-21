part of '../love_script_runtime.dart';

extension LoveScriptRuntimeJoystickCallbacks on LoveScriptRuntime {
  Future<Object?> callJoystickPressedIfDefined(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return callLoveCallbackIfDefined(
      'joystickpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  Future<Object?> callJoystickReleasedIfDefined(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return callLoveCallbackIfDefined(
      'joystickreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

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

  Future<Object?> callGamepadPressedIfDefined(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return callLoveCallbackIfDefined(
      'gamepadpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  Future<Object?> callGamepadReleasedIfDefined(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return callLoveCallbackIfDefined(
      'gamepadreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

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

  Future<Object?> callJoystickAddedIfDefined(LoveJoystickDevice joystick) {
    return callLoveCallbackIfDefined(
      'joystickadded',
      _joystickCallbackArgs(joystick),
    );
  }

  Future<Object?> callJoystickRemovedIfDefined(LoveJoystickDevice joystick) {
    return callLoveCallbackIfDefined(
      'joystickremoved',
      _joystickCallbackArgs(joystick),
    );
  }

  Future<Object?> dispatchJoystickPressed(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  Future<Object?> dispatchJoystickReleased(
    LoveJoystickDevice joystick,
    int button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

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

  Future<Object?> dispatchGamepadPressed(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'gamepadpressed',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

  Future<Object?> dispatchGamepadReleased(
    LoveJoystickDevice joystick,
    String button,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'gamepadreleased',
      _joystickCallbackArgs(joystick, <Object?>[button]),
    );
  }

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

  Future<Object?> dispatchJoystickAdded(LoveJoystickDevice joystick) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickadded',
      _joystickCallbackArgs(joystick),
    );
  }

  Future<Object?> dispatchJoystickRemoved(LoveJoystickDevice joystick) {
    return _dispatchLoveEventAndCallbackIfDefined(
      'joystickremoved',
      _joystickCallbackArgs(joystick),
    );
  }

  List<Object?> _joystickCallbackArgs(
    LoveJoystickDevice joystick, [
    List<Object?> tail = const <Object?>[],
  ]) {
    final wrapped = wrapLoveJoystickForRuntime(runtime, joystick);
    return <Object?>[wrapped, ...tail];
  }
}
