part of '../love_api_bindings.dart';

final Expando<bool> _loveJoystickReleased = Expando<bool>(
  'love2dJoystickReleased',
);

LoveJoystickDevice? _joystickIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final joystick = table[_loveJoystickObjectKey];
  return joystick is LoveJoystickDevice ? joystick : null;
}

LoveJoystickDevice _requireJoystick(
  List<Object?> args,
  int index,
  String symbol,
) {
  final joystick = _joystickIfPresent(_valueAt(args, index));
  if (joystick != null) {
    return joystick;
  }

  throw LuaError('$symbol expected a Joystick at argument ${index + 1}');
}

/// Wraps a joystick object for direct use in runtime-dispatched callbacks.
///
/// This reuses the same cached wrapper shape as the `love.joystick` module so
/// callback payloads and module-returned joystick objects behave identically.
Value wrapLoveJoystickForRuntime(
  LuaRuntime runtime,
  LoveJoystickDevice joystick,
) {
  final context = LibraryContext(
    environment: runtime.getCurrentEnv(),
    interpreter: runtime,
  );
  return _wrapJoystick(context, joystick);
}

Value _wrapJoystick(LibraryContext context, LoveJoystickDevice joystick) {
  final cached = _loveJoystickWrapperCache[joystick];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Joystick', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveJoystickObjectKey: joystick,
    'getAxes': Value(
      builder.create(_bindJoystickGetAxes(context)),
      functionName: 'getAxes',
    ),
    'getAxis': Value(
      builder.create(_bindJoystickGetAxis(context)),
      functionName: 'getAxis',
    ),
    'getAxisCount': Value(
      builder.create(_bindJoystickGetAxisCount(context)),
      functionName: 'getAxisCount',
    ),
    'getButtonCount': Value(
      builder.create(_bindJoystickGetButtonCount(context)),
      functionName: 'getButtonCount',
    ),
    'getDeviceInfo': Value(
      builder.create(_bindJoystickGetDeviceInfo(context)),
      functionName: 'getDeviceInfo',
    ),
    'getGUID': Value(
      builder.create(_bindJoystickGetGuid(context)),
      functionName: 'getGUID',
    ),
    'getGamepadAxis': Value(
      builder.create(_bindJoystickGetGamepadAxis(context)),
      functionName: 'getGamepadAxis',
    ),
    'getGamepadMapping': Value(
      builder.create(_bindJoystickGetGamepadMapping(context)),
      functionName: 'getGamepadMapping',
    ),
    'getGamepadMappingString': Value(
      builder.create(_bindJoystickGetGamepadMappingStringMethod(context)),
      functionName: 'getGamepadMappingString',
    ),
    'getHat': Value(
      builder.create(_bindJoystickGetHat(context)),
      functionName: 'getHat',
    ),
    'getHatCount': Value(
      builder.create(_bindJoystickGetHatCount(context)),
      functionName: 'getHatCount',
    ),
    'getID': Value(
      builder.create(_bindJoystickGetId(context)),
      functionName: 'getID',
    ),
    'getName': Value(
      builder.create(_bindJoystickGetName(context)),
      functionName: 'getName',
    ),
    'getVibration': Value(
      builder.create(_bindJoystickGetVibration(context)),
      functionName: 'getVibration',
    ),
    'isConnected': Value(
      builder.create(_bindJoystickIsConnected(context)),
      functionName: 'isConnected',
    ),
    'isDown': Value(
      builder.create(_bindJoystickIsDown(context)),
      functionName: 'isDown',
    ),
    'isGamepad': Value(
      builder.create(_bindJoystickIsGamepad(context)),
      functionName: 'isGamepad',
    ),
    'isGamepadDown': Value(
      builder.create(_bindJoystickIsGamepadDown(context)),
      functionName: 'isGamepadDown',
    ),
    'isVibrationSupported': Value(
      builder.create(_bindJoystickIsVibrationSupported(context)),
      functionName: 'isVibrationSupported',
    ),
    'setVibration': Value(
      builder.create(_bindJoystickSetVibration(context)),
      functionName: 'setVibration',
    ),
    'release': Value(
      builder.create((args) {
        final joystick = _requireJoystick(args, 0, 'Object:release');
        if (_loveJoystickReleased[joystick] == true) {
          return false;
        }
        _loveJoystickReleased[joystick] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        _requireJoystick(args, 0, 'Object:type');
        return 'Joystick';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireJoystick(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveJoystickWrapperCache[joystick] = table;
  return table;
}
