library;

import 'dart:async';
import 'dart:ui' as ui;

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

const bool _loveTraceTouchLeak = bool.fromEnvironment(
  'LOVE2D_TRACE_TOUCH_LEAK',
  defaultValue: true,
);

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
  // print('[love2d-touch] $stage${message.isEmpty ? '' : ' $message'}');
}

class LoveFlameInputAdapter {
  LoveFlameInputAdapter({
    required LoveHost host,
    required LoveScriptRuntime? Function() runtimeProvider,
    Size? Function()? viewportSizeProvider,
    LoveJoystickInputAdapter? joystickInput,
    this.onError,
    this.consumeKeyboardEvents = true,
  }) : _host = host,
       _runtimeProvider = runtimeProvider,
       _viewportSizeProvider = viewportSizeProvider,
       _joystickInput =
           joystickInput ??
           LoveJoystickInputAdapter(
             host: host,
             runtimeProvider: runtimeProvider,
             onError: onError,
           );

  final LoveHost _host;
  final LoveScriptRuntime? Function() _runtimeProvider;
  final Size? Function()? _viewportSizeProvider;
  final LoveJoystickInputAdapter _joystickInput;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final bool consumeKeyboardEvents;
  final Map<int, int> _pointerButtons = <int, int>{};
  final Set<int> _virtualJoystickButtonsDown = <int>{};
  final Set<String> _virtualGamepadButtonsDown = <String>{};
  final Map<String, double> _virtualGamepadAxes = <String, double>{};
  late final LoveFlameTextInputState _textInputState = LoveFlameTextInputState(
    keyboard: keyboard,
    dispatch: _dispatch,
  );
  Future<void> _dispatchQueue = Future<void>.value();

  bool _focused = false;
  bool _mouseFocused = false;
  bool _virtualGamepadTracked = false;

  late final LoveJoystickDevice _virtualGamepad = LoveJoystickDevice(
    id: _loveFlameVirtualGamepadId,
    name: _loveFlameVirtualGamepadName,
    connected: false,
    gamepad: true,
    guid: _loveFlameVirtualGamepadGuid,
  );

  LoveKeyboardState get keyboard => _host.keyboard;
  LoveMouseState get mouse => _host.mouse;
  LoveTouchState get touch => _host.touch;
  TextEditingValue get currentTextEditingValue => _textInputState.editingValue;

  Future<void> flush() async {
    await _dispatchQueue;
    await _joystickInput.flush();
  }

  void beginPlatformTextInputSession() {
    _textInputState.beginPlatformSession();
  }

  void endPlatformTextInputSession() {
    _textInputState.endPlatformSession();
  }

  void handleTextEditingValue(TextEditingValue value) {
    _textInputState.handleEditingValue(value);
  }

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

  void handleFocusChanged(bool focused) {
    _setFocusState(focused);
  }

  void handlePointerEnter(PointerEnterEvent event) {
    _updateMousePosition(event.localPosition);
    _setMouseFocusState(true);
  }

  void handlePointerExit(PointerExitEvent event) {
    _updateMousePosition(event.localPosition);
    _setMouseFocusState(false);
  }

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

  void _updateMousePosition(Offset localPosition) {
    final logicalPosition = _logicalPoint(localPosition);
    mouse.setPosition(
      logicalPosition.dx,
      logicalPosition.dy,
      fromSystemEvent: true,
    );
  }

  Offset _logicalPoint(Offset localPosition) {
    final viewportSize = _viewportSizeProvider?.call();
    if (viewportSize == null) {
      return localPosition;
    }

    return loveViewportToLogicalPoint(
      viewportPoint: localPosition,
      windowMetrics: _host.windowMetrics,
      viewportSize: viewportSize,
    );
  }

  Offset _logicalDelta(Offset localDelta) {
    final viewportSize = _viewportSizeProvider?.call();
    if (viewportSize == null) {
      return localDelta;
    }

    return loveViewportDeltaToLogicalDelta(
      viewportDelta: localDelta,
      windowMetrics: _host.windowMetrics,
      viewportSize: viewportSize,
    );
  }

  bool _isTouch(PointerEvent event) => event.kind == PointerDeviceKind.touch;

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

  int _wheelDirection(double value, {required bool invert}) {
    if (value == 0) {
      return 0;
    }

    final direction = value > 0 ? 1 : -1;
    return invert ? -direction : direction;
  }

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

  void _ensureVirtualGamepadTracked() {
    if (_virtualGamepadTracked) {
      return;
    }

    _virtualGamepadTracked = true;
    _joystickInput.handleDeviceAdded(_virtualGamepad);
  }

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

  void _setFocusState(bool focused) {
    if (_focused == focused) {
      return;
    }

    _focused = focused;
    _host.windowHasFocus = focused;
    _dispatch((runtime) => runtime.queueFocus(focused));
  }

  void _setMouseFocusState(bool focused) {
    if (_mouseFocused == focused) {
      return;
    }

    _mouseFocused = focused;
    _host.windowHasMouseFocus = focused;
    _dispatch((runtime) => runtime.queueMouseFocus(focused));
  }

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
