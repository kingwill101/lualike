import 'package:lualike/lualike.dart' show LuaRuntime, LuaString, Value;

/// Returns [value] unwrapped from a LOVE `Value` wrapper when necessary.
///
/// Lua tables retain their raw identity because their method graphs can be
/// cyclic; recursively unwrapping those graphs would not terminate.
Object? loveRawValue(Object? value) {
  if (value is! Value) {
    return value;
  }

  final raw = value.raw;
  if (raw is Map<dynamic, dynamic> || raw is List<dynamic>) {
    return raw;
  }
  return value.unwrap();
}

/// Returns a Lua table represented by [value], if present.
Map<dynamic, dynamic>? loveTableIfPresent(Object? value) {
  final raw = loveRawValue(value);
  return raw is Map<dynamic, dynamic> ? raw : null;
}

/// Returns a writable Lua table and its optional wrapper, if present.
(Value?, Map<dynamic, dynamic>)? loveTableTargetIfPresent(Object? value) {
  final table = loveTableIfPresent(value);
  if (table == null) {
    return null;
  }
  return (value is Value ? value : null, table);
}

/// Converts Lua values commonly used for string-like arguments to Dart strings.
String? loveStringLike(Object? value, {bool allowNumber = true}) {
  final raw = loveRawValue(value);
  return switch (raw) {
    final String stringValue => stringValue,
    final LuaString stringValue => stringValue.toString(),
    final num numberValue when allowNumber => numberValue.toString(),
    _ => null,
  };
}

/// Returns the requested LOVE module table, if the module exists.
Map<dynamic, dynamic>? loveModuleTable(LuaRuntime runtime, String moduleName) {
  final moduleTable = loveRawValue(runtime.globals.get('love.$moduleName'));
  return moduleTable is Map<dynamic, dynamic> ? moduleTable : null;
}
