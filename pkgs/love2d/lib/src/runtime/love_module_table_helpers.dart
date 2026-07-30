import 'package:lualike/lualike.dart' show LuaRuntime, Value;

/// Returns [value] unwrapped from a LOVE `Value` wrapper when necessary.
Object? loveRawValue(Object? value) => value is Value ? value.raw : value;

/// Returns the requested LOVE module table, if the module exists.
Map<dynamic, dynamic>? loveModuleTable(LuaRuntime runtime, String moduleName) {
  final moduleTable = loveRawValue(runtime.globals.get('love.$moduleName'));
  return moduleTable is Map<dynamic, dynamic> ? moduleTable : null;
}
