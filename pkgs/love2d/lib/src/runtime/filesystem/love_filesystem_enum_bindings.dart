library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

/// Tracks which runtimes already have filesystem enum bindings installed.
final Expando<bool> _loveFilesystemEnumsInstalled = Expando<bool>(
  'love2dFilesystemEnumsInstalled',
);

/// The generated filesystem enum tables exposed through the LOVE globals.
final Map<String, Map<String, Object?>> _loveFilesystemEnumMaps =
    _buildLoveFilesystemEnumMaps();

/// Builds Lua-facing enum tables for the `love.filesystem` module.
Map<String, Map<String, Object?>> _buildLoveFilesystemEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.filesystem') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

/// Installs generated filesystem enum tables into [runtime].
void installLoveFilesystemEnumBindings(LuaRuntime runtime) {
  if (_loveFilesystemEnumsInstalled[runtime] == true) {
    return;
  }

  final filesystemTable = _filesystemModuleTable(runtime);
  if (filesystemTable == null) {
    return;
  }

  for (final entry in _loveFilesystemEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    filesystemTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  _loveFilesystemEnumsInstalled[runtime] = true;
}

/// The `love.filesystem` module table from [runtime], if one is available.
Map<dynamic, dynamic>? _filesystemModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final filesystem = loveTable['filesystem'];
  final filesystemTable = filesystem is Value ? filesystem.raw : filesystem;
  if (filesystemTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return filesystemTable;
}
