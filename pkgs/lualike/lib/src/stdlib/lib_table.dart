import 'package:lualike/lualike.dart';

import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/type.dart';
import 'library.dart';

import '../number_limits.dart';

/// Table library implementation using the new Library system
class TableLibrary extends Library {
  @override
  String get name => "table";

  @override
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => {
    "__index": (List<Object?> args) {
      final _ = args[0] as Value;
      final key = args[1] as Value;

      // Convert key to string if needed
      final keyStr = key.raw is String ? key.raw as String : key.toString();

      // Return the function from our registry if it exists
      switch (keyStr) {
        case "concat":
          return _TableConcat();
        case "insert":
          return _TableInsert();
        case "move":
          return _TableMove();
        case "pack":
          return _TablePack();
        case "remove":
          return _TableRemove();
        case "sort":
          return _TableSort();
        case "unpack":
          return _TableUnpack();
        default:
          return Value(null);
      }
    },
  };

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all table functions directly
    context.define("insert", _TableInsert());
    context.define("remove", _TableRemove());
    context.define("concat", _TableConcat());
    context.define("move", _TableMove());
    context.define("pack", _TablePack());
    context.define("sort", _TableSort());
    context.define("unpack", _TableUnpack());
  }
}

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
        hasRequired = hasRequired && table.hasMetamethod('__index');
      }
      if ((what & TablePermission.write) != 0) {
        hasRequired = hasRequired && table.hasMetamethod('__newindex');
      }
      if ((what & TablePermission.length) != 0) {
        hasRequired = hasRequired && table.hasMetamethod('__len');
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
  if (table.hasMetamethod('__len')) {
    try {
      final lenResult = await table.callMetamethodAsync('__len', [table]);
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
              throw LuaError("bad argument #1 to 'table.sort' (array too big)");
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
              throw LuaError("bad argument #1 to 'table.sort' (array too big)");
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

  // No __len metamethod, use regular table length calculation
  return switch (table.raw) {
    final TableStorage storage => storage.highestPositiveIntegerKey(),
    final Map<dynamic, dynamic> map => _getTableLength(map),
    _ => throw LuaError.typeError("table expected"),
  };
}

/// Helper method to calculate table length using Lua semantics
/// This finds the largest integer key n such that t[n] is not nil
/// and t[n+1] is nil
int _getTableLength(Map map) {
  if (map case final TableStorage storage) {
    return storage.highestPositiveIntegerKey();
  }

  var length = 0;

  // Find the largest integer key with a non-nil value
  for (final MapEntry(key: key, value: value) in map.entries) {
    if (key is int &&
        key > 0 &&
        value != null &&
        !(value is Value && value.raw == null) &&
        NumberUtils.compare(key, length) > 0) {
      length = key;
    }
  }

  // Now check if t[length+1] is nil to confirm the boundary
  final nextKey = NumberUtils.add(length, 1);
  final nextValue = map[nextKey];
  final nextIsNil =
      nextValue == null || (nextValue is Value && nextValue.raw == null);

  // If t[length+1] is not nil, we need to find the actual boundary
  if (!nextIsNil) {
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
        break;
      }

      boundary = checkKey;
      checkKey = NumberUtils.add(checkKey, 1);
      searchCount++;
    }

    length = boundary;
  }

  return NumberUtils.toInt(length);
}

