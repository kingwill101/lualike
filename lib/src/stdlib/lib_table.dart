import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';

import '../number_limits.dart';

class TableLib {
  static final ValueClass tableClass = ValueClass.create({
    "__len": (List<Object?> args) {
      final table = args[0] as Value;
      if (table.raw is Map) {
        return Value((table.raw as Map).length);
      }
      throw LuaError.typeError("__len metamethod called on non-table value");
    },
  });

  static final Map<String, BuiltinFunction> functions = {
    "insert": _TableInsert(),
    "remove": _TableRemove(),
    "concat": _TableConcat(),
    "move": _TableMove(),
    "pack": _TablePack(),
    "sort": _TableSort(),
    "unpack": _TableUnpack(),
  };
}

class _TableInsert implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2 || args.length > 3) {
      throw LuaError("wrong number of arguments to 'insert'");
    }
    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError.typeError(
        "table.insert requires a table as first argument",
      );
    }

    final map = table.raw as Map;
    final pos = args.length == 3
        ? (args[1] as Value).raw as int
        : map.length + 1;
    final value = args[args.length == 3 ? 2 : 1];

    // Shift existing elements
    for (var i = map.length + 1; i > pos; i--) {
      map[i] = map[i - 1];
    }
    map[pos] = value;
    return Value(null);
  }
}

class _TableRemove implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("table.remove requires a table argument");
    }
    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError.typeError(
        "table.remove requires a table as first argument",
      );
    }

    final map = table.raw as Map;
    final pos = args.length > 1 ? (args[1] as Value).raw as int : map.length;

    if (map.isEmpty) {
      return Value(null);
    }

    final removed = map[pos];

    // Shift elements
    for (var i = pos; i < map.length; i++) {
      map[i] = map[i + 1];
    }
    map.remove(map.length);

    return removed as Value;
  }
}

class _TableConcat implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("table expected");
    }
    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError.typeError("table expected");
    }

    final map = table.raw as Map;
    final sep = args.length > 1 ? (args[1] as Value).raw.toString() : "";
    final start = args.length > 2 ? (args[2] as Value).raw as int : 1;
    final end = args.length > 3 ? (args[3] as Value).raw as int : map.length;

    // If start > end, return empty string (Lua behavior)
    if (start > end) {
      return Value("");
    }

    final buffer = StringBuffer();
    var i = start;
    while (NumberUtils.compare(i, end) <= 0) {
      if (NumberUtils.compare(i, start) > 0) {
        buffer.write(sep);
      }
      final value = map[i];
      if (value == null || (value is Value && value.raw == null)) {
        // Lua throws an error when encountering nil values in the range
        throw LuaError("invalid value (nil) at index $i in table for 'concat'");
      }

      // Validate that the value is a string or number
      final rawValue = (value as Value).raw;
      NumberUtils.validateStringOrNumber(rawValue, 'concat', i);

      buffer.write(rawValue.toString());

      // Prevent integer overflow when i == max integer
      if (i == NumberLimits.maxInteger) break;

      // Use NumberUtils for safe increment
      i = NumberUtils.add(i, 1);
    }

    return Value(buffer.toString());
  }
}

