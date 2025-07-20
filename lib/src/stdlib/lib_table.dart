import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';

import '../number_limits.dart';

class TablePermission {
  static const int read = 1;
  static const int write = 2;
  static const int length = 4;
}

/// Check that 'table' either is a table or can behave like one (that is,
/// has a metatable with the required metamethods)
void checktab(Value table, int what) {
  if (table.raw is! Map) {
    /* is it not a table? */
    if (table.metatable != null) {
      /* must have metatable */
      bool hasRequired = true;

      if ((what & TablePermission.read) != 0) {
        hasRequired = hasRequired && table.metatable!['__index'] != null;
      }
      if ((what & TablePermission.write) != 0) {
        hasRequired = hasRequired && table.metatable!['__newindex'] != null;
      }
      if ((what & TablePermission.length) != 0) {
        hasRequired = hasRequired && table.metatable!['__len'] != null;
      }

      if (!hasRequired) {
        throw LuaError.typeError("table expected");
      }
    } else {
      throw LuaError.typeError("table expected");
    }
  }
}

/// Get the length of a table, respecting the __len metamethod
/// This corresponds to luaL_len in the C implementation
Future<int> getTableLength(Value table, {String? context}) async {
  // Check if table has a __len metamethod
  if (table.metatable != null) {
    final lenMetamethod = table.metatable!['__len'];
    if (lenMetamethod != null) {
      try {
        final lenResult = await lenMetamethod.call([table]);
        Logger.debug(
          "getTableLength: lenResult = $lenResult, type = ${lenResult.runtimeType}",
        );
        if (lenResult is Value) {
          final lenValue = lenResult.raw;
          if (lenValue is! int && lenValue is! BigInt) {
            throw LuaError("object length is not an integer");
          }
          // Try to convert to int, but catch conversion errors
          try {
            return NumberUtils.toInt(lenValue);
          } catch (e) {
            // If conversion fails due to size, handle based on context
            if (lenValue is BigInt &&
                lenValue >= BigInt.from(NumberLimits.maxInt32)) {
              if (context == "table.sort") {
                throw LuaError(
                  "bad argument #1 to 'table.sort' (array too big)",
                );
              } else {
                throw LuaError("object length is not an integer");
              }
            }
            rethrow;
          }
        } else if (lenResult is int || lenResult is BigInt) {
          // Try to convert to int, but catch conversion errors
          try {
            return NumberUtils.toInt(lenResult);
          } catch (e) {
            // If conversion fails due to size, handle based on context
            if (lenResult is BigInt &&
                lenResult >= BigInt.from(NumberLimits.maxInt32)) {
              if (context == "table.sort") {
                throw LuaError(
                  "bad argument #1 to 'table.sort' (array too big)",
                );
              } else {
                throw LuaError("object length is not an integer");
              }
            }
            rethrow;
          }
        } else {
          throw LuaError("object length is not an integer");
        }
      } catch (e) {
        // If the metamethod throws an error, we should propagate it
        rethrow;
      }
    }
  }

  // No __len metamethod, use regular table length calculation
  if (table.raw is Map) {
    return _getTableLength(table.raw as Map);
  }

  throw LuaError.typeError("table expected");
}

