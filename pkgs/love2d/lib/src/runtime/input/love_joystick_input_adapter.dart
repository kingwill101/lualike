library;

import 'dart:async';

import '../love_runtime.dart';
import '../love_script_runtime.dart';

/// Host-side joystick ingestion helper for LOVE runtime integrations.
///
/// Unlike [LoveFlameInputAdapter], this adapter is not tied to Flutter events.
/// Integrations can feed it device add/remove notifications plus joystick or
/// gamepad state changes from any platform backend.
class LoveJoystickInputAdapter {
  /// Creates a joystick and gamepad input adapter for a LOVE host.
  LoveJoystickInputAdapter({
    required LoveHost host,
    required LoveScriptRuntime? Function() runtimeProvider,
    this.onError,
  }) : _host = host,
       _runtimeProvider = runtimeProvider;

  final LoveHost _host;
  final LoveScriptRuntime? Function() _runtimeProvider;
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// The managed joystick registry exposed by the host.
  LoveJoystickManager get joysticks => _host.joysticks;

  /// Waits for all queued state transitions and callback dispatches to finish.
  ///
  /// Joystick queueing is synchronous, so this is a no-op retained for API
  /// compatibility with host frame loops that still call [flush].
  Future<void> flush() => Future<void>.value();

  void handleDeviceAdded(LoveJoystickDevice joystick) {
    _enqueue((runtime) {
      final managed = _trackAddedJoystick(joystick);
      if (managed == null || runtime == null) {
        return;
      }
      // queue* only pushes onto the event queue; ignore completed Future.
      runtime.queueJoystickAdded(managed);
    });
  }

  void handleDeviceRemoved(LoveJoystickDevice joystick) {
    _enqueue((runtime) {
      final managed = _managedJoystickById(joystick.id) ?? joystick;
      if (!managed.connected && _managedJoystickById(managed.id) == null) {
        return;
      }

      managed.connected = false;
      try {
        if (runtime != null) {
          runtime.queueJoystickRemoved(managed);
        }
      } finally {
        // Remove after dispatch so the callback can still query the object.
        joysticks.removeDevice(managed.id);
      }
    });
  }

  void handleJoystickButtonDown(LoveJoystickDevice joystick, int button) {
    if (button < 1) {
      return;
    }

    _enqueue((runtime) {
      final managed = _ensureTrackedJoystick(joystick);
      managed.setButtonDown(button, down: true);
      if (runtime == null) {
        return;
      }
      runtime.queueJoystickPressed(managed, button);
    });
  }

  void handleJoystickButtonUp(LoveJoystickDevice joystick, int button) {
    if (button < 1) {
      return;
    }

    _enqueue((runtime) {
      final managed = _ensureTrackedJoystick(joystick);
      managed.setButtonDown(button, down: false);
      if (runtime == null) {
        return;
      }
      runtime.queueJoystickReleased(managed, button);
    });
  }

  void handleJoystickAxisMotion(
    LoveJoystickDevice joystick,
    int axis,
    double value,
  ) {
    if (axis < 1) {
      return;
    }

    _enqueue((runtime) {
      final managed = _ensureTrackedJoystick(joystick);
      managed.setAxis(axis, value);
      if (runtime == null) {
        return;
      }
      runtime.queueJoystickAxis(managed, axis, value);
    });
  }

  void handleJoystickHatMotion(
    LoveJoystickDevice joystick,
    int hat,
    String value,
  ) {
    if (hat < 1 || !loveIsValidJoystickHat(value)) {
      return;
    }

    _enqueue((runtime) {
      final managed = _ensureTrackedJoystick(joystick);
      managed.setHat(hat, value);
      if (runtime == null) {
        return;
      }
      runtime.queueJoystickHat(managed, hat, value);
    });
  }

  void handleGamepadButtonDown(LoveJoystickDevice joystick, String button) {
    if (!loveIsValidGamepadButton(button)) {
      return;
    }

    _enqueue((runtime) {
      final managed = _ensureTrackedJoystick(joystick);
      managed.setGamepadButton(button, down: true);
      if (runtime == null) {
        return;
      }
      runtime.queueGamepadPressed(managed, button);
    });
  }

