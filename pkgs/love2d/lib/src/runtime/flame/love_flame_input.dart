library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../input/love_joystick_input_adapter.dart';
import '../love_runtime.dart';
import '../love_script_runtime.dart';
import 'love_flame_viewport_geometry.dart';
import 'love_flame_text_input_state.dart';

part 'love_flame_gamepad_bridge.dart';
part 'love_flame_key_mapping.dart';

/// Whether verbose touch-trace logging is enabled for debugging input leaks.
const bool _loveTraceTouchLeak = bool.fromEnvironment(
  'LOVE2D_TRACE_TOUCH_LEAK',
  defaultValue: true,
);

/// Emits a debug trace line for touch input processing when enabled.
void _loveTraceTouchInput(
  String stage, {
  Map<String, Object?> details = const {},
}) {
  if (!_loveTraceTouchLeak) {
    return;
  }

  final message = details.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');
  if (message.isEmpty) {
    // print('[love2d-touch] $stage');
    return;
  }
  // print('[love2d-touch] $stage $message');
}

/// Adapts Flutter keyboard, mouse, touch, and synthesized gamepad events to
/// LOVE runtime callbacks.
class LoveFlameInputAdapter {
  /// Creates an input adapter for a Flame-backed LOVE host.
  LoveFlameInputAdapter({
    required LoveHost host,
    required LoveScriptRuntime? Function() runtimeProvider,
    Size? Function()? viewportSizeProvider,
    CameraComponent? Function()? cameraProvider,
    LoveJoystickInputAdapter? joystickInput,
    this.onError,
    this.consumeKeyboardEvents = true,
  }) : _host = host,
       _runtimeProvider = runtimeProvider,
       _viewportSizeProvider = viewportSizeProvider,
       _cameraProvider = cameraProvider,
       _joystickInput =
           joystickInput ??
           LoveJoystickInputAdapter(
             host: host,
             runtimeProvider: runtimeProvider,
             onError: onError,
           );

  /// The LOVE host whose input state is being updated.
  final LoveHost _host;

  /// Resolves the active script runtime that should receive queued callbacks.
  final LoveScriptRuntime? Function() _runtimeProvider;

  /// Supplies the current rendered viewport size for coordinate conversion.
  final Size? Function()? _viewportSizeProvider;

  /// Supplies Flame's fixed-resolution camera for presentation conversion.
  final CameraComponent? Function()? _cameraProvider;

  /// The joystick adapter used for physical and synthesized gamepad input.
  final LoveJoystickInputAdapter _joystickInput;

  /// The callback used to report uncaught input dispatch errors.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Whether handled keyboard events should be consumed from Flutter.
  final bool consumeKeyboardEvents;

  /// The active mouse button tracked for each Flutter pointer identifier.
  final Map<int, int> _pointerButtons = <int, int>{};

  /// The synthesized joystick buttons currently held down.
  final Set<int> _virtualJoystickButtonsDown = <int>{};

  /// The synthesized gamepad buttons currently held down.
  final Set<String> _virtualGamepadButtonsDown = <String>{};

  /// The synthesized gamepad axes currently reported to LOVE.
  final Map<String, double> _virtualGamepadAxes = <String, double>{};

  /// The text input state mirrored from the active Flutter text connection.
  late final LoveFlameTextInputState _textInputState = LoveFlameTextInputState(
    keyboard: keyboard,
    dispatch: _dispatch,
  );

  /// The tail future for queued asynchronous runtime dispatch work.
  Future<void> _dispatchQueue = Future<void>.value();

  /// Whether the LOVE viewport currently has keyboard focus.
  bool _focused = false;

  /// Whether the LOVE viewport currently has mouse hover focus.
  bool _mouseFocused = false;

  /// Whether the synthesized virtual gamepad is currently registered.
  bool _virtualGamepadTracked = false;

  /// The synthesized joystick device used for virtual gamepad input.
  late final LoveJoystickDevice _virtualGamepad = LoveJoystickDevice(
    id: _loveFlameVirtualGamepadId,
    name: _loveFlameVirtualGamepadName,
    connected: false,
    gamepad: true,
    guid: _loveFlameVirtualGamepadGuid,
  );

  /// The LOVE keyboard state owned by the host.
  LoveKeyboardState get keyboard => _host.keyboard;

  /// The LOVE mouse state owned by the host.
  LoveMouseState get mouse => _host.mouse;

