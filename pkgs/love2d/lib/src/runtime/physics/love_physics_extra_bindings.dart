/// Extra LOVE physics bindings derived from the generated API reference.
library;

import 'package:lualike/lualike.dart' show LuaRuntime;

import '../love_binding_helpers.dart';

/// Tracks which runtimes already have the physics extra bindings installed.
final Expando<bool> _lovePhysicsExtrasInstalled = Expando<bool>(
  'love2dPhysicsExtrasInstalled',
);

/// The generated enum tables exposed through `love.physics`.
final Map<String, Map<String, Object?>> _lovePhysicsEnumMaps =
    loveEnumMapsForModule('love.physics');

/// Installs generated enum tables into `love.physics` for [runtime].
void installLovePhysicsExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _lovePhysicsExtrasInstalled,
    moduleName: 'physics',
    install: _installLovePhysicsExtraBindings,
  );
}

void _installLovePhysicsExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> physicsTable,
) {
  loveInstallEnumTables(runtime, physicsTable, _lovePhysicsEnumMaps);
}
