import 'package:lualike/src/intern.dart';

import '../logging/logger.dart';
import '../lua_error.dart';
import '../lua_string.dart';
import '../runtime/lua_slot.dart';
import '../value.dart';

Value _extensionValue(Object? value) => valueFromOptionalLuaSlot(null, value);

dynamic fromLuaValue(dynamic obj) {
  if (obj is Value) {
    final raw = rawLuaSlot(obj);
    if (raw is Map) {
      final rawMap = raw;
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
    // If the underlying raw is a List (legacy/internal), unwrap each element.
    else if (raw is List) {
      return raw.map((e) => fromLuaValue(e)).toList();
    }

    // 3) Otherwise, it's a primitive or something else; just return its raw value.
    if (raw is LuaString) {
      return raw.toLatin1String();
    }
    return raw;
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
    final raw = rawLuaSlot(val);

    // If the underlying raw is a Map, recursively convert each entry.
    if (raw is Map) {
      final rawMap = raw.map((k, v) => MapEntry(k, v.toValue()));
      return Value(rawMap, metatable: val.metatable);
    }
    // If the underlying raw is a List, recursively convert each element.
    else if (raw is List) {
      final rawList = raw.map((e) => e.toValue()).toList();
      return Value(rawList, metatable: val.metatable);
    }

    // Otherwise, it's already a Value wrapping a primitive.
    return val;
  } else if (dy is Map) {
    // Recursively convert each value in the map.
    final map = (dy).map((k, v) => MapEntry(k, toLuaValue(v)));
    return Value(map);
  } else if (dy is List) {
    // Recursively convert list elements and wrap as a 1-based Lua table.
    final list = (dy).map((e) => toLuaValue(e)).toList();
    return Value(Value.listToLuaTable(list));
  }
  // For any other type, simply wrap it.
  return Value.wrap(dy);
}

/// Extension methods for the Value class to simplify common operations
extension ValueExtension<T> on T {
  dynamic get raw => rawLuaSlot(this);

  bool get isValue => this is Value;

  Value get value => _extensionValue(this);

  /// Unwraps a Value to its raw content if it is a Value, otherwise returns the object itself
  dynamic get unwrapped {
    final rawValue = raw;
    if (rawValue is Value) {
      return rawValue.completeUnwrap();
    } else if (rawValue is LuaString) {
      return rawValue.toLatin1String();
    }
    return rawValue;
  }

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

  /// Check if a value has any of the specified metamethods
  bool hasAnyMetamethod(List<String> methods) {
    if (value.metatable == null) return false;
    return methods.any((method) => value.metatable!.containsKey(method));
  }

  /// Concatenates this value with another value.
  /// Handles string and table concatenation with metamethods.
  /// Returns a new Value representing the concatenated result.
  Value concat(dynamic other) {
    final wrappedOther = _extensionValue(other);

    // Check for __concat metamethod
    var metamethod =
        value.getMetamethod('__concat') ??
        wrappedOther.getMetamethod('__concat');

    if (metamethod != null) {
      try {
        dynamic result;
        if (metamethod is Function) {
          result = metamethod([this, wrappedOther]);
        } else if (metamethod is Value && rawLuaSlot(metamethod) is Function) {
          result = (rawLuaSlot(metamethod) as Function)([this, wrappedOther]);
        } else {
          throw UnsupportedError(
            "Metamethod __concat exists but is not callable: $metamethod",
          );
        }
        return result is Value ? result : Value.wrap(result);
      } catch (e) {
        Logger.error('Error invoking __concat metamethod: $e', error: e);
        rethrow;
      }
    }

    // Default string concatenation behavior
    final rawSelf = raw;
    final rawOther = rawLuaSlot(wrappedOther);
    if (isString || wrappedOther.isString) {
      final String leftStr = rawSelf is LuaString
          ? rawSelf.toLatin1String()
          : rawSelf.toString();
      final String rightStr = rawOther is LuaString
          ? rawOther.toLatin1String()
          : rawOther.toString();
      return StringInterning.createStringValue(leftStr + rightStr);
    }

    throw LuaError.typeError(
      "attempt to concatenate a ${rawSelf.runtimeType} with a ${rawOther.runtimeType}",
    );
  }
}