  /// The LOVE touch state owned by the host.
  LoveTouchState get touch => _host.touch;

  /// The active platform text editing value tracked for LOVE text input.
  TextEditingValue get currentTextEditingValue => _textInputState.editingValue;

  /// Waits for all queued input dispatches to finish.
  Future<void> flush() async {
    await _dispatchQueue;
    await _joystickInput.flush();
  }

  /// Starts a platform text input session for LOVE text entry.
  void beginPlatformTextInputSession() {
    _textInputState.beginPlatformSession();
  }

  /// Ends the active platform text input session.
  void endPlatformTextInputSession() {
    _textInputState.endPlatformSession();
  }

  /// Applies a platform text editing update.
  void handleTextEditingValue(TextEditingValue value) {
    _textInputState.handleEditingValue(value);
  }

  /// Handles a Flutter keyboard event and forwards it to LOVE.
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (_loveIsGamepadLikeDeviceType(event.deviceType)) {
      return _handleGamepadKeyEvent(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    final scancode = loveScancodeFromFlutterPhysicalKey(event.physicalKey);
    final key = loveKeyFromFlutterKeyEvent(event, scancode: scancode);

    switch (event) {
      case KeyDownEvent():
        keyboard.setKeyDown(key, scancode: scancode, down: true);
        _dispatch(
          (runtime) =>
              runtime.queueKeyPressed(key, scancode: scancode, isRepeat: false),
        );
        _dispatchTextInput(event);
      case KeyRepeatEvent():
        keyboard.setKeyDown(key, scancode: scancode, down: true);
        if (keyboard.keyRepeat) {
          _dispatch(
            (runtime) => runtime.queueKeyPressed(
              key,
              scancode: scancode,
              isRepeat: true,
            ),
          );
        }
        _dispatchTextInput(event);
      case KeyUpEvent():
        keyboard.setKeyDown(key, scancode: scancode, down: false);
        _dispatch(
          (runtime) => runtime.queueKeyReleased(key, scancode: scancode),
        );
    }

    return consumeKeyboardEvents
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// Updates LOVE focus state when the viewport focus changes.
  void handleFocusChanged(bool focused) {
    _setFocusState(focused);
  }

  /// Handles a pointer entering the LOVE viewport.
  void handlePointerEnter(PointerEnterEvent event) {
    _updateMousePosition(event.localPosition);
    _setMouseFocusState(true);
  }

  /// Handles a pointer leaving the LOVE viewport.
  void handlePointerExit(PointerExitEvent event) {
    _updateMousePosition(event.localPosition);
    _setMouseFocusState(false);
  }

  /// Resets transient input state when app visibility changes.
  void handleVisibilityChanged(bool visible) {
    if (visible) {
      return;
    }

    _textInputState.clear();
    _setMouseFocusState(false);
    _setFocusState(false);
    for (final scancode in keyboard.pressedScancodes.toList(growable: false)) {
      keyboard.setScancodeDown(scancode, down: false);
    }
    for (final button in mouse.buttonsDown.toList(growable: false)) {
      mouse.setButtonDown(button, down: false);
    }
    _resetVirtualGamepadState();
    _pointerButtons.clear();
    touch.clear();
  }

  /// Handles pointer hover updates and forwards mouse-motion callbacks.
  void handlePointerHover(PointerHoverEvent event) {
    _updateMousePosition(event.localPosition);
    final logicalDelta = _logicalDelta(event.localDelta);
    final x = mouse.x;
    final y = mouse.y;
    final dx = logicalDelta.dx;
    final dy = logicalDelta.dy;
    final isTouch = _isTouch(event);
    _dispatch(
      (runtime) => runtime.queueMouseMoved(x, y, dx, dy, isTouch: isTouch),
    );
  }

  /// Handles pointer movement and forwards touch and mouse-motion callbacks.
  void handlePointerMove(PointerMoveEvent event) {
    final logicalPosition = _logicalPoint(event.localPosition);
    final logicalDelta = _logicalDelta(event.localDelta);
    _updateMousePosition(event.localPosition);
    final isTouch = _isTouch(event);
    if (isTouch) {
      _loveTraceTouchInput(
        'pointer.move',
        details: <String, Object?>{
          'pointer': event.pointer,
          'x': logicalPosition.dx,
          'y': logicalPosition.dy,
          'dx': logicalDelta.dx,
          'dy': logicalDelta.dy,
          'activeTouchesBefore': touch.getTouches(),
        },
      );
      final x = logicalPosition.dx;
      final y = logicalPosition.dy;
      final dx = logicalDelta.dx;
      final dy = logicalDelta.dy;
      touch.moveTouch(
        id: event.pointer,
        x: x,
        y: y,
        dx: dx,
        dy: dy,
        pressure: event.pressure,
      );
      _dispatch(
        (runtime) => runtime.queueTouchMoved(
          event.pointer,
          x,
          y,
          dx,
          dy,
          event.pressure,
        ),
      );
      _loveTraceTouchInput(
        'pointer.move.applied',
        details: <String, Object?>{
          'pointer': event.pointer,
          'activeTouchesAfter': touch.getTouches(),
        },
      );
    }

    final x = mouse.x;
    final y = mouse.y;
    final dx = logicalDelta.dx;
    final dy = logicalDelta.dy;
    _dispatch(
      (runtime) => runtime.queueMouseMoved(x, y, dx, dy, isTouch: isTouch),
    );
  }

  /// Handles pointer press events and forwards touch or mouse press callbacks.
  void handlePointerDown(PointerDownEvent event) {
    final logicalPosition = _logicalPoint(event.localPosition);
    _updateMousePosition(event.localPosition);
    final isTouch = _isTouch(event);
    if (isTouch) {
      _loveTraceTouchInput(
        'pointer.down',
        details: <String, Object?>{
          'pointer': event.pointer,
          'x': logicalPosition.dx,
          'y': logicalPosition.dy,
          'pressure': event.pressure,
          'activeTouchesBefore': touch.getTouches(),
        },
      );
      final x = logicalPosition.dx;
      final y = logicalPosition.dy;
      touch.beginTouch(id: event.pointer, x: x, y: y, pressure: event.pressure);
      _dispatch(
        (runtime) => runtime.queueTouchPressed(
          event.pointer,
          x,
          y,
          0.0,
          0.0,
          event.pressure,
        ),
      );
      _loveTraceTouchInput(
        'pointer.down.applied',
        details: <String, Object?>{
          'pointer': event.pointer,
          'activeTouchesAfter': touch.getTouches(),
        },
      );
    }

    final button = _loveMouseButtonFromButtons(event.buttons);
    if (button == null) {
      return;
    }

    _pointerButtons[event.pointer] = button;
    mouse.setButtonDown(button, down: true);
    final x = mouse.x;
    final y = mouse.y;
    _dispatch(
      (runtime) => runtime.queueMousePressed(x, y, button, isTouch: isTouch),
    );
  }

  /// Handles pointer release events and forwards touch or mouse release callbacks.
  void handlePointerUp(PointerUpEvent event) {
    final logicalPosition = _logicalPoint(event.localPosition);
    final logicalDelta = _logicalDelta(event.localDelta);
    _updateMousePosition(event.localPosition);
    final isTouch = _isTouch(event);
    if (isTouch) {
      _loveTraceTouchInput(
        'pointer.up',
        details: <String, Object?>{
          'pointer': event.pointer,
          'x': logicalPosition.dx,
          'y': logicalPosition.dy,
          'dx': logicalDelta.dx,
          'dy': logicalDelta.dy,
          'pressure': event.pressure,
          'activeTouchesBefore': touch.getTouches(),
        },
      );
      final x = logicalPosition.dx;
      final y = logicalPosition.dy;
      touch.endTouch(event.pointer);
      _dispatch(
        (runtime) => runtime.queueTouchReleased(
          event.pointer,
          x,
          y,
          logicalDelta.dx,
          logicalDelta.dy,
          event.pressure,
        ),
      );
      _loveTraceTouchInput(
        'pointer.up.applied',
        details: <String, Object?>{
          'pointer': event.pointer,
          'activeTouchesAfter': touch.getTouches(),
        },
      );
    }

    final button =
        _pointerButtons.remove(event.pointer) ??
        _loveMouseButtonFromButtons(event.buttons);
    if (button == null) {
      return;
    }

    mouse.setButtonDown(button, down: false);
    final x = mouse.x;
    final y = mouse.y;
    _dispatch(
      (runtime) => runtime.queueMouseReleased(x, y, button, isTouch: isTouch),
    );
  }

  /// Handles pointer cancellation by clearing tracked touch and mouse state.
  void handlePointerCancel(PointerCancelEvent event) {
    if (_isTouch(event)) {
      _loveTraceTouchInput(
        'pointer.cancel',
        details: <String, Object?>{
          'pointer': event.pointer,
          'activeTouchesBefore': touch.getTouches(),
        },
      );
      touch.endTouch(event.pointer);
      _loveTraceTouchInput(
        'pointer.cancel.applied',
        details: <String, Object?>{
          'pointer': event.pointer,
          'activeTouchesAfter': touch.getTouches(),
        },
      );
    }

    final button = _pointerButtons.remove(event.pointer);
    if (button != null) {
      mouse.setButtonDown(button, down: false);
    }
  }

  /// Handles pointer signal events such as mouse-wheel scrolling.
  void handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }

    final wheelX = _wheelDirection(event.scrollDelta.dx, invert: false);
    final wheelY = _wheelDirection(event.scrollDelta.dy, invert: true);
    if (wheelX == 0 && wheelY == 0) {
      return;
    }

    _dispatch(
      (runtime) =>
          runtime.queueWheelMoved(wheelX.toDouble(), wheelY.toDouble()),
    );
  }

