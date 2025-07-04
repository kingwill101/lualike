import '../logger.dart';
import '../lua_string.dart';
import '../value.dart';

dynamic fromLuaValue(dynamic obj) {
  if (obj is Value) {
    if (obj.raw is Map) {
      final rawMap = obj.raw as Map;
      final unwrappedMap = <dynamic, dynamic>{};

      rawMap.forEach((key, value) {
        unwrappedMap[key] = fromLuaValue(value);
      });

      // Patch: Convert array-like tables (integer keys starting at 1, contiguous) to Dart lists.
      // This matches Lua's semantics for array tables, including nil values.
      final keys = unwrappedMap.keys;
      if (keys.isNotEmpty && keys.every((k) => k is int)) {
        final intKeys = keys.cast<int>().toList()..sort();
        // Find the maximum contiguous N such that keys 1..N exist (even if values are null)
        int maxIndex = 0;
        for (int i = 1; i <= intKeys.last; i++) {
          if (!unwrappedMap.containsKey(i)) {
            break;
          }
          maxIndex = i;
        }
        if (maxIndex > 0) {
          // Build a Dart list up to maxIndex (may include nulls)
          return List.generate(maxIndex, (i) => unwrappedMap[i + 1]);
        }
      }

      return unwrappedMap;
    }
    // 2) If the underlying raw is a List, then recursively unwrap each element.
    else if (obj.raw is List) {
      return (obj.raw as List).map((e) => fromLuaValue(e)).toList();
    }

    // 3) Otherwise, it's a primitive or something else; just return its raw value.
    return obj.raw;
  }

  // If it's not a Value, return it as-is.
  return obj;
}

Value toLuaValue(dynamic dy) {
  /// Recursively converts a LuaLike Value (or a plain object) into standard Dart objects.
  /// If the object is a Value and its raw value is a Map or a List,
  /// then each element is recursively unwrapped.

  if (dy is Value) {
    final val = dy;

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
  } else if (dy is Map) {
    // Recursively convert each value in the map.
    final map = (dy).map((k, v) => MapEntry(k, toLuaValue(v)));
    return Value(map);
  } else if (dy is List) {
    // Recursively convert list elements.
    final list = (dy).map((e) => toLuaValue(e)).toList();
    return Value(list);
  }
  // For any other type, simply wrap it.
  return Value(dy);
}

/// Extension methods for the Value class to simplify common operations
extension ValueExtension<T> on T {
  get raw => this is Value ? (this as Value).raw : this;

  get isValue => this is Value;

  Value get value => this is Value ? this as Value : Value(this);

  /// Unwraps a Value to its raw content if it is a Value, otherwise returns the object itself
  dynamic get unwrapped => raw is Value ? (raw as Value).unwrapped : raw;

  /// Checks if this Value is nil (null in Lua sense)
  bool get isNil => raw == null;

  /// Checks if this Value is a table
  bool get isTable => raw is Map;

  /// Checks if this Value is a function
  bool get isFunction => raw is Function;

  /// Checks if this Value is a number
  bool get isNumber => raw is num;

  /// Checks if this Value is a string
  bool get isString => raw is String || raw is LuaString;

  /// Checks if this Value is a boolean
  bool get isBoolean => raw is bool;

  /// Converts this Value to a boolean according to Lua truthiness rules
  bool toBool() => raw != null && raw != false;

  /// Check if the object is "truthy" in Lua sense
  bool isLuaTruthy() {
    if (raw == null || raw == false) return false;
    return true;
  }

  /// Safely calls this Value as a function with given arguments
  /// Returns the result, or throws if not callable
  Future<dynamic> callFunction(List<dynamic> args) async {
    if (raw is Function) {
      final result = raw(args);
      return result is Future ? await result : result;
    } else if (value.hasMetamethod('__call')) {
      return value.callMetamethod('__call', [
        this as Value,
        ...args.map((a) => a is Value ? a : Value(a)),
      ]);
    }
    throw UnsupportedError('Value is not callable: $this');
  }

  /// Apply a binary metamethod with proper error handling
  Value applyBinaryMetamethod(String metamethodName, dynamic other) {
    final wrappedOther = other is Value ? other : Value(other);
    var metamethod =
        value.getMetamethod(metamethodName) ??
        wrappedOther.getMetamethod(metamethodName);

    if (metamethod != null) {
      try {
        dynamic result;
        if (metamethod is Function) {
          result = metamethod([this, wrappedOther]);
        } else if (metamethod is Value && metamethod.raw is Function) {
          result = metamethod.raw([this, wrappedOther]);
        } else {
          throw UnsupportedError(
            "Metamethod $metamethodName exists but is not callable: $metamethod",
          );
        }
        return result is Value ? result : Value(result);
      } catch (e) {
        Logger.error('Error invoking metamethod $metamethodName: $e', error: e);
        rethrow;
      }
    }

    throw UnsupportedError(
      "Operation not supported for these types: ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

  /// Check if a value has any of the specified metamethods
  bool hasAnyMetamethod(List<String> methods) {
    if (value.metatable == null) return false;
    return methods.any((method) => value.metatable!.containsKey(method));
  }
}
