import '../lua_string.dart';
import '../runtime/lua_slot.dart';
import '../value.dart';

/// Extension methods for all objects to simplify Value conversion.
///
/// IMPORTANT: This extension is on [Object?] — NOT on `dynamic` — so that
/// it resolves properly in Dart's extension method system. Extensions on
/// `dynamic` are silently ignored by the compiler.
extension DynamicValueExtension on Object? {
  /// Convert any object to a Value if it's not already one
  /// Recursively converts any object to a LuaLike Value.
  ///
  /// • If the object is already a Value and its underlying raw value is a Map or List,
  ///   then all nested entries are converted recursively.
  /// • If the object is a Map, then each value is recursively converted.
  /// • If the object is a List, then each element is recursively converted.
  /// • Otherwise, the object is simply wrapped in a Value.
  Value toValue() {
    if (this is Value) {
      final val = this as Value;
      final raw = rawLuaSlot(val);

      if (raw is Map) {
        final rawMap = raw.map((k, v) => MapEntry(k, v.toValue()));
        return Value(rawMap, metatable: val.metatable);
      } else if (raw is List) {
        return Value(Value.listToLuaTable(raw), metatable: val.metatable);
      }

      return val;
    } else if (this is Map) {
      final map = (this as Map).map((k, v) => MapEntry(k, v.toValue()));
      return Value(map);
    } else if (this is List) {
      final list = (this as List).map((e) => e.toValue()).toList();
      return Value(Value.listToLuaTable(list));
    }
    return Value.wrap(this);
  }

  /// Unwrap this value to its raw Dart equivalent.
  ///
  /// If the value is a [Value], it is recursively unwrapped (handles nested
  /// Value wrappers). If the value is a [LuaString], it is converted to a
  /// Dart [String]. Otherwise the original value is returned.
  Object? unwrap() {
    if (this is Value) return (this as Value).completeUnwrap();
    if (this is LuaString) return (this as LuaString).toLatin1String();
    return this;
  }

  /// Check if the object is "truthy" in Lua sense
  bool isLuaTruthy() {
    if (this == null || this == false) return false;
    return true;
  }
}