  /// Dispatches direct text input from a keyboard event when IME is inactive.
  void _dispatchTextInput(KeyEvent event) {
    if (!keyboard.textInputEnabled || _textInputState.platformSessionActive) {
      return;
    }

    final character = event.character;
    if (character == null || character.isEmpty) {
      return;
    }
    if (character.runes.any((codePoint) => codePoint < 0x20)) {
      return;
    }

    _dispatch((runtime) => runtime.queueTextInput(character));
  }

  /// Updates LOVE mouse coordinates from a viewport-local Flutter position.
  void _updateMousePosition(Offset localPosition) {
    final logicalPosition = _logicalPoint(localPosition);
    mouse.setPosition(
      logicalPosition.dx,
      logicalPosition.dy,
      fromSystemEvent: true,
    );
  }

  /// Converts a viewport-local Flutter point to LOVE logical coordinates.
  Offset _logicalPoint(Offset localPosition) {
    final viewportSize = _viewportSizeProvider?.call();
    if (viewportSize == null) {
      return localPosition;
    }

    return loveFlamePresentationGeometry(
      windowMetrics: _host.windowMetrics,
      viewportSize: viewportSize,
      camera: _cameraProvider?.call(),
    ).viewportToLogicalPoint(localPosition);
  }

  /// Converts a viewport-local Flutter delta to LOVE logical coordinates.
  Offset _logicalDelta(Offset localDelta) {
    final viewportSize = _viewportSizeProvider?.call();
    if (viewportSize == null) {
      return localDelta;
    }

    return loveFlamePresentationGeometry(
      windowMetrics: _host.windowMetrics,
      viewportSize: viewportSize,
      camera: _cameraProvider?.call(),
    ).viewportDeltaToLogicalDelta(localDelta);
  }

