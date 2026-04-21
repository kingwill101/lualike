library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

final Expando<bool> _loveDataExtrasInstalled = Expando<bool>(
  'love2dDataExtrasInstalled',
);

final Map<String, Map<String, Object?>> _loveDataEnumMaps =
    _buildLoveDataEnumMaps();

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

void installLoveDataExtraBindings(LuaRuntime runtime) {
  if (_loveDataExtrasInstalled[runtime] == true) {
    return;
  }

  final dataTable = _dataModuleTable(runtime);
  if (dataTable == null) {
    return;
  }

  for (final entry in _loveDataEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    dataTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  _loveDataExtrasInstalled[runtime] = true;
}

Map<dynamic, dynamic>? _dataModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final data = loveTable['data'];
  final dataTable = data is Value ? data.raw : data;
  if (dataTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return dataTable;
}
