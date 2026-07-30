library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_binding_helpers.dart';
import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Whether the extra data bindings have already been installed for a runtime.
final Expando<bool> _loveDataExtrasInstalled = Expando<bool>(
  'love2dDataExtrasInstalled',
);

/// Cached LOVE data enum tables keyed by exported symbol name.
final Map<String, Map<String, Object?>> _loveDataEnumMaps =
    _buildLoveDataEnumMaps();

/// Builds Lua-ready enum tables for the `love.data` module.
Map<String, Map<String, Object?>> _buildLoveDataEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.data') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

/// Installs generated enum tables into `love.data`.
void installLoveDataExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveDataExtrasInstalled,
    moduleName: 'data',
    install: _installLoveDataExtraBindings,
  );
}

void _installLoveDataExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> dataTable,
) {
  for (final entry in _loveDataEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    dataTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }
}
