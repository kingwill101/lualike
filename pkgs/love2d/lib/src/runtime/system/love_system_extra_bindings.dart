library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

final Expando<bool> _loveSystemExtrasInstalled = Expando<bool>(
  'love2dSystemExtrasInstalled',
);

final Map<String, Map<String, Object?>> _loveSystemEnumMaps =
    _buildLoveSystemEnumMaps();

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

void installLoveSystemExtraBindings(LuaRuntime runtime) {
  if (_loveSystemExtrasInstalled[runtime] == true) {
    return;
  }

  final systemTable = _systemModuleTable(runtime);
  if (systemTable == null) {
    return;
  }

  for (final entry in _loveSystemEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    systemTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  _loveSystemExtrasInstalled[runtime] = true;
}

Map<dynamic, dynamic>? _systemModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final system = loveTable['system'];
  final systemTable = system is Value ? system.raw : system;
  if (systemTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return systemTable;
}
