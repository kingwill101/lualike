import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/utils/type.dart';

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
    // Do not override __len here; '#t' should use Lua's array boundary rule
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

    final arg0 = args[0];
    final table = arg0 is Value ? arg0 : Value(arg0);
    checktab(table, TablePermission.read | TablePermission.write);

    final map = table.raw as Map;
    final comp = args.length > 1 ? args[1] : null;

    // Validate comparison function if provided
    if (comp != null && comp is! Value) {
      throw LuaError(
        "bad argument #2 to 'sort' (function expected, got ${getLuaType(comp)})",
      );
    }
    if (comp is Value &&
        comp.raw != null &&
        comp.raw is! Function &&
        comp.raw is! BuiltinFunction) {
      throw LuaError(
        "bad argument #2 to 'sort' (function expected, got ${getLuaType(comp)})",
      );
    }

    // Check for "array too big" (from C implementation)
    try {
      final tableLength = await getTableLength(table, context: "table.sort");
      if (tableLength >= NumberLimits.maxInt32) {
        throw LuaError("bad argument #1 to 'table.sort' (array too big)");
      }
    } catch (e) {
      if (e is LuaError &&
          e.message.contains("object length is not an integer")) {
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
              rethrow;
            }
          }
        }
      }
      rethrow;
    }

    // Get the array length using Lua semantics
    final n = _getTableLength(map);
    if (n == 0) {
      return Value(null);
    }

    // Validate the order function if provided
    await _validateOrderFunction(map, n, comp);

    // Perform in-place quicksort using Lua's algorithm
    await _auxSort(map, 1, n, comp, 0);

    return Value(null);
  }

  // Simple in-place quicksort implementation
  Future<void> _auxSort(Map map, int lo, int up, Object? comp, int rnd) async {
    Logger.debug("_auxSort: lo=$lo, up=$up", category: 'TableSort');

    if (lo >= up) {
      Logger.debug("_auxSort: base case reached", category: 'TableSort');
      return; // base case
    }

    // Quick check for degenerate case: if comparison function always returns false/nil
    // and we have more than a few elements, use a fast path
    if (up - lo > 5 && comp != null && comp is Value && comp.raw != null) {
      bool alwaysFalse = true;
      // Test a few comparisons to see if they all return false
      for (int i = 0; i < 3 && alwaysFalse; i++) {
        final testResult = await _sortComp(map, lo + i, lo + i + 1, comp);
        if (testResult) {
          alwaysFalse = false;
        }
      }
      if (alwaysFalse) {
        Logger.debug(
          "_auxSort: degenerate case - all comparisons return false, using fast path",
          category: 'TableSort',
        );
        // For degenerate cases, just run a minimal sort to maintain compatibility
        // but use insertion sort which is efficient for this case
        await _insertionSort(map, lo, up, comp);
        return;
      }
    }

    // For small arrays or degenerate cases, use insertion sort
    if (up - lo < 10) {
      Logger.debug(
        "_auxSort: using insertion sort for small array",
        category: 'TableSort',
      );
      await _insertionSort(map, lo, up, comp);
      return;
    }

    // Choose pivot (middle element)
    int pivot = (lo + up) ~/ 2;
    Logger.debug(
      "_auxSort: chosen pivot at index $pivot",
      category: 'TableSort',
    );

    // Move pivot to end
    _set2(map, pivot, up);

    // Partition
    int i = lo - 1;
    for (int j = lo; j < up; j++) {
      final compResult = await _sortComp(map, j, up, comp);
      Logger.debug(
        "_auxSort: comparing indices $j and $up, result=$compResult",
        category: 'TableSort',
      );
      if (compResult) {
        i++;
        _set2(map, i, j);
        Logger.debug(
          "_auxSort: swapped elements at indices $i and $j",
          category: 'TableSort',
        );
      }
    }

    // Move pivot to correct position
    _set2(map, i + 1, up);
    pivot = i + 1;
    Logger.debug(
      "_auxSort: pivot moved to position $pivot",
      category: 'TableSort',
    );

    // Handle degenerate case: if pivot is at the beginning or end,
    // we need to ensure progress to avoid infinite recursion
    if (pivot <= lo) {
      Logger.debug(
        "_auxSort: degenerate case - pivot at beginning, sorting rest",
        category: 'TableSort',
      );
      // Pivot is at the beginning, sort the rest
      await _auxSort(map, lo + 1, up, comp, rnd);
    } else if (pivot >= up) {
      Logger.debug(
        "_auxSort: degenerate case - pivot at end, sorting rest",
        category: 'TableSort',
      );
      // Pivot is at the end, sort the rest
      await _auxSort(map, lo, up - 1, comp, rnd);
    } else {
      Logger.debug(
        "_auxSort: normal case - sorting left and right parts",
        category: 'TableSort',
      );
      // Normal case: recursively sort left and right parts
      await _auxSort(map, lo, pivot - 1, comp, rnd);
      await _auxSort(map, pivot + 1, up, comp, rnd);
    }
  }

  // Insertion sort for small arrays or degenerate cases
  Future<void> _insertionSort(Map map, int lo, int up, Object? comp) async {
    for (int i = lo + 1; i <= up; i++) {
      for (int j = i; j > lo && await _sortComp(map, j, j - 1, comp); j--) {
        Logger.debug(
          "_insertionSort: should swap? j=$j, result=true",
          category: 'TableSort',
        );
        _set2(map, j, j - 1);
      }
    }
  }

  // Return true iff value at index 'a' is less than the value at index 'b'
  Future<bool> _sortComp(Map map, int a, int b, Object? comp) async {
    final valA = map[a];
    final valB = map[b];

    Logger.debug(
      "_sortComp: comparing indices a=$a (${valA.runtimeType}) with b=$b (${valB.runtimeType})",
      category: 'TableSort',
    );

    // If either value is nil, raise an error (Lua behavior)
    if (valA == null ||
        (valA is Value && valA.raw == null) ||
        valB == null ||
        (valB is Value && valB.raw == null)) {
      throw LuaError.typeError("attempt to compare nil value");
    }

    if (comp == null || (comp is Value && comp.raw == null)) {
      // no function?
      final result = await _compareValues(valA, valB) < 0; // a < b
      Logger.debug("_sortComp: result = $result", category: 'TableSort');
      return result;
    } else {
      // function
      if (comp is Value &&
          (comp.raw is Function || comp.raw is BuiltinFunction)) {
        final func = comp.raw;
        final result = await func([valA, valB]);
        final boolResult = result is Value
            ? result.raw == true
            : result == true;
        Logger.debug("_sortComp: result = $boolResult", category: 'TableSort');
        return boolResult;
      } else {
        throw LuaError("invalid order function");
      }
    }
  }

  // Validate that the comparison function provides a consistent ordering
  Future<void> _validateOrderFunction(Map map, int n, Object? comp) async {
    if (comp == null || n < 2) return;

    if (comp is Value &&
        (comp.raw is Function || comp.raw is BuiltinFunction)) {
      final func = comp.raw;

      // Test the function with a few pairs to detect obvious issues
      bool? firstResult;
      int testCount = 0;
      final maxTests = n < 10 ? n : 10; // Test up to 10 pairs or all if n < 10

      for (int i = 1; i < maxTests; i++) {
        final valA = map[i];
        final valB = map[i + 1];

        if (valA != null && valB != null) {
          final result = await func([valA, valB]);
          final boolResult = result is Value
              ? result.raw == true
              : result == true;

          if (firstResult == null) {
            firstResult = boolResult;
          } else if (boolResult != firstResult) {
            // Function returns different values, so it's not always the same
            return;
          }

          testCount++;
        }
      }

      // Only reject if the function always returns true (which would make all elements equal)
      // Functions that always return false or nil are valid (they just don't change the order)
      if (testCount >= 2 && firstResult == true) {
        // Test one more pair in reverse order to confirm
        final valA = map[2];
        final valB = map[1];

        if (valA != null && valB != null) {
          final result = await func([valA, valB]);
          final boolResult = result is Value
              ? result.raw == true
              : result == true;

          if (boolResult == true) {
            // Function always returns true regardless of order
            throw LuaError("invalid order function");
          }
        }
      }
    }
  }

  // Compare two values using Lua semantics
  Future<int> _compareValues(dynamic a, dynamic b) async {
    // Handle nil values - this should prevent metamethods from being called with nil
    if (a == null || (a is Value && a.raw == null)) {
      throw LuaError.typeError("attempt to compare nil value");
    }
    if (b == null || (b is Value && b.raw == null)) {
      throw LuaError.typeError("attempt to compare nil value");
    }

    final aVal = a is Value ? a.raw : a;
    final bVal = b is Value ? b.raw : b;

    // Additional nil check after unwrapping
    if (aVal == null || bVal == null) {
      throw LuaError.typeError("attempt to compare nil value");
    }

    // Debug logging
    Logger.debug(
      "_compareValues: comparing a=$a (${a.runtimeType}) with b=$b (${b.runtimeType})",
      category: 'TableSort',
    );

    if (aVal is num && bVal is num) {
      return aVal.compareTo(bVal);
    } else if ((aVal is String || aVal is LuaString) &&
        (bVal is String || bVal is LuaString)) {
      // Convert both to strings for comparison
      final aStr = aVal.toString();
      final bStr = bVal.toString();
      return aStr.compareTo(bStr);
    } else {
      // Check for metamethods
      final aValue = a is Value ? a : Value(a);
      final bValue = b is Value ? b : Value(b);

      // Try to use __lt metamethod from a
      if (aValue.metatable != null) {
        final ltMetamethod = aValue.metatable!.raw['__lt'];
        if (ltMetamethod != null) {
          try {
            final result = await ltMetamethod.call([aValue, bValue]);
            Logger.debug(
              "_compareValues: __lt metamethod result: $result (${result.runtimeType})",
              category: 'TableSort',
            );
            if (result is Value) {
              final boolResult = result.raw == true ? -1 : 1;
              Logger.debug(
                "_compareValues: returning $boolResult (Value case)",
                category: 'TableSort',
              );
              return boolResult;
            } else {
              final boolResult = result == true ? -1 : 1;
              Logger.debug(
                "_compareValues: returning $boolResult (direct case)",
                category: 'TableSort',
              );
              return boolResult;
            }
          } catch (e) {
            Logger.debug(
              "_compareValues: __lt metamethod failed for a: $e",
              category: 'TableSort',
            );
            // If __lt metamethod fails, try the reverse
            if (bValue.metatable != null) {
              final bLtMetamethod = bValue.metatable!.raw['__lt'];
              if (bLtMetamethod != null) {
                try {
                  final result = await bLtMetamethod.call([bValue, aValue]);
                  if (result is Value) {
                    return result.raw == true ? 1 : -1;
                  } else {
                    return result == true ? 1 : -1;
                  }
                } catch (e) {
                  Logger.debug(
                    "_compareValues: __lt metamethod failed for b: $e",
                    category: 'TableSort',
                  );
                  // Both metamethods failed
                }
              }
            }
          }
        }
      }

      // Try to use __lt metamethod from b
      if (bValue.metatable != null) {
        final ltMetamethod = bValue.metatable!.raw['__lt'];
        if (ltMetamethod != null) {
          try {
            final result = await ltMetamethod.call([bValue, aValue]);
            if (result is Value) {
              return result.raw == true ? 1 : -1;
            } else {
              return result == true ? 1 : -1;
            }
          } catch (e) {
            Logger.debug(
              "_compareValues: __lt metamethod failed for b (second attempt): $e",
              category: 'TableSort',
            );
            // Metamethod failed
          }
        }
      }

      throw LuaError.typeError("attempt to compare incompatible types");
    }
  }

  // Swap two elements in the map
  void _set2(Map map, int i, int j) {
    Logger.debug(
      "_set2: swapping elements at indices $i and $j",
      category: 'TableSort',
    );
    final temp = map[i];
    map[i] = map[j];
    map[j] = temp;
  }

  // Partition function (similar to C implementation)
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