  /// Whether [event] originated from a touch pointer.
  bool _isTouch(PointerEvent event) => event.kind == PointerDeviceKind.touch;

  /// The first LOVE mouse button encoded in Flutter's [buttons] bitfield.
  int? _loveMouseButtonFromButtons(int buttons) {
    final orderedBits = <(int bit, int button)>[
      (kPrimaryMouseButton, 1),
      (kSecondaryMouseButton, 2),
      (kMiddleMouseButton, 3),
      (kBackMouseButton, 4),
      (kForwardMouseButton, 5),
    ];

    for (final entry in orderedBits) {
      if ((buttons & entry.$1) != 0) {
        return entry.$2;
      }
    }

    return null;
  }

  /// Normalizes a scroll delta component to a LOVE wheel direction step.
  int _wheelDirection(double value, {required bool invert}) {
    if (value == 0) {
      return 0;
    }

    final direction = value > 0 ? 1 : -1;
    return invert ? -direction : direction;
  }

  /// Routes a gamepad-like keyboard event to the matching virtual control path.
  bool _handleGamepadKeyEvent(KeyEvent event) {
    final button = _loveGamepadButtonFromFlutterLogicalKey(event.logicalKey);
    if (button != null) {
      return _handleGamepadButtonEvent(event, button);
    }

    final axis = _loveGamepadAxisFromFlutterLogicalKey(event.logicalKey);
    if (axis != null) {
      return _handleGamepadAxisEvent(event, axis);
    }

    final joystickButton = _loveJoystickButtonFromFlutterLogicalKey(
      event.logicalKey,
    );
    if (joystickButton != null) {
      return _handleJoystickButtonEvent(event, joystickButton);
    }

    return false;
  }