  void handleGamepadButtonUp(LoveJoystickDevice joystick, String button) {
    if (!loveIsValidGamepadButton(button)) {
      return;
    }

    _enqueue((runtime) {
      final managed = _ensureTrackedJoystick(joystick);
      managed.setGamepadButton(button, down: false);
      if (runtime == null) {
        return;
      }
      runtime.queueGamepadReleased(managed, button);
    });
  }

  void handleGamepadAxisMotion(
    LoveJoystickDevice joystick,
    String axis,
    double value,
  ) {
    if (!loveIsValidGamepadAxis(axis)) {
      return;
    }

    _enqueue((runtime) {
      final managed = _ensureTrackedJoystick(joystick);
      managed.setGamepadAxis(axis, value);
      if (runtime == null) {
        return;
      }
      runtime.queueGamepadAxis(managed, axis, value);
    });
  }

  /// Applies a silent joystick state reset without dispatching LOVE callbacks.
  ///
  /// This is useful for host integrations that need to clear synthesized input
  /// state, such as when app visibility changes mid-gesture.
  void resetJoystickState(
    LoveJoystickDevice joystick, {
    Iterable<int> buttons = const <int>[],
  }) {
    final buttonsToClear = buttons
        .where((button) => button >= 1)
        .toSet()
        .toList(growable: false);
    if (buttonsToClear.isEmpty) {
      return;
    }

    _enqueue((_) {
      final managed = _ensureTrackedJoystick(joystick);
      for (final button in buttonsToClear) {
        managed.setButtonDown(button, down: false);
      }
    });
  }

  /// Applies a silent gamepad state reset without dispatching LOVE callbacks.
  ///
  /// This is useful for host integrations that need to clear synthesized input
  /// state, such as when app visibility changes mid-gesture.
  void resetGamepadState(
    LoveJoystickDevice joystick, {
    Iterable<String> buttons = const <String>[],
    Iterable<String> axes = const <String>[],
  }) {
    final buttonsToClear = buttons
        .where(loveIsValidGamepadButton)
        .toSet()
        .toList(growable: false);
    final axesToClear = axes
        .where(loveIsValidGamepadAxis)
        .toSet()
        .toList(growable: false);
    if (buttonsToClear.isEmpty && axesToClear.isEmpty) {
      return;
    }

    _enqueue((_) {
      final managed = _ensureTrackedJoystick(joystick);
      for (final button in buttonsToClear) {
        managed.setGamepadButton(button, down: false);
      }
      for (final axis in axesToClear) {
        managed.setGamepadAxis(axis, 0.0);
      }
    });
  }

  LoveJoystickDevice? _trackAddedJoystick(LoveJoystickDevice joystick) {
    final existing = _managedJoystickById(joystick.id);
    if (identical(existing, joystick) && joystick.connected) {
      return null;
    }

    if (existing != null && !identical(existing, joystick)) {
      joysticks.removeDevice(existing.id);
    }

    final resolved = identical(existing, joystick) ? existing! : joystick;
    if (!_isTracked(resolved)) {
      joysticks.addDevice(resolved);
    }
    resolved.connected = true;
    return resolved;
  }

  LoveJoystickDevice _ensureTrackedJoystick(LoveJoystickDevice joystick) {
    final existing = _managedJoystickById(joystick.id);
    if (existing != null && !identical(existing, joystick)) {
      joysticks.removeDevice(existing.id);
    }

    if (!_isTracked(joystick)) {
      joysticks.addDevice(joystick);
    }
    joystick.connected = true;
    return joystick;
  }

  LoveJoystickDevice? _managedJoystickById(int id) {
    for (final device in joysticks.devices) {
      if (device.id == id) {
        return device;
      }
    }
    return null;
  }

  bool _isTracked(LoveJoystickDevice joystick) {
    for (final device in joysticks.devices) {
      if (identical(device, joystick)) {
        return true;
      }
    }
    return false;
  }

  /// Runs [action] immediately for synchronous joystick queueing.
  ///
  /// Joystick `queue*` helpers only push onto the LOVE event queue. Running
  /// them through a Future chain forced every axis/button event onto the
  /// microtask queue and made [flush] wait for that artificial latency.
  void _enqueue(void Function(LoveScriptRuntime? runtime) action) {
    try {
      action(_runtimeProvider());
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }
}
