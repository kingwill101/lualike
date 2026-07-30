library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_binding_helpers.dart';
import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Tracks which runtimes already have system extra bindings installed.
final Expando<bool> _loveSystemExtrasInstalled = Expando<bool>(
  'love2dSystemExtrasInstalled',
);

/// The generated enum tables exposed through the LOVE system module.
final Map<String, Map<String, Object?>> _loveSystemEnumMaps =
    _buildLoveSystemEnumMaps();

/// Builds Lua-facing enum tables for the `love.system` module.
Map<String, Map<String, Object?>> _buildLoveSystemEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.system') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

/// Installs generated system enum tables into [runtime].
void installLoveSystemExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveSystemExtrasInstalled,
    moduleName: 'system',
    install: _installLoveSystemExtraBindings,
  );
}

void _installLoveSystemExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> systemTable,
) {
  for (final entry in _loveSystemEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    systemTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }
}