class _TableMove implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 4) {
      throw LuaError.typeError("table.move requires at least 4 arguments");
    }

    final a1 = args[0] as Value;
    final f = (args[1] as Value).raw as int;
    final e = (args[2] as Value).raw as int;
    final t = (args[3] as Value).raw as int;
    final a2 = args.length > 4 ? args[4] as Value : a1;

    if (a1.raw is! Map || a2.raw is! Map) {
      throw LuaError.typeError("table.move requires table arguments");
    }

    final srcTable = a1.raw as Map;
    final destTable = a2.raw as Map;

    if (f > e) {
      return a2; // Nothing to move
    }

    // Check for "too many elements to move" (from C implementation)
    // Use NumberUtils for safe arithmetic operations
    if (f <= 0 && e > 0) {
      final maxAllowed = NumberUtils.add(NumberLimits.maxInteger, f);
      if (NumberUtils.compare(e, maxAllowed) > 0) {
        throw LuaError("too many elements to move");
      }
    }

    // Calculate n = e - f + 1 using NumberUtils to handle overflow
    final n = NumberUtils.add(NumberUtils.subtract(e, f), 1);

    // Check for "destination wrap around" (from C implementation)
    // luaL_argcheck(L, t <= LUA_MAXINTEGER - n + 1, 4, "destination wrap around");
    final maxDest = NumberUtils.add(
      NumberLimits.maxInteger,
      NumberUtils.subtract(1, n),
    );
    if (NumberUtils.compare(t, maxDest) > 0) {
      throw LuaError("destination wrap around");
    }

    // For extremely large ranges (like 1 to maxI), fail early after first access
    // This matches the Lua reference implementation behavior
    if (NumberUtils.compare(e, f) > NumberLimits.maxInt32) {
      // Just access the first element to trigger metamethods, then fail
      final value = srcTable[f];
      final destIndex = t;
      destTable[destIndex] = value;
      throw LuaError("too many elements to move");
    }

    // Calculate the direction of movement to avoid overwriting values
    // when source and destination tables are the same
    if (a1 == a2 && NumberUtils.compare(t, f) > 0) {
      // Move from right to left (highest index first)
      var i = e;
      while (NumberUtils.compare(i, f) >= 0) {
        final value = srcTable[i];
        final destIndex = NumberUtils.add(t, NumberUtils.subtract(i, f));
        destTable[destIndex] = value;

        // Check for integer overflow to prevent infinite loops
        if (i == NumberLimits.minInteger) {
          break; // Can't decrement further
        }

        // Use NumberUtils for safe decrement
        i = NumberUtils.subtract(i, 1);
      }
    } else {
      // Move from left to right (lowest index first)
      var i = f;
      while (NumberUtils.compare(i, e) <= 0) {
        final value = srcTable[i];
        final destIndex = NumberUtils.add(t, NumberUtils.subtract(i, f));
        destTable[destIndex] = value;

        // Check for integer overflow to prevent infinite loops
        if (i == NumberLimits.maxInteger) {
          break; // Can't increment further
        }

        // Use NumberUtils for safe increment
        i = NumberUtils.add(i, 1);
      }
    }

    return a2;
  }
}

class _TableSort implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("table.sort requires a table argument");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError.typeError("table.sort requires a table as first argument");
    }

    final map = table.raw as Map;
    final comp = args.length > 1 ? args[1] : null;

    // Get the array part of the table (numeric indices)
    final keys = map.keys.where((k) => k is int && k >= 1).toList()..sort();
    if (keys.isEmpty) {
      return Value(null);
    }

    // Get the maximum array index
    final maxIndex = keys.last as int;

    // Check for "array too big" (from C implementation)
    // luaL_argcheck(L, n < INT_MAX, 1, "array too big");
    if (maxIndex >= NumberLimits.maxInt32) {
      throw LuaError("array too big");
    }

    // Create a list of values to sort
    final values = <dynamic>[];
    for (var i = 1; i <= maxIndex; i++) {
      final value = map[i];
      if (value != null) {
        values.add(value);
      }
    }

    // Sort the values
    if (comp != null) {
      // Use bubble sort since we need to handle yields during comparisons
      try {
        var i = 0;
        while (i < values.length) {
          var j = 0;
          while (j < values.length - i - 1) {
            if (comp is Value && comp.raw is Function) {
              final func = comp.raw as Function;
              final a = values[j];
              final b = values[j + 1];

              // Call comparator - this might yield
              final result = await func([a, b]);

              // Handle result after potential yield
              bool shouldSwap = false;
              if (result is Value) {
                shouldSwap = result.raw != true;
              } else {
                shouldSwap = result != true;
              }

              if (shouldSwap) {
                final temp = values[j];
                values[j] = values[j + 1];
                values[j + 1] = temp;
              }
            } else {
              throw LuaError.typeError("invalid order function for sorting");
            }
            j++;
          }
          i++;
        }
      } catch (e) {
        if (e is YieldException) {
          // Let yield propagate up
          rethrow;
        }
        throw LuaError.typeError("invalid order function for sorting: $e");
      }
    } else {
      // Default comparison without yields
      values.sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;

        if (a is Value && b is Value) {
          final aVal = a.raw;
          final bVal = b.raw;

          // Both numbers
          if (aVal is num && bVal is num) {
            return aVal.compareTo(bVal);
          }

          // Both strings
          if (aVal is String && bVal is String) {
            return aVal.compareTo(bVal);
          }

          // Mixed types or unsupported types
          throw LuaError.typeError("attempt to compare incompatible types");
        } else if (a is num && b is num) {
          return a.compareTo(b);
        } else if (a is String && b is String) {
          return a.compareTo(b);
        } else {
          throw LuaError.typeError("attempt to compare incompatible types");
        }
      });
    }

    // Update the table with sorted values
    for (var i = 0; i < values.length; i++) {
      map[i + 1] = values[i];
    }

    return Value(null);
  }
}