/// Helper method to calculate table length using Lua semantics
/// This finds the largest integer key n such that t[n] is not nil
/// and t[n+1] is nil
int _getTableLength(Map map) {
  Logger.debug(
    "_getTableLength: Starting with ${map.length} keys",
    category: 'Table',
  );
  dynamic length = 0;

  // Find the largest integer key with a non-nil value
  for (var key in map.keys) {
    Logger.debug(
      "_getTableLength: Processing key: $key (${key.runtimeType})",
      category: 'Table',
    );
    if (key is int && key > 0) {
      Logger.debug(
        "_getTableLength: Key is positive int: $key",
        category: 'Table',
      );
      final value = map[key];
      if (value != null && !(value is Value && value.raw == null)) {
        Logger.debug(
          "_getTableLength: Key has non-nil value, comparing with length: $length",
          category: 'Table',
        );
        if (NumberUtils.compare(key, length) > 0) {
          length = key;
          Logger.debug("_getTableLength: Updated length to: $length");
        }
      } else {
        Logger.debug(
          "_getTableLength: Key has nil value, skipping",
          category: 'Table',
        );
      }
    } else {
      Logger.debug(
        "_getTableLength: Key is not positive int, skipping",
        category: 'Table',
      );
    }
  }

  // Now check if t[length+1] is nil to confirm the boundary
  final nextKey = NumberUtils.add(length, 1);
  final nextValue = map[nextKey];
  final nextIsNil =
      nextValue == null || (nextValue is Value && nextValue.raw == null);

  Logger.debug(
    "_getTableLength: Checking boundary at $nextKey, is nil: $nextIsNil",
    category: 'Table',
  );

  // If t[length+1] is not nil, we need to find the actual boundary
  if (!nextIsNil) {
    Logger.debug(
      "_getTableLength: Boundary check failed, finding actual boundary",
      category: 'Table',
    );
    // Find the actual boundary by checking consecutive keys
    var boundary = length;
    var checkKey = NumberUtils.add(boundary, 1);

    // Limit the search to prevent infinite loops
    final maxSearch = 1000;
    var searchCount = 0;

    while (searchCount < maxSearch) {
      final checkValue = map[checkKey];
      final checkIsNil =
          checkValue == null || (checkValue is Value && checkValue.raw == null);

      if (checkIsNil) {
        Logger.debug(
          "_getTableLength: Found boundary at $boundary",
          category: 'Table',
        );
        break;
      }

      boundary = checkKey;
      checkKey = NumberUtils.add(checkKey, 1);
      searchCount++;
    }

    length = boundary;
  }

  final result = NumberUtils.toInt(length);
  Logger.debug("_getTableLength: Final result: $result", category: 'Table');
  return result;
}

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
    // Lua: table.insert(table, [pos,] value)
    final nArgs = args.length;
    if (nArgs != 2 && nArgs != 3) {
      throw LuaError("wrong number of arguments to 'insert'");
    }
    final table = args[0] is Value ? args[0] as Value : Value(args[0]);
    checktab(
      table,
      TablePermission.read | TablePermission.write | TablePermission.length,
    );
    final map = table.raw as Map;

    // Check if table has a __len metamethod that returns non-integer
    if (table.metatable != null) {
      final lenMetamethod = table.metatable!['__len'];
      if (lenMetamethod != null) {
        try {
          final lenResult = lenMetamethod.call([table]);
          if (lenResult is Value) {
            final lenValue = lenResult.raw;
            Logger.debug(
              "getTableLength: lenValue = $lenValue, type = ${lenValue.runtimeType}",
            );
            if (lenValue is! int && lenValue is! BigInt) {
              throw LuaError("object length is not an integer");
            }
          } else if (lenResult is! int && lenResult is! BigInt) {
            throw LuaError("object length is not an integer");
          }
        } catch (e) {
          // If the metamethod throws an error, we should propagate it
          rethrow;
        }
      }
    }

    // Find the array length (aux_getn)
    int e = 0;
    while (map.containsKey(e + 1)) {
      e++;
    }
    final int firstEmpty = e + 1;

    int pos;
    Object? value;
    if (nArgs == 2) {
      // Only table, value: insert at end
      pos = firstEmpty;
      value = args[1];
    } else {
      // table, pos, value
      pos = (args[1] as Value).raw as int;
      value = args[2];
      // Check bounds: 1 <= pos <= firstEmpty
      if (pos < 1 || pos > firstEmpty) {
        throw LuaError("position out of bounds");
      }
      // Move up elements: for (i = firstEmpty; i > pos; i--) t[i] = t[i-1]
      for (var i = firstEmpty; i > pos; i--) {
        map[i] = map[i - 1];
      }
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
    final table = args[0] is Value ? args[0] as Value : Value(args[0]);
    checktab(table, TablePermission.read | TablePermission.write);

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
    final table = args[0] is Value ? args[0] as Value : Value(args[0]);
    checktab(table, TablePermission.read);

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
  Future<Object?> call(List<Object?> args) async {
    Logger.debug("_TableMove: Starting with ${args.length} args");

    if (args.length < 4) {
      throw LuaError.typeError("table.move requires at least 4 arguments");
    }

    // Ensure all arguments are Value objects
    final a1 = args[0] is Value ? args[0] as Value : Value(args[0]);
    Logger.debug("_TableMove: a1 = $a1, type = ${a1.raw.runtimeType}");

    final f = NumberUtils.toInt(
      (args[1] is Value ? args[1] as Value : Value(args[1])).raw,
    );
    final e = NumberUtils.toInt(
      (args[2] is Value ? args[2] as Value : Value(args[2])).raw,
    );
    final t = NumberUtils.toInt(
      (args[3] is Value ? args[3] as Value : Value(args[3])).raw,
    );
    final a2 = args.length > 4
        ? (args[4] is Value ? args[4] as Value : Value(args[4]))
        : a1;

    Logger.debug("_TableMove: f=$f, e=$e, t=$t, a2=$a2");
    Logger.debug(
      "_TableMove: maxI=${NumberLimits.maxInteger}, minI=${NumberLimits.minInteger}",
    );

    Logger.debug("_TableMove: About to checktab a1");
    checktab(a1, TablePermission.read);
    Logger.debug("_TableMove: About to checktab a2");
    checktab(a2, TablePermission.write);
    Logger.debug("_TableMove: checktab completed");

    if (e >= f) {
      /* otherwise, nothing to move */
      // Check for "too many elements to move" (Lua C implementation logic)
      // luaL_argcheck(L, f > 0 || e < LUA_MAXINTEGER + f, 3, "too many elements to move");
      if (NumberUtils.compare(f, 0) <= 0 &&
          NumberUtils.compare(e, NumberUtils.add(NumberLimits.maxInteger, f)) >=
              0) {
        throw LuaError(
          "bad argument #3 to 'table.move' (too many elements to move)",
        );
      }

      // Calculate n = e - f + 1
      final n = NumberUtils.add(NumberUtils.subtract(e, f), 1);

      // Check for "destination wrap around"
      final maxDest = NumberUtils.add(
        NumberLimits.maxInteger,
        NumberUtils.subtract(1, n),
      );
      if (NumberUtils.compare(t, maxDest) > 0) {
        throw LuaError("destination wrap around");
      }

      // Determine direction of movement
      if (t > e || t <= f || (a1 != a2)) {
        // Move in increasing order (left to right)
        for (var i = 0; NumberUtils.compare(i, n) < 0; i++) {
          final srcIndex = NumberUtils.add(f, i);
          final destIndex = NumberUtils.add(t, i);
          Logger.debug(
            "_TableMove: i=$i, srcIndex=$srcIndex, destIndex=$destIndex",
          );
          // Use proper table access that respects metamethods and awaits Future results
          var value = await a1.getValueAsync(Value(srcIndex));
          // Handle null values properly - convert to Value(null)
          final valueToStore = value is Value ? value : Value(value);
          Logger.debug(
            "_TableMove: writing value=$valueToStore to destIndex=$destIndex",
          );
          // Use proper table assignment that respects __newindex metamethod and awaits Future results
          await a2.setValueAsync(Value(destIndex), valueToStore);
        }
      } else {
        // Move in decreasing order (right to left) to avoid overwriting
        for (
          var i = NumberUtils.subtract(n, 1);
          NumberUtils.compare(i, 0) >= 0;
          i--
        ) {
          final srcIndex = NumberUtils.add(f, i);
          final destIndex = NumberUtils.add(t, i);
          // Use proper table access that respects metamethods and awaits Future results
          var value = await a1.getValueAsync(Value(srcIndex));
          // Handle null values properly - convert to Value(null)
          final valueToStore = value is Value ? value : Value(value);
          // Use proper table assignment that respects __newindex metamethod and awaits Future results
          await a2.setValueAsync(Value(destIndex), valueToStore);
        }
      }
    }

    return a2; /* return destination table */
  }
}