  /// Handles a synthesized joystick button event for the virtual gamepad.
  bool _handleJoystickButtonEvent(KeyEvent event, int button) {
    switch (event) {
      case KeyDownEvent():
        _ensureVirtualGamepadTracked();
        if (!_virtualJoystickButtonsDown.add(button)) {
          return true;
        }
        _joystickInput.handleJoystickButtonDown(_virtualGamepad, button);
      case KeyRepeatEvent():
        return true;
      case KeyUpEvent():
        if (!_virtualJoystickButtonsDown.remove(button)) {
          return true;
        }
        _joystickInput.handleJoystickButtonUp(_virtualGamepad, button);
    }

    return true;
  }

  /// Handles a synthesized gamepad button event for the virtual gamepad.
  bool _handleGamepadButtonEvent(KeyEvent event, String button) {
    switch (event) {
      case KeyDownEvent():
        _ensureVirtualGamepadTracked();
        if (!_virtualGamepadButtonsDown.add(button)) {
          return true;
        }
        _joystickInput.handleGamepadButtonDown(_virtualGamepad, button);
      case KeyRepeatEvent():
        return true;
      case KeyUpEvent():
        if (!_virtualGamepadButtonsDown.remove(button)) {
          return true;
        }
        _joystickInput.handleGamepadButtonUp(_virtualGamepad, button);
    }

    return true;
  }

  /// Handles a synthesized gamepad axis event for the virtual gamepad.
  bool _handleGamepadAxisEvent(KeyEvent event, String axis) {
    switch (event) {
      case KeyDownEvent():
        _ensureVirtualGamepadTracked();
        if (_virtualGamepadAxes[axis] == 1.0) {
          return true;
        }
        _virtualGamepadAxes[axis] = 1.0;
        _joystickInput.handleGamepadAxisMotion(_virtualGamepad, axis, 1.0);
      case KeyRepeatEvent():
        return true;
      case KeyUpEvent():
        if ((_virtualGamepadAxes.remove(axis) ?? 0.0) == 0.0) {
          return true;
        }
        _joystickInput.handleGamepadAxisMotion(_virtualGamepad, axis, 0.0);
    }

    return true;
  }

  /// Registers the synthesized virtual gamepad with the joystick adapter.
  void _ensureVirtualGamepadTracked() {
    if (_virtualGamepadTracked) {
      return;
    }

    _virtualGamepadTracked = true;
    _joystickInput.handleDeviceAdded(_virtualGamepad);
  }

  /// Clears every synthesized virtual gamepad input currently held down.
  void _resetVirtualGamepadState() {
    if (!_virtualGamepadTracked) {
      return;
    }

    _joystickInput.resetJoystickState(
      _virtualGamepad,
      buttons: _virtualJoystickButtonsDown,
    );
    _joystickInput.resetGamepadState(
      _virtualGamepad,
      buttons: _virtualGamepadButtonsDown,
      axes: _virtualGamepadAxes.keys,
    );
    _virtualJoystickButtonsDown.clear();
    _virtualGamepadButtonsDown.clear();
    _virtualGamepadAxes.clear();
  }

  /// Synchronizes LOVE window focus state with [focused].
  void _setFocusState(bool focused) {
    if (_focused == focused) {
      return;
    }

    _focused = focused;
    _host.windowHasFocus = focused;
    _dispatch((runtime) => runtime.queueFocus(focused));
  }

  /// Synchronizes LOVE mouse-focus state with [focused].
  void _setMouseFocusState(bool focused) {
    if (_mouseFocused == focused) {
      return;
    }

    _mouseFocused = focused;
    _host.windowHasMouseFocus = focused;
    _dispatch((runtime) => runtime.queueMouseFocus(focused));
  }

  /// Queues [callback] onto the active LOVE runtime in dispatch order.
  void _dispatch(Future<Object?> Function(LoveScriptRuntime runtime) callback) {
    final runtime = _runtimeProvider();
    if (runtime == null) {
      return;
    }

    _dispatchQueue = _dispatchQueue.then((_) async {
      try {
        await callback(runtime);
      } catch (error, stackTrace) {
        final handler = onError;
        if (handler != null) {
          handler(error, stackTrace);
        }
      }
    });
  }
}