class TableLib {
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

class _TableInsert extends BuiltinFunction {
  _TableInsert() : super();
  @override
  Object? call(List<Object?> args) async {
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

    final int baseLength = await getTableLength(table, context: "table.insert");
    final int firstEmpty = baseLength + 1;

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

class _TableRemove extends BuiltinFunction {
  _TableRemove() : super();
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

class _TableConcat extends BuiltinFunction {
  _TableConcat() : super();
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

class _TableMove extends BuiltinFunction {
  _TableMove() : super();
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

class _TableSort extends BuiltinFunction {
  _TableSort() : super();
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

    final n = await getTableLength(table, context: "table.sort");
    if (n >= NumberLimits.maxInt32) {
      throw LuaError("bad argument #1 to 'table.sort' (array too big)");
    }
    if (n <= 1) {
      return Value(null);
    }

    // Validate the order function if provided
    if (_shouldValidateOrderFunction(comp)) {
      await _validateOrderFunction(map, n, comp);
    }

    final primitiveSortDirection = _primitiveSortDirection(comp);
    if (primitiveSortDirection != 0 &&
        _trySortPrimitiveArray(map, n, primitiveSortDirection)) {
      return Value(null);
    }

    // Perform in-place quicksort using Lua's algorithm
    await _auxSort(map, 1, n, comp, 0);

    return Value(null);
  }

  int _primitiveSortDirection(Object? comp) => switch (comp) {
    null => 1,
    Value(raw: null) => 1,
    Value(isLessComparator: true) => 1,
    Value(isLessComparatorReversed: true) => -1,
    _ => 0,
  };

  bool _shouldValidateOrderFunction(Object? comp) => switch (comp) {
    null => false,
    Value(raw: null) => false,
    Value(isCountedLessComparator: true) => false,
    Value(isCountedLessComparatorReversed: true) => false,
    Value(isLessComparator: true) => false,
    Value(isLessComparatorReversed: true) => false,
    Value(isNilReturningClosure: true) => false,
    _ => true,
  };

  bool _trySortPrimitiveArray(Map map, int n, int direction) {
    List<num>? numericValues = <num>[];
    List<String>? stringValues = <String>[];

    for (var i = 1; i <= n; i++) {
      final cell = map[i];
      if (cell is Value && cell.metatable != null) {
        return false;
      }

      final raw = cell is Value ? cell.raw : cell;
      switch (raw) {
        case num value when stringValues != null:
          stringValues = null;
          numericValues?.add(value);
        case String() || LuaString():
          numericValues = null;
          stringValues?.add(raw.toString());
        default:
          return false;
      }

      if (numericValues == null && stringValues == null) {
        return false;
      }
    }

    if (numericValues != null) {
      Logger.debugLazy(
        () => 'table.sort fast path (numeric) length=$n direction=$direction',
        category: 'TableSort',
      );
      numericValues.sort((a, b) => a.compareTo(b));
      _writeSortedValues(map, numericValues, direction);
      return true;
    }

    if (stringValues != null) {
      Logger.debugLazy(
        () => 'table.sort fast path (string) length=$n direction=$direction',
        category: 'TableSort',
      );
      stringValues.sort();
      _writeSortedValues(map, stringValues, direction);
      return true;
    }

    return false;
  }

  void _writeSortedValues<T>(Map map, List<T> values, int direction) {
    for (var i = 1; i <= values.length; i++) {
      final sortedValue = direction > 0
          ? values[i - 1]
          : values[values.length - i];
      final original = map[i];
      if (original is Value) {
        original.raw = sortedValue;
        map[i] = original;
      } else {
        map[i] = sortedValue;
      }
    }
  }

  // Simple in-place quicksort implementation
  Future<void> _auxSort(Map map, int lo, int up, Object? comp, int rnd) async {
    Logger.debugLazy(
      () => "_auxSort: lo=$lo, up=$up",
      category: 'TableSort',
    );

    if (lo >= up) {
      Logger.debugLazy(
        () => "_auxSort: base case reached",
        category: 'TableSort',
      );
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
        Logger.debugLazy(
          () =>
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
      Logger.debugLazy(
        () => "_auxSort: using insertion sort for small array",
        category: 'TableSort',
      );
      await _insertionSort(map, lo, up, comp);
      return;
    }

    // Choose pivot (middle element)
    int pivot = (lo + up) ~/ 2;
    Logger.debugLazy(
      () => "_auxSort: chosen pivot at index $pivot",
      category: 'TableSort',
    );

    // Move pivot to end
    _set2(map, pivot, up);

    // Partition
    int i = lo - 1;
    for (int j = lo; j < up; j++) {
      final compResult = await _sortComp(map, j, up, comp);
      Logger.debugLazy(
        () => "_auxSort: comparing indices $j and $up, result=$compResult",
        category: 'TableSort',
      );
      if (compResult) {
        i++;
        _set2(map, i, j);
        Logger.debugLazy(
          () => "_auxSort: swapped elements at indices $i and $j",
          category: 'TableSort',
        );
      }
    }

    // Move pivot to correct position
    _set2(map, i + 1, up);
    pivot = i + 1;
    Logger.debugLazy(
      () => "_auxSort: pivot moved to position $pivot",
      category: 'TableSort',
    );

    // Handle degenerate case: if pivot is at the beginning or end,
    // we need to ensure progress to avoid infinite recursion
    if (pivot <= lo) {
      Logger.debugLazy(
        () => "_auxSort: degenerate case - pivot at beginning, sorting rest",
        category: 'TableSort',
      );
      // Pivot is at the beginning, sort the rest
      await _auxSort(map, lo + 1, up, comp, rnd);
    } else if (pivot >= up) {
      Logger.debugLazy(
        () => "_auxSort: degenerate case - pivot at end, sorting rest",
        category: 'TableSort',
      );
      // Pivot is at the end, sort the rest
      await _auxSort(map, lo, up - 1, comp, rnd);
    } else {
      Logger.debugLazy(
        () => "_auxSort: normal case - sorting left and right parts",
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
        Logger.debugLazy(
          () => "_insertionSort: should swap? j=$j, result=true",
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

    Logger.debugLazy(
      () =>
          "_sortComp: comparing indices a=$a (${valA.runtimeType}) with b=$b (${valB.runtimeType})",
      category: 'TableSort',
    );

    bool? fastLessThan(dynamic lhs, dynamic rhs) {
      final left = lhs is Value ? lhs.raw : lhs;
      final right = rhs is Value ? rhs.raw : rhs;

      if (left is num && right is num) {
        return left < right;
      }
      if ((left is String || left is LuaString) &&
          (right is String || right is LuaString)) {
        final ls = left.toString();
        final rs = right.toString();
        return ls.compareTo(rs) < 0;
      }

      return null;
    }

    // If either value is nil, raise an error (Lua behavior)
    if (valA == null ||
        (valA is Value && valA.raw == null) ||
        valB == null ||
        (valB is Value && valB.raw == null)) {
      throw LuaError.typeError("attempt to compare nil value");
    }

    if (comp == null || (comp is Value && comp.raw == null)) {
      // no function?

      // Fast path: number/number or string/string (including LuaString) comparisons
      final aVal = valA is Value ? (valA).raw : valA;
      final bVal = valB is Value ? (valB).raw : valB;
      if (aVal is num && bVal is num) {
        final res = aVal < bVal;
        Logger.debugLazy(
          () => "_sortComp (fast num): $aVal < $bVal => $res",
          category: 'TableSort',
        );
        return res;
      }
      if ((aVal is String || aVal is LuaString) &&
          (bVal is String || bVal is LuaString)) {
        final aStr = aVal.toString();
        final bStr = bVal.toString();
        final res = aStr.compareTo(bStr) < 0;
        Logger.debugLazy(
          () => "_sortComp (fast str): '$aStr' < '$bStr' => $res",
          category: 'TableSort',
        );
        return res;
      }

      final result = await _compareValues(valA, valB) < 0; // a < b
      Logger.debugLazy(
        () => "_sortComp: result = $result",
        category: 'TableSort',
      );
      return result;
    } else {
      // function
      if (comp is Value &&
          (comp.raw is Function || comp.raw is BuiltinFunction)) {
        if (comp.isNilReturningClosure) {
          return false;
        }

        if (comp.isCountedLessComparator ||
            comp.isCountedLessComparatorReversed) {
          final fast = comp.isCountedLessComparator
              ? fastLessThan(valA, valB)
              : fastLessThan(valB, valA);
          if (fast != null) {
            _incrementComparatorCounter(comp);
            Logger.debugLazy(
              () => "_sortComp: counted comparator fast result = $fast",
              category: 'TableSort',
            );
            return fast;
          }
        }

        if (comp.isLessComparator || comp.isLessComparatorReversed) {
          final fast = comp.isLessComparator
              ? fastLessThan(valA, valB)
              : fastLessThan(valB, valA);
          if (fast != null) {
            Logger.debugLazy(
              () => "_sortComp: comparator hint fast result = $fast",
              category: 'TableSort',
            );
            return fast;
          }
        }

        final func = comp.raw;
        final result = await func([valA, valB]);
        final boolResult = result is Value
            ? result.raw == true
            : result == true;
        Logger.debugLazy(
          () => "_sortComp: result = $boolResult",
          category: 'TableSort',
        );
        return boolResult;
      } else {
        throw LuaError("invalid order function");
      }
    }
  }

  void _incrementComparatorCounter(Value comparator) {
    final counterBox = comparator.comparatorCounterBox;
    if (counterBox == null) {
      return;
    }

    final current = counterBox.value;
    switch (current) {
      case Value(raw: final int value):
        current.raw = value + 1;
      case Value(raw: final double value):
        current.raw = value + 1;
      case Value(raw: final BigInt value):
        current.raw = value + BigInt.one;
      case final Value wrapped:
        final raw = wrapped.raw;
        if (raw is num) {
          wrapped.raw = raw + 1;
        } else if (raw is BigInt) {
          wrapped.raw = raw + BigInt.one;
        }
      case final int value:
        counterBox.value = value + 1;
      case final double value:
        counterBox.value = value + 1;
      case final BigInt value:
        counterBox.value = value + BigInt.one;
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
    Logger.debugLazy(
      () =>
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
      // Check for metamethods using the unified Value API
      final aValue = a is Value ? a : Value(a);
      final bValue = b is Value ? b : Value(b);

      // Prefer __lt from 'a'
      if (aValue.hasMetamethod('__lt')) {
        try {
          final result = await aValue.callMetamethodAsync('__lt', [
            aValue,
            bValue,
          ]);
          final boolRes = result is Value
              ? (result.raw == true)
              : (result == true);
          return boolRes ? -1 : 1;
        } catch (e) {
          Logger.debugLazy(
            () => "_compareValues: __lt metamethod failed for a: $e",
            category: 'TableSort',
          );
        }
      }

      // Try __lt from 'b' (reverse)
      if (bValue.hasMetamethod('__lt')) {
        try {
          final result = await bValue.callMetamethodAsync('__lt', [
            bValue,
            aValue,
          ]);
          final boolRes = result is Value
              ? (result.raw == true)
              : (result == true);
          return boolRes ? 1 : -1;
        } catch (e) {
          Logger.debugLazy(
            () => "_compareValues: __lt metamethod failed for b: $e",
            category: 'TableSort',
          );
        }
      }

      // No metamethods available
      throw LuaError.typeError("attempt to compare incompatible types");
    }
  }

  // Swap two elements in the map
  void _set2(Map map, int i, int j) {
    Logger.debugLazy(
      () => "_set2: swapping elements at indices $i and $j",
      category: 'TableSort',
    );
    final temp = map[i];
    map[i] = map[j];
    map[j] = temp;
  }

  // Partition function (similar to C implementation)
}

class _TablePack extends BuiltinFunction {
  _TablePack() : super();
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

class _TableUnpack extends BuiltinFunction {
  _TableUnpack() : super();
  @override
  Object? call(List<Object?> args) async {
    final bool log = Logger.enabled;
    if (log) {
      Logger.debug("_TableUnpack: Starting unpack with ${args.length} args");
    }

    if (args.isEmpty) {
      throw LuaError.typeError("table.unpack requires a table argument");
    }

    final table = args[0] is Value ? args[0] as Value : Value(args[0]);
    checktab(table, TablePermission.read);
    final map = table.raw as Map;
    if (log) {
      Logger.debug("_TableUnpack: Got table with ${map.length} entries");
    }

    int i, j;

    // Handle start index (default to 1)
    if (args.length > 1) {
      final startArg = args[1] as Value;
      if (log) {
        Logger.debug(
          "_TableUnpack: Start arg raw value: ${startArg.raw}, type: ${startArg.raw.runtimeType}",
        );
      }
      if (startArg.raw == null) {
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected, got nil)",
        );
      }
      try {
        i = NumberUtils.toInt(startArg.raw);
        if (log) {
          Logger.debug(
            "_TableUnpack: Converted start index to: $i, type: ${i.runtimeType}",
          );
        }
      } catch (e) {
        if (log) {
          Logger.debug("_TableUnpack: Error converting start index: $e");
        }
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected)",
        );
      }
    } else {
      i = 1;
      if (log) {
        Logger.debug("_TableUnpack: Using default start index: $i");
      }
    }

    // Handle end index (default to table length using Lua semantics)
    if (args.length > 2) {
      final endArg = args[2] as Value;
      if (log) {
        Logger.debug(
          "_TableUnpack: End arg raw value: ${endArg.raw}, type: ${endArg.raw.runtimeType}",
        );
      }
      if (endArg.raw == null) {
        // nil means use table length (same as not providing the argument)
        if (log) {
          Logger.debug("_TableUnpack: End arg is nil, getting table length");
        }
        j = await getTableLength(table, context: null);
      } else {
        try {
          j = NumberUtils.toInt(endArg.raw);
          if (log) {
            Logger.debug(
              "_TableUnpack: Converted end index to: $j, type: ${j.runtimeType}",
            );
          }
        } catch (e) {
          if (log) {
            Logger.debug("_TableUnpack: Error converting end index: $e");
          }
          throw LuaError.typeError(
            "bad argument #3 to 'unpack' (number expected)",
          );
        }
      }
    } else {
      if (log) {
        Logger.debug("_TableUnpack: No end arg, getting table length");
      }
      j = await getTableLength(table, context: null);
    }

    if (log) {
      Logger.debug(
        "_TableUnpack: i=$i (${i.runtimeType}), j=$j (${j.runtimeType})",
      );
    }

    final int start = i;
    final int end = j;
    if (start > end) {
      if (log) {
        Logger.debug(
          "_TableUnpack: Empty range (i > j), returning zero values",
        );
      }
      return Value.multi(<dynamic>[]);
    }

    final BigInt startBig = NumberUtils.toBigInt(start);
    final BigInt endBig = NumberUtils.toBigInt(end);
    final BigInt rawCount = endBig - startBig + BigInt.one;
    if (rawCount.isNegative || rawCount >= BigInt.from(NumberLimits.maxInt32)) {
      if (log) {
        Logger.debug(
          "_TableUnpack: count=$rawCount outside limits, throwing error",
        );
      }
      throw LuaError("too many results to unpack");
    }

    final int count = rawCount.toInt();
    final result = List<Value?>.filled(count, null, growable: false);
    if (map is TableStorage) {
      final storage = map;
      for (var offset = 0; offset < count; offset++) {
        final value = storage.arrayValueAt(start + offset);
        if (value == null) {
          result[offset] = Value(null);
        } else if (value is Value) {
          result[offset] = value;
        } else {
          result[offset] = Value(value);
        }
      }
    } else {
      for (var offset = 0; offset < count; offset++) {
        final value = map[start + offset];
        if (value == null || (value is Value && value.raw == null)) {
          result[offset] = Value(null);
        } else {
          result[offset] = value is Value ? value : Value(value);
        }
      }
    }

    if (count == 0) {
      return Value.multi(<dynamic>[]);
    }
    if (count == 1) {
      return result[0]!;
    }
    return Value.multi(result.cast<Value>());
  }
}
