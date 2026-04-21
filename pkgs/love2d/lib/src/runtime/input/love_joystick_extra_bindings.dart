library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

final Expando<bool> _loveJoystickExtrasInstalled = Expando<bool>(
  'love2dJoystickExtrasInstalled',
);

final Map<String, Map<String, Object?>> _loveJoystickEnumMaps =
    _buildLoveJoystickEnumMaps();

Map<String, Map<String, Object?>> _buildLoveJoystickEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.joystick') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

void installLoveJoystickExtraBindings(LuaRuntime runtime) {
  if (_loveJoystickExtrasInstalled[runtime] == true) {
    return;
  }

  final joystickTable = _joystickModuleTable(runtime);
  if (joystickTable == null) {
    return;
  }

  for (final entry in _loveJoystickEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    joystickTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  _loveJoystickExtrasInstalled[runtime] = true;
}

Map<dynamic, dynamic>? _joystickModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final joystick = loveTable['joystick'];
  final joystickTable = joystick is Value ? joystick.raw : joystick;
  if (joystickTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return joystickTable;
}
