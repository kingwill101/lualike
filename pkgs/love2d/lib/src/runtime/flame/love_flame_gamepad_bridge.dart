part of 'love_flame_input.dart';

const int _loveFlameVirtualGamepadId = -1;
const String _loveFlameVirtualGamepadGuid = 'ffffffffffffffffffffffffffffffff';
const String _loveFlameVirtualGamepadName = 'Flutter Virtual Gamepad';

bool _loveIsGamepadLikeDeviceType(ui.KeyEventDeviceType deviceType) =>
    switch (deviceType) {
      ui.KeyEventDeviceType.gamepad ||
      ui.KeyEventDeviceType.joystick ||
      ui.KeyEventDeviceType.directionalPad => true,
      _ => false,
    };

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

String? _loveGamepadAxisFromFlutterLogicalKey(LogicalKeyboardKey key) =>
    switch (key) {
      LogicalKeyboardKey.gameButtonLeft2 => 'triggerleft',
      LogicalKeyboardKey.gameButtonRight2 => 'triggerright',
      _ => null,
    };

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