class _TablePack implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final table = <dynamic, dynamic>{};
    for (var i = 0; i < args.length; i++) {
      table[i + 1] = args[i];
    }
    table['n'] = args.length;
    return ValueClass.table(table);
  }
}

class _TableUnpack implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("table.unpack requires a table argument");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError.typeError("table.unpack requires a table argument");
    }
    final map = table.raw as Map;

    int i, j;

    // Handle start index (default to 1)
    if (args.length > 1) {
      final startArg = args[1] as Value;
      if (startArg.raw == null) {
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected, got nil)",
        );
      }
      try {
        i = NumberUtils.toInt(startArg.raw);
      } catch (e) {
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected)",
        );
      }
    } else {
      i = 1;
    }

    // Handle end index (default to table length using Lua semantics)
    if (args.length > 2) {
      final endArg = args[2] as Value;
      if (endArg.raw == null) {
        // nil means use table length (same as not providing the argument)
        j = _getTableLength(map);
      } else {
        try {
          j = NumberUtils.toInt(endArg.raw);
        } catch (e) {
          throw LuaError.typeError(
            "bad argument #3 to 'unpack' (number expected)",
          );
        }
      }
    } else {
      j = _getTableLength(map);
    }

    // Check for empty range
    if (i > j) {
      return Value.multi([]);
    }

    // Check for "too many results to unpack"
    // Use NumberUtils for safe arithmetic operations

    // Calculate n = j - i + 1 using NumberUtils to handle overflow
    final n = NumberUtils.add(NumberUtils.subtract(j, i), 1);

    // Check if n is valid (positive and not too large)
    if (n < 0 || n >= NumberLimits.maxInt32) {
      throw LuaError("too many results to unpack");
    }

    final result = <Value>[];

    // Use NumberUtils for safe loop iteration
    var k = i;
    while (NumberUtils.compare(k, j) <= 0) {
      final v = map[k];
      if (v == null || (v is Value && v.raw == null)) {
        result.add(Value(null));
      } else {
        result.add(v is Value ? v : Value(v));
      }

      // Use NumberUtils for safe increment
      if (k == NumberLimits.maxInteger) {
        break; // Can't increment further
      }
      k = NumberUtils.add(k, 1);
    }

    if (result.isEmpty) return Value.multi([]);
    if (result.length == 1) return result[0];
    return Value.multi(result);
  }

  // Helper method to calculate table length using Lua semantics
  // This finds the largest integer key n such that t[n] is not nil
  // and t[n+1] is nil
  int _getTableLength(Map map) {
    int length = 0;
    for (var key in map.keys) {
      if (key is int && key > 0) {
        final value = map[key];
        if (value != null && !(value is Value && value.raw == null)) {
          if (key > length) {
            // For very large keys (> 10000), skip gap checking entirely to avoid infinite loops
            if (key > 10000) {
              // Skip this key entirely - it's too large to check gaps
              continue;
            }

            // For reasonable keys, do minimal gap checking
            bool hasGap = false;
            final maxGapCheck = 100; // Very small limit to prevent any issues
            final startCheck = length + 1;
            final endCheck = (key - startCheck > maxGapCheck)
                ? startCheck + maxGapCheck
                : key;

            for (var i = startCheck; i < endCheck; i++) {
              final intermediate = map[i];
              if (intermediate == null ||
                  (intermediate is Value && intermediate.raw == null)) {
                hasGap = true;
                break;
              }
            }

            if (!hasGap) {
              length = key;
            }
          }
        }
      }
    }
    return length;
  }
}

void defineTableLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final tableTable = <String, dynamic>{};
  TableLib.functions.forEach((key, value) {
    tableTable[key] = value;
  });
  env.define(
    "table",
    Value(tableTable, metatable: TableLib.tableClass.metamethods),
  );
}
