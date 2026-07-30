library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_binding_helpers.dart';
import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Tracks which runtimes already have joystick extra bindings installed.
final Expando<bool> _loveJoystickExtrasInstalled = Expando<bool>(
  'love2dJoystickExtrasInstalled',
);

/// The generated enum tables exposed through the LOVE joystick module.
final Map<String, Map<String, Object?>> _loveJoystickEnumMaps =
    _buildLoveJoystickEnumMaps();

/// Builds Lua-facing enum tables for the `love.joystick` module.
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

/// Installs generated joystick enum tables into [runtime].
void installLoveJoystickExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveJoystickExtrasInstalled,
    moduleName: 'joystick',
    install: _installLoveJoystickExtraBindings,
  );
}

void _installLoveJoystickExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> joystickTable,
) {
  for (final entry in _loveJoystickEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    joystickTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }
}
