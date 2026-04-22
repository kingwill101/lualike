/// Extra LOVE physics bindings derived from the generated API reference.
library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Tracks which runtimes already have the physics extra bindings installed.
final Expando<bool> _lovePhysicsExtrasInstalled = Expando<bool>(
  'love2dPhysicsExtrasInstalled',
);

/// The generated enum tables exposed through `love.physics`.
final Map<String, Map<String, Object?>> _lovePhysicsEnumMaps =
    _buildLovePhysicsEnumMaps();

/// Builds the runtime enum tables for `love.physics`.
Map<String, Map<String, Object?>> _buildLovePhysicsEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.physics') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

/// Installs generated enum tables into `love.physics` for [runtime].
void installLovePhysicsExtraBindings(LuaRuntime runtime) {
  if (_lovePhysicsExtrasInstalled[runtime] == true) {
    return;
  }

  final physicsTable = _physicsModuleTable(runtime);
  if (physicsTable == null) {
    return;
  }

  for (final entry in _lovePhysicsEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    physicsTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  _lovePhysicsExtrasInstalled[runtime] = true;
}

/// Returns the `love.physics` module table from [runtime], if it exists.
Map<dynamic, dynamic>? _physicsModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final physics = loveTable['physics'];
  final physicsTable = physics is Value ? physics.raw : physics;
  if (physicsTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return physicsTable;
}
