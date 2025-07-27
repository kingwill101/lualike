import '../value.dart';

/// Extension methods for dynamic objects to simplify Value conversion
extension DynamicValueExtension on dynamic {
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

      // If the underlying raw is a Map, recursively convert each entry.
      if (val.raw is Map) {
        final rawMap = (val.raw as Map).map((k, v) => MapEntry(k, v.toValue()));
        return Value(rawMap, metatable: val.metatable);
      }
      // If the underlying raw is a List, recursively convert each element.
      else if (val.raw is List) {
        final rawList = (val.raw as List).map((e) => e.toValue()).toList();
        return Value(rawList, metatable: val.metatable);
      }

      // Otherwise, it's already a Value wrapping a primitive.
      return val;
    } else if (this is Map) {
      // Recursively convert each value in the map.
      final map = (this as Map).map((k, v) => MapEntry(k, v.toValue()));
      return Value(map);
    } else if (this is List) {
      // Recursively convert list elements.
      final list = (this as List).map((e) => e.toValue()).toList();
      return Value(list);
    }
    // For any other type, simply wrap it.
    return Value(this);
  }

  /// Safely unwrap a Value or return the original object
  dynamic unwrapValue() {
    if (this is Value) return (this as Value).raw;
    return this;
  }

  /// Check if the object is "truthy" in Lua sense
  bool isLuaTruthy() {
    if (this == null || this == false) return false;
    return true;
  }
}
