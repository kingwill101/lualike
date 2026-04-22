part of '../love_api_bindings.dart';

const String _loveJoystickReleasedWrapperKey = '__love2d_joystick_released__';

/// Whether a joystick has already been released through `Object:release`.
final Expando<bool> _loveJoystickReleased = Expando<bool>(
  'love2dJoystickReleased',
);

/// Returns the Lua wrapper table for a `Joystick`, including released wrappers.
Map<dynamic, dynamic>? _joystickWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final joystick = table[_loveJoystickObjectKey];
  if (joystick is LoveJoystickDevice ||
      table[_loveJoystickReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns whether [value] is a released `Joystick` wrapper.
bool _joystickWrapperReleased(Object? value) {
  final table = _joystickWrapperTableIfPresent(value);
  return table?[_loveJoystickReleasedWrapperKey] == true;
}

/// Returns wrapped [LoveJoystickDevice] when [value] is a Joystick table.
LoveJoystickDevice? _joystickIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final joystick = table[_loveJoystickObjectKey];
  return joystick is LoveJoystickDevice ? joystick : null;
}

/// Returns a required `Joystick` receiver.
LoveJoystickDevice _requireJoystick(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_joystickWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final joystick = _joystickIfPresent(value);
  if (joystick != null) {
    return joystick;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'Joystick',
    actual: value,
  );
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

/// Wraps [joystick] as a Lua-facing `Joystick` object table.
Value _wrapJoystick(LibraryContext context, LoveJoystickDevice joystick) {
  final cached = _loveJoystickWrapperCache[joystick];
  if (cached != null && _joystickIfPresent(cached) != null) {
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
        final receiver = _valueAt(args, 0);
        final table = _joystickWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'Joystick',
            actual: receiver,
          );
        }

        final joystick = table[_loveJoystickObjectKey];
        if (joystick is! LoveJoystickDevice) {
          return false;
        }

        if (_loveJoystickReleased[joystick] == true) {
          return false;
        }

        _loveJoystickReleased[joystick] = true;
        table[_loveJoystickReleasedWrapperKey] = true;
        table[_loveJoystickObjectKey] = null;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_joystickWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'Joystick',
            actual: receiver,
          );
        }
        return 'Joystick';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_joystickWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'Joystick',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveJoystickWrapperCache[joystick] = table;
  return table;
}