class _TableSort implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("table.sort requires a table argument");
    }

    final table = args[0] is Value ? args[0] as Value : Value(args[0]);
    checktab(table, TablePermission.read | TablePermission.write);

    final map = table.raw as Map;
    final comp = args.length > 1 ? args[1] : null;

    // Check for "array too big" (from C implementation)
    // luaL_argcheck(L, n < INT_MAX, 1, "array too big");
    // First check the table length using __len metamethod if available
    try {
      final tableLength = await getTableLength(table, context: "table.sort");
      if (tableLength >= NumberLimits.maxInt32) {
        throw LuaError("bad argument #1 to 'table.sort' (array too big)");
      }
    } catch (e) {
      // If getTableLength throws an error (like "object length is not an integer"),
      // we should check if it's because the length is too large
      if (e is LuaError &&
          e.message.contains("object length is not an integer")) {
        // Check if the table has a __len metamethod that returns a large value
        if (table.metatable != null) {
          final lenMetamethod = table.metatable!['__len'];
          if (lenMetamethod != null) {
            try {
              final lenResult = lenMetamethod.call([table]);
              if (lenResult is Value) {
                final lenValue = lenResult.raw;
                if (lenValue is BigInt &&
                    lenValue >= BigInt.from(NumberLimits.maxInt32)) {
                  throw LuaError(
                    "bad argument #1 to 'table.sort' (array too big)",
                  );
                }
              } else if (lenResult is BigInt &&
                  lenResult >= BigInt.from(NumberLimits.maxInt32)) {
                throw LuaError(
                  "bad argument #1 to 'table.sort' (array too big)",
                );
              }
            } catch (_) {
              // If the metamethod call fails, rethrow the original error
              rethrow;
            }
          }
        }
      }
      // Rethrow the original error
      rethrow;
    }

    // Get the array part of the table (numeric indices)
    final keys = map.keys.where((k) => k is int && k >= 1).toList()..sort();
    if (keys.isEmpty) {
      return Value(null);
    }

    // Get the maximum array index
    final maxIndex = keys.last as int;

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
  Object? call(List<Object?> args) async {
    Logger.debug("_TableUnpack: Starting unpack with ${args.length} args");

    if (args.isEmpty) {
      throw LuaError.typeError("table.unpack requires a table argument");
    }

    final table = args[0] is Value ? args[0] as Value : Value(args[0]);
    checktab(table, TablePermission.read);
    final map = table.raw as Map;
    Logger.debug("_TableUnpack: Got table with ${map.length} entries");

    int i, j;

    // Handle start index (default to 1)
    if (args.length > 1) {
      final startArg = args[1] as Value;
      Logger.debug(
        "_TableUnpack: Start arg raw value: ${startArg.raw}, type: ${startArg.raw.runtimeType}",
      );
      if (startArg.raw == null) {
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected, got nil)",
        );
      }
      try {
        i = NumberUtils.toInt(startArg.raw);
        Logger.debug(
          "_TableUnpack: Converted start index to: $i, type: ${i.runtimeType}",
        );
      } catch (e) {
        Logger.debug("_TableUnpack: Error converting start index: $e");
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected)",
        );
      }
    } else {
      i = 1;
      Logger.debug("_TableUnpack: Using default start index: $i");
    }

    // Handle end index (default to table length using Lua semantics)
    if (args.length > 2) {
      final endArg = args[2] as Value;
      Logger.debug(
        "_TableUnpack: End arg raw value: ${endArg.raw}, type: ${endArg.raw.runtimeType}",
      );
      if (endArg.raw == null) {
        // nil means use table length (same as not providing the argument)
        Logger.debug("_TableUnpack: End arg is nil, getting table length");
        j = await getTableLength(table, context: null);
      } else {
        try {
          j = NumberUtils.toInt(endArg.raw);
          Logger.debug(
            "_TableUnpack: Converted end index to: $j, type: ${j.runtimeType}",
          );
        } catch (e) {
          Logger.debug("_TableUnpack: Error converting end index: $e");
          throw LuaError.typeError(
            "bad argument #3 to 'unpack' (number expected)",
          );
        }
      }
    } else {
      Logger.debug("_TableUnpack: No end arg, getting table length");
      j = await getTableLength(table, context: null);
    }

    Logger.debug(
      "_TableUnpack: i=$i (${i.runtimeType}), j=$j (${j.runtimeType})",
    );

    // Check for empty range
    if (i > j) {
      Logger.debug("_TableUnpack: Empty range (i > j), returning nil");
      return Value(null);
    }

    // Check for "too many results to unpack"
    // Use NumberUtils for safe arithmetic operations
    Logger.debug("_TableUnpack: Calculating n = j - i + 1");

    // Calculate n = j - i + 1 using NumberUtils to handle overflow
    // Ensure consistent types by converting constants to BigInt when needed
    final diff = NumberUtils.subtract(j, i);
    Logger.debug("_TableUnpack: diff = $diff (${diff.runtimeType})");
    final n = NumberUtils.add(diff, 1);
    Logger.debug("_TableUnpack: n = $n (${n.runtimeType})");

    // Check if n is valid (positive and not too large)
    Logger.debug("_TableUnpack: Checking if n is valid");
    final nCompare0 = NumberUtils.compare(n, 0);
    Logger.debug("_TableUnpack: n compare 0: $nCompare0");
    final nCompareMax = NumberUtils.compare(n, NumberLimits.maxInt32);
    Logger.debug("_TableUnpack: n compare maxInt32: $nCompareMax");

    if (nCompare0 < 0 || nCompareMax >= 0) {
      Logger.debug("_TableUnpack: n is invalid, throwing error");
      throw LuaError("too many results to unpack");
    }

    Logger.debug("_TableUnpack: n is valid, starting loop");
    final result = <Value>[];

    // Use NumberUtils for safe loop iteration
    var k = i;
    Logger.debug("_TableUnpack: Starting loop with k=$k (${k.runtimeType})");
    while (NumberUtils.compare(k, j) <= 0) {
      Logger.debug("_TableUnpack: Loop iteration, k=$k, j=$j");
      final v = map[k];
      if (v == null || (v is Value && v.raw == null)) {
        result.add(Value(null));
      } else {
        result.add(v is Value ? v : Value(v));
      }

      // Use NumberUtils for safe increment
      if (k == NumberLimits.maxInteger) {
        Logger.debug("_TableUnpack: k reached maxInteger, breaking");
        break; // Can't increment further
      }
      k = NumberUtils.add(k, 1);
      Logger.debug("_TableUnpack: Incremented k to: $k (${k.runtimeType})");
    }

    if (result.isEmpty) return Value.multi([]);
    if (result.length == 1) return result[0];
    return Value.multi(result);
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
