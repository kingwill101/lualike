/// Extra LOVE physics bindings derived from the generated API reference.
library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_binding_helpers.dart';
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
  for (final entry in _lovePhysicsEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    physicsTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }
}
