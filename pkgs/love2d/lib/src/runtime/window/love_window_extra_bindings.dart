library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Tracks which runtimes already have window extra bindings installed.
final Expando<bool> _loveWindowExtrasInstalled = Expando<bool>(
  'love2dWindowExtrasInstalled',
);

/// The generated enum tables exposed through the LOVE window module.
final Map<String, Map<String, Object?>> _loveWindowEnumMaps =
    _buildLoveWindowEnumMaps();

/// Builds Lua-facing enum tables for the `love.window` module.
Map<String, Map<String, Object?>> _buildLoveWindowEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.window') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

/// Installs generated window enum tables and aliases into [runtime].
void installLoveWindowExtraBindings(LuaRuntime runtime) {
  if (_loveWindowExtrasInstalled[runtime] == true) {
    return;
  }

  final windowTable = _windowModuleTable(runtime);
  if (windowTable == null) {
    return;
  }

  for (final entry in _loveWindowEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    windowTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  final dpiScale = windowTable['getDPIScale'];
  if (dpiScale != null) {
    windowTable['getNativeDPIScale'] = dpiScale;
  }

  _loveWindowExtrasInstalled[runtime] = true;
}

/// The `love.window` module table from [runtime], if one is available.
Map<dynamic, dynamic>? _windowModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final window = loveTable['window'];
  final windowTable = window is Value ? window.raw : window;
  if (windowTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return windowTable;
}
