library;

import 'package:lualike/lualike.dart' show LuaRuntime;

import '../love_binding_helpers.dart';

/// Tracks which runtimes already have joystick extra bindings installed.
final Expando<bool> _loveJoystickExtrasInstalled = Expando<bool>(
  'love2dJoystickExtrasInstalled',
);

/// The generated enum tables exposed through the LOVE joystick module.
final Map<String, Map<String, Object?>> _loveJoystickEnumMaps =
    loveEnumMapsForModule('love.joystick');

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
  loveInstallEnumTables(runtime, joystickTable, _loveJoystickEnumMaps);
}
