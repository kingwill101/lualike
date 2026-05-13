part of 'love_flame_input.dart';

/// The joystick identifier reserved for the synthesized Flutter gamepad.
const int _loveFlameVirtualGamepadId = -1;

/// The GUID reported for the synthesized Flutter gamepad.
const String _loveFlameVirtualGamepadGuid = 'ffffffffffffffffffffffffffffffff';

/// The device name reported for the synthesized Flutter gamepad.
const String _loveFlameVirtualGamepadName = 'Flutter Virtual Gamepad';

/// Whether [deviceType] should be routed through gamepad input handling.
bool _loveIsGamepadLikeDeviceType(ui.KeyEventDeviceType deviceType) =>
    switch (deviceType) {
      ui.KeyEventDeviceType.gamepad ||
      ui.KeyEventDeviceType.joystick ||
      ui.KeyEventDeviceType.directionalPad => true,
      _ => false,
    };

/// The LOVE gamepad button constant mapped from [key], if one exists.
String? _loveGamepadButtonFromFlutterLogicalKey(LogicalKeyboardKey key) =>
    switch (key) {
      LogicalKeyboardKey.arrowUp => 'dpup',
      LogicalKeyboardKey.arrowDown => 'dpdown',
      LogicalKeyboardKey.arrowLeft => 'dpleft',
      LogicalKeyboardKey.arrowRight => 'dpright',
      LogicalKeyboardKey.gameButtonA => 'a',
      LogicalKeyboardKey.gameButtonB => 'b',
      LogicalKeyboardKey.gameButtonX => 'x',
      LogicalKeyboardKey.gameButtonY => 'y',
      LogicalKeyboardKey.gameButtonSelect => 'back',
      LogicalKeyboardKey.gameButtonMode => 'guide',
      LogicalKeyboardKey.gameButtonStart => 'start',
      LogicalKeyboardKey.gameButtonThumbLeft => 'leftstick',
      LogicalKeyboardKey.gameButtonThumbRight => 'rightstick',
      LogicalKeyboardKey.gameButtonLeft1 => 'leftshoulder',
      LogicalKeyboardKey.gameButtonRight1 => 'rightshoulder',
      _ => null,
    };

/// The LOVE gamepad axis constant mapped from [key], if one exists.
String? _loveGamepadAxisFromFlutterLogicalKey(LogicalKeyboardKey key) =>
    switch (key) {
      LogicalKeyboardKey.gameButtonLeft2 => 'triggerleft',
      LogicalKeyboardKey.gameButtonRight2 => 'triggerright',
      _ => null,
    };

/// The LOVE joystick button number mapped from [key], if one exists.
int? _loveJoystickButtonFromFlutterLogicalKey(LogicalKeyboardKey key) =>
    switch (key) {
      LogicalKeyboardKey.gameButton1 => 1,
      LogicalKeyboardKey.gameButton2 => 2,
      LogicalKeyboardKey.gameButton3 => 3,
      LogicalKeyboardKey.gameButton4 => 4,
      LogicalKeyboardKey.gameButton5 => 5,
      LogicalKeyboardKey.gameButton6 => 6,
      LogicalKeyboardKey.gameButton7 => 7,
      LogicalKeyboardKey.gameButton8 => 8,
      LogicalKeyboardKey.gameButton9 => 9,
      LogicalKeyboardKey.gameButton10 => 10,
      LogicalKeyboardKey.gameButton11 => 11,
      LogicalKeyboardKey.gameButton12 => 12,
      LogicalKeyboardKey.gameButton13 => 13,
      LogicalKeyboardKey.gameButton14 => 14,
      LogicalKeyboardKey.gameButton15 => 15,
      LogicalKeyboardKey.gameButton16 => 16,
      _ => null,
    };
