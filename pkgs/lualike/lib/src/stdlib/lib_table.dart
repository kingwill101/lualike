import 'dart:typed_data';

import 'package:lualike/lualike.dart';

import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/runtime_hints.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/type.dart';
import 'library.dart';

import '../number_limits.dart';

bool _isNilTableValue(Object? value) => rawLuaSlot(value) == null;

bool _isTrueTableValue(Object? value) => rawLuaSlot(value) == true;

/// Table library implementation using the new Library system
class TableLibrary extends Library {
  @override
  String get name => "table";

  @override
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => {
    "__index": (List<Object?> args) {
      final key = args[1];

      // Convert key to string if needed
      final rawKey = rawLuaSlot(key);
      final keyStr = rawKey is String ? rawKey : key.toString();

      // Return the function from our registry if it exists
      switch (keyStr) {
        case "concat":
          return _TableConcat(interpreter);
        case "create":
          return _TableCreate(interpreter);
        case "insert":
          return _TableInsert(interpreter);
        case "move":
          return _TableMove(interpreter);
        case "pack":
          return _TablePack(interpreter);
        case "remove":
          return _TableRemove(interpreter);
        case "sort":
          return _TableSort(interpreter);
        case "unpack":
          return _TableUnpack(interpreter);
        default:
          return interpreter.constantPrimitiveValue(null);
      }
    },
  };

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final interpreter = context.vm;
    // Register all table functions directly
    context.define("insert", _TableInsert(interpreter));
    context.define("remove", _TableRemove(interpreter));
    context.define("concat", _TableConcat(interpreter));
    context.define("create", _TableCreate(interpreter));
    context.define("move", _TableMove(interpreter));
    context.define("pack", _TablePack(interpreter));
    context.define("sort", _TableSort(interpreter));
    context.define("unpack", _TableUnpack(interpreter));
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
  if (rawLuaSlot(table) is! Map) {
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
      Logger.debugLazy(
        () =>
            "getTableLength: lenResult = $lenResult, type = ${lenResult.runtimeType}",
      );
      final lenValue = rawLuaSlot(lenResult);
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
    } catch (e) {
      // If the metamethod throws an error, we should propagate it
      rethrow;
    }
  }

  // No __len metamethod, use regular table length calculation
  return switch (rawLuaSlot(table)) {
    final TableStorage storage => storage.luaLengthBoundary(),
    final Map<dynamic, dynamic> map => _getTableLength(map),
    _ => throw LuaError.typeError("table expected"),
  };
}

/// Helper method to calculate table length using Lua semantics
/// This finds the largest integer key n such that t[n] is not nil
/// and t[n+1] is nil
int _getTableLength(Map map) {
  if (map case final TableStorage storage) {
    return storage.luaLengthBoundary();
  }
  return luaTableLengthFromMap(map.cast<dynamic, dynamic>());
}

Value _wrapTableLibraryValue(LuaRuntime? runtime, Object? value) {
  return cachedPrimitiveOrValue(runtime, value);
}

Future<Value> _tableSequenceReadAsync(
  Value table,
  int index, {
  LuaRuntime? runtime,
}) async {
  final value = await table.getValueAsync(index);
  return _wrapTableLibraryValue(table.interpreter ?? runtime, value);
}

Future<void> _tableSequenceWriteAsync(
  Value table,
  int index,
  Object? value, {
  LuaRuntime? runtime,
}) {
  final wrapped = _wrapTableLibraryValue(table.interpreter ?? runtime, value);
  return table.setValueAsync(index, wrapped);
}

class TableLib {
  static final Map<String, BuiltinFunction> functions = {
    "insert": _TableInsert(),
    "remove": _TableRemove(),
    "concat": _TableConcat(),
    "create": _TableCreate(),
    "move": _TableMove(),
    "pack": _TablePack(),
    "sort": _TableSort(),
    "unpack": _TableUnpack(),
  };
}

class _TableCreate extends BuiltinFunction {
  _TableCreate([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    if (args.length > 2) {
      throw LuaError("wrong number of arguments to 'create'");
    }

    int parseSize(Object? value, String label) {
      final raw = rawLuaSlot(value);
      if (raw == null) {
        return 0;
      }
      if (raw is! num && raw is! BigInt) {
        throw LuaError(
          "bad argument to 'table.create' ($label must be an integer)",
        );
      }
      final sizeBig = NumberUtils.toBigInt(raw);
      if (sizeBig < BigInt.zero) {
        throw LuaError(
          "bad argument to 'table.create' ($label must be non-negative)",
        );
      }
      if (sizeBig > BigInt.from(NumberLimits.maxInt32)) {
        throw LuaError("bad argument to 'table.create' ($label out of range)");
      }
      if (sizeBig == BigInt.from(NumberLimits.maxInt32)) {
        throw LuaError('table overflow');
      }
      return sizeBig.toInt();
    }

    final arraySize = args.isEmpty ? 0 : parseSize(args[0], 'array size');
    final hashSize = args.length < 2 ? 0 : parseSize(args[1], 'hash size');

    final table = TableStorage();
    if (arraySize > 0) {
      table.ensureArrayCapacity(arraySize);
    }
    if (hashSize > 0) {
      table.reserveHashCapacity(hashSize);
    }
    return ValueClass.table(table)..interpreter = interpreter;
  }
}

class _TableInsert extends BuiltinFunction {
  _TableInsert([super.interpreter]);
  @override
  Object? call(List<Object?> args) async {
    // Lua: table.insert(table, [pos,] value)
    final nArgs = args.length;
    if (nArgs != 2 && nArgs != 3) {
      throw LuaError("wrong number of arguments to 'insert'");
    }
    final table = _wrapTableLibraryValue(interpreter, args[0]);
    checktab(
      table,
      TablePermission.read | TablePermission.write | TablePermission.length,
    );
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
      pos = rawLuaSlot(args[1]) as int;
      value = args[2];
      // Check bounds: 1 <= pos <= firstEmpty
      if (pos < 1 || pos > firstEmpty) {
        throw LuaError("position out of bounds");
      }
      // Move up elements: for (i = firstEmpty; i > pos; i--) t[i] = t[i-1]
      for (var i = firstEmpty; i > pos; i--) {
        final shifted = await _tableSequenceReadAsync(
          table,
          i - 1,
          runtime: interpreter,
        );
        await _tableSequenceWriteAsync(table, i, shifted, runtime: interpreter);
      }
    }
    await _tableSequenceWriteAsync(table, pos, value, runtime: interpreter);
    return primitiveValue(null);
  }
}

class _TableRemove extends BuiltinFunction {
  _TableRemove([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("table.remove requires a table argument");
    }
    final table = _wrapTableLibraryValue(interpreter, args[0]);
    checktab(table, TablePermission.read | TablePermission.write);

    final size = await getTableLength(table);
    final pos = args.length > 1 ? rawLuaSlot(args[1]) as int : size;

    if (pos == 0 && size > 0) {
      throw LuaError("bad argument #2 to 'remove' (position out of bounds)");
    }

    if (pos < 0 || pos > size) {
      return primitiveValue(null);
    }

    final removed = await _tableSequenceReadAsync(
      table,
      pos,
      runtime: interpreter,
    );

    // Shift elements
    for (var i = pos; i < size; i++) {
      final shifted = await _tableSequenceReadAsync(
        table,
        i + 1,
        runtime: interpreter,
      );
      await _tableSequenceWriteAsync(table, i, shifted, runtime: interpreter);
    }
    await _tableSequenceWriteAsync(
      table,
      size,
      primitiveValue(null),
      runtime: interpreter,
    );

    return removed;
  }
}

class _TableConcat extends BuiltinFunction {
  _TableConcat([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("table expected");
    }
    final table = _wrapTableLibraryValue(interpreter, args[0]);
    checktab(table, TablePermission.read);

    final separatorValue = args.length > 1 ? rawLuaSlot(args[1]) : "";
    final start = args.length > 2 ? rawLuaSlot(args[2]) as int : 1;
    final end = args.length > 3
        ? rawLuaSlot(args[3]) as int
        : await getTableLength(table);

    // Empty ranges return an empty LuaString when the separator is byte-backed
    // so table.concat preserves byte-string semantics.
    if (start > end) {
      return separatorValue is LuaString
          ? valueFromOptionalLuaSlot(
              interpreter,
              LuaString.fromBytes(const <int>[]),
            )
          : dartStringValue("");
    }

    final parts = <Object?>[];
    var i = start;
    while (NumberUtils.compare(i, end) <= 0) {
      final value = await _tableSequenceReadAsync(
        table,
        i,
        runtime: interpreter,
      );
      final rawValue = rawLuaSlot(value);
      if (rawValue == null) {
        // Lua throws an error when encountering nil values in the range
        throw LuaError("invalid value (nil) at index $i in table for 'concat'");
      }

      // Validate that the value is a string or number
      NumberUtils.validateStringOrNumber(rawValue, 'concat', i);
      parts.add(rawValue);

      // Prevent integer overflow when i == max integer
      if (i == NumberLimits.maxInteger) break;

      // Use NumberUtils for safe increment
      i = NumberUtils.add(i, 1);
    }

    final preserveByteStrings =
        separatorValue is LuaString || parts.any((part) => part is LuaString);
    if (!preserveByteStrings) {
      final buffer = StringBuffer();
      for (var index = 0; index < parts.length; index++) {
        if (index > 0) {
          buffer.write(separatorValue.toString());
        }
        buffer.write(parts[index].toString());
      }
      return dartStringValue(buffer.toString());
    }

    List<int> toBytes(Object? value) => switch (value) {
      final LuaString stringValue => stringValue.bytes,
      final String stringValue => LuaString.fromDartString(stringValue).bytes,
      final num numberValue => LuaString.fromDartString(
        numberValue.toString(),
      ).bytes,
      final BigInt integerValue => LuaString.fromDartString(
        integerValue.toString(),
      ).bytes,
      null => Uint8List(0),
      _ => LuaString.fromDartString(value.toString()).bytes,
    };

    final builder = BytesBuilder(copy: false);
    final separatorBytes = toBytes(separatorValue);
    for (var index = 0; index < parts.length; index++) {
      if (index > 0 && separatorBytes.isNotEmpty) {
        builder.add(separatorBytes);
      }
      builder.add(toBytes(parts[index]));
    }
    return valueFromOptionalLuaSlot(
      interpreter,
      LuaString.fromBytes(builder.takeBytes()),
    );
  }
}

class _TableMove extends BuiltinFunction {
  _TableMove([super.interpreter]);
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => "_TableMove: Starting with ${args.length} args");

    if (args.length < 4) {
      throw LuaError.typeError("table.move requires at least 4 arguments");
    }

    // Ensure all arguments are Value objects
    final a1 = _wrapTableLibraryValue(interpreter, args[0]);
    Logger.debugLazy(
      () => "_TableMove: a1 = $a1, type = ${rawLuaSlot(a1).runtimeType}",
    );

    final f = NumberUtils.toInt(rawLuaSlot(args[1]));
    final e = NumberUtils.toInt(rawLuaSlot(args[2]));
    final t = NumberUtils.toInt(rawLuaSlot(args[3]));
    final a2 = args.length > 4
        ? _wrapTableLibraryValue(interpreter, args[4])
        : a1;

    Logger.debugLazy(() => "_TableMove: f=$f, e=$e, t=$t, a2=$a2");
    Logger.debugLazy(
      () =>
          "_TableMove: maxI=${NumberLimits.maxInteger}, minI=${NumberLimits.minInteger}",
    );

    Logger.debugLazy(() => "_TableMove: About to checktab a1");
    checktab(a1, TablePermission.read);
    Logger.debugLazy(() => "_TableMove: About to checktab a2");
    checktab(a2, TablePermission.write);
    Logger.debugLazy(() => "_TableMove: checktab completed");

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
          Logger.debugLazy(
            () => "_TableMove: i=$i, srcIndex=$srcIndex, destIndex=$destIndex",
          );
          // Use proper table access that respects metamethods and awaits Future results
          var value = await a1.getValueAsync(primitiveValue(srcIndex));
          // Handle null values properly.
          final valueToStore = _wrapTableLibraryValue(
            a2.interpreter ?? a1.interpreter ?? interpreter,
            value,
          );
          Logger.debugLazy(
            () =>
                "_TableMove: writing value=$valueToStore to destIndex=$destIndex",
          );
          // Use proper table assignment that respects __newindex metamethod and awaits Future results
          await a2.setValueAsync(primitiveValue(destIndex), valueToStore);
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
          var value = await a1.getValueAsync(primitiveValue(srcIndex));
          // Handle null values properly.
          final valueToStore = _wrapTableLibraryValue(
            a2.interpreter ?? a1.interpreter ?? interpreter,
            value,
          );
          // Use proper table assignment that respects __newindex metamethod and awaits Future results
          await a2.setValueAsync(primitiveValue(destIndex), valueToStore);
        }
      }
    }

    return a2; /* return destination table */
  }
}

class _TableSort extends BuiltinFunction {
  _TableSort([super.interpreter]);
  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("table.sort requires a table argument");
    }

    final arg0 = args[0];
    final table = _wrapTableLibraryValue(interpreter, arg0);
    try {
      checktab(table, TablePermission.read | TablePermission.write);
    } on LuaError catch (error) {
      if (error.message == 'table expected') {
        throw LuaError(
          "bad argument #1 to 'table.sort' "
          "(table expected, got ${getLuaType(table)})",
        );
      }
      rethrow;
    }
    final comp = args.length > 1 ? args[1] : null;
    final rawTable = rawLuaSlot(table);
    final rawSequenceTable =
        rawTable is Map &&
        table.getMetamethod('__index') == null &&
        table.getMetamethod('__newindex') == null;
    final map = rawSequenceTable ? rawTable : null;

    // Validate comparison function if provided
    if (comp != null && comp is! Value) {
      throw LuaError(
        "bad argument #2 to 'sort' (function expected, got ${getLuaType(comp)})",
      );
    }
    final compRaw = rawLuaSlot(comp);
    if (comp is Value &&
        compRaw != null &&
        compRaw is! Function &&
        compRaw is! BuiltinFunction) {
      throw LuaError(
        "bad argument #2 to 'sort' (function expected, got ${getLuaType(comp)})",
      );
    }

    final n = await getTableLength(table, context: "table.sort");
    if (n >= NumberLimits.maxInt32) {
      throw LuaError("bad argument #1 to 'table.sort' (array too big)");
    }
    if (n <= 1) {
      return primitiveValue(null);
    }

    // Validate the order function if provided
    if (_shouldValidateOrderFunction(comp)) {
      await _validateOrderFunction(table, n, comp);
    }

    final primitiveSortDirection = _primitiveSortDirection(comp);
    if (primitiveSortDirection != 0 &&
        map != null &&
        _trySortPrimitiveArray(map, n, primitiveSortDirection)) {
      return primitiveValue(null);
    }

    // Perform in-place quicksort using Lua's algorithm
    await _auxSort(table, 1, n, comp, 0);

    return primitiveValue(null);
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

      final raw = rawLuaSlot(cell);
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
      if (original is Value && !original.isSharedPrimitive) {
        original.raw = sortedValue;
        map[i] = original;
      } else {
        map[i] = original is Value ? primitiveValue(sortedValue) : sortedValue;
      }
    }
  }

  // Simple in-place quicksort implementation
  Future<void> _auxSort(
    Value table,
    int lo,
    int up,
    Object? comp,
    int rnd,
  ) async {
    Logger.debugLazy(() => "_auxSort: lo=$lo, up=$up", category: 'TableSort');

    if (lo >= up) {
      Logger.debugLazy(
        () => "_auxSort: base case reached",
        category: 'TableSort',
      );
      return; // base case
    }

    // Quick check for degenerate case: if comparison function always returns false/nil
    // and we have more than a few elements, use a fast path
    if (up - lo > 5 && comp is Value && !_isNilTableValue(comp)) {
      bool alwaysFalse = true;
      // Test a few comparisons to see if they all return false
      for (int i = 0; i < 3 && alwaysFalse; i++) {
        final testResult = await _sortComp(table, lo + i, lo + i + 1, comp);
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
        await _insertionSort(table, lo, up, comp);
        return;
      }
    }

    // For small arrays or degenerate cases, use insertion sort
    if (up - lo < 10) {
      Logger.debugLazy(
        () => "_auxSort: using insertion sort for small array",
        category: 'TableSort',
      );
      await _insertionSort(table, lo, up, comp);
      return;
    }

    // Choose pivot (middle element)
    int pivot = (lo + up) ~/ 2;
    Logger.debugLazy(
      () => "_auxSort: chosen pivot at index $pivot",
      category: 'TableSort',
    );

    // Move pivot to end
    await _set2(table, pivot, up);

    // Partition
    int i = lo - 1;
    for (int j = lo; j < up; j++) {
      final compResult = await _sortComp(table, j, up, comp);
      Logger.debugLazy(
        () => "_auxSort: comparing indices $j and $up, result=$compResult",
        category: 'TableSort',
      );
      if (compResult) {
        i++;
        await _set2(table, i, j);
        Logger.debugLazy(
          () => "_auxSort: swapped elements at indices $i and $j",
          category: 'TableSort',
        );
      }
    }

    // Move pivot to correct position
    await _set2(table, i + 1, up);
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
      await _auxSort(table, lo + 1, up, comp, rnd);
    } else if (pivot >= up) {
      Logger.debugLazy(
        () => "_auxSort: degenerate case - pivot at end, sorting rest",
        category: 'TableSort',
      );
      // Pivot is at the end, sort the rest
      await _auxSort(table, lo, up - 1, comp, rnd);
    } else {
      Logger.debugLazy(
        () => "_auxSort: normal case - sorting left and right parts",
        category: 'TableSort',
      );
      // Normal case: recursively sort left and right parts
      await _auxSort(table, lo, pivot - 1, comp, rnd);
      await _auxSort(table, pivot + 1, up, comp, rnd);
    }
  }

  // Insertion sort for small arrays or degenerate cases
  Future<void> _insertionSort(Value table, int lo, int up, Object? comp) async {
    for (int i = lo + 1; i <= up; i++) {
      for (int j = i; j > lo && await _sortComp(table, j, j - 1, comp); j--) {
        Logger.debugLazy(
          () => "_insertionSort: should swap? j=$j, result=true",
          category: 'TableSort',
        );
        await _set2(table, j, j - 1);
      }
    }
  }

  // Return true iff value at index 'a' is less than the value at index 'b'
  Future<bool> _sortComp(Value table, int a, int b, Object? comp) async {
    final valA = await _tableSequenceReadAsync(table, a);
    final valB = await _tableSequenceReadAsync(table, b);

    Logger.debugLazy(
      () =>
          "_sortComp: comparing indices a=$a (${valA.runtimeType}) with b=$b (${valB.runtimeType})",
      category: 'TableSort',
    );

    bool? fastLessThan(dynamic lhs, dynamic rhs) {
      final left = rawLuaSlot(lhs);
      final right = rawLuaSlot(rhs);

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
    final aVal = rawLuaSlot(valA);
    final bVal = rawLuaSlot(valB);
    if (aVal == null || bVal == null) {
      throw LuaError.typeError("attempt to compare nil value");
    }

    if (_isNilTableValue(comp)) {
      // no function?

      // Fast path: number/number or string/string (including LuaString) comparisons
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
      final compRaw = rawLuaSlot(comp);
      if (comp is Value &&
          (compRaw is Function || compRaw is BuiltinFunction)) {
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

        final func = compRaw;
        final runtime = interpreter;
        final previousYieldable = runtime?.isYieldable;
        if (runtime != null) {
          enterSortComparator(runtime);
          runtime.isYieldable = false;
        }
        late final Object? result;
        try {
          result = await (func as dynamic)([valA, valB]);
        } finally {
          if (runtime != null) {
            runtime.isYieldable = previousYieldable ?? true;
            exitSortComparator(runtime);
          }
        }
        final boolResult = _isTrueTableValue(result);
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
      case Value(raw: final int value) when !current.isSharedPrimitive:
        current.raw = value + 1;
      case Value(raw: final int value):
        counterBox.value = primitiveValue(value + 1);
      case Value(raw: final double value) when !current.isSharedPrimitive:
        current.raw = value + 1;
      case Value(raw: final double value):
        counterBox.value = primitiveValue(value + 1);
      case Value(raw: final BigInt value) when !current.isSharedPrimitive:
        current.raw = value + BigInt.one;
      case Value(raw: final BigInt value):
        counterBox.value = primitiveValue(value + BigInt.one);
      case final Value wrapped:
        final raw = rawLuaSlot(wrapped);
        if (raw is num) {
          if (wrapped.isSharedPrimitive) {
            counterBox.value = primitiveValue(raw + 1);
          } else {
            wrapped.raw = raw + 1;
          }
        } else if (raw is BigInt) {
          if (wrapped.isSharedPrimitive) {
            counterBox.value = primitiveValue(raw + BigInt.one);
          } else {
            wrapped.raw = raw + BigInt.one;
          }
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
  Future<void> _validateOrderFunction(Value table, int n, Object? comp) async {
    if (comp == null || n < 2) return;

    final compRaw = rawLuaSlot(comp);
    if (comp is Value && (compRaw is Function || compRaw is BuiltinFunction)) {
      final func = compRaw;

      // Test the function with a few pairs to detect obvious issues
      bool? firstResult;
      int testCount = 0;
      final maxTests = n < 10 ? n : 10; // Test up to 10 pairs or all if n < 10

      for (int i = 1; i < maxTests; i++) {
        final valA = await _tableSequenceReadAsync(table, i);
        final valB = await _tableSequenceReadAsync(table, i + 1);

        if (!_isNilTableValue(valA) && !_isNilTableValue(valB)) {
          final runtime = interpreter;
          final previousYieldable = runtime?.isYieldable;
          if (runtime != null) {
            enterSortComparator(runtime);
            runtime.isYieldable = false;
          }
          late final Object? result;
          try {
            result = await (func as dynamic)([valA, valB]);
          } finally {
            if (runtime != null) {
              runtime.isYieldable = previousYieldable ?? true;
              exitSortComparator(runtime);
            }
          }
          final boolResult = _isTrueTableValue(result);

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
        final valA = await _tableSequenceReadAsync(table, 2);
        final valB = await _tableSequenceReadAsync(table, 1);

        if (!_isNilTableValue(valA) && !_isNilTableValue(valB)) {
          final runtime = interpreter;
          if (runtime != null) {
            enterSortComparator(runtime);
          }
          late final Object? result;
          try {
            result = await (func as dynamic)([valA, valB]);
          } finally {
            if (runtime != null) {
              exitSortComparator(runtime);
            }
          }
          final boolResult = _isTrueTableValue(result);

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
    if (_isNilTableValue(a)) {
      throw LuaError.typeError("attempt to compare nil value");
    }
    if (_isNilTableValue(b)) {
      throw LuaError.typeError("attempt to compare nil value");
    }

    final aVal = rawLuaSlot(a);
    final bVal = rawLuaSlot(b);

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
      final aValue = cachedPrimitiveOrValue(interpreter, a);
      final bValue = cachedPrimitiveOrValue(interpreter, b);

      // Prefer __lt from 'a'
      if (aValue.hasMetamethod('__lt')) {
        try {
          final result = await aValue.callMetamethodAsync('__lt', [
            aValue,
            bValue,
          ]);
          final boolRes = _isTrueTableValue(result);
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
          final boolRes = _isTrueTableValue(result);
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
  Future<void> _set2(Value table, int i, int j) async {
    Logger.debugLazy(
      () => "_set2: swapping elements at indices $i and $j",
      category: 'TableSort',
    );
    final temp = await _tableSequenceReadAsync(table, i, runtime: interpreter);
    final other = await _tableSequenceReadAsync(table, j, runtime: interpreter);
    await _tableSequenceWriteAsync(table, i, other, runtime: interpreter);
    await _tableSequenceWriteAsync(table, j, temp, runtime: interpreter);
  }

  // Partition function (similar to C implementation)
}

class _TablePack extends BuiltinFunction {
  _TablePack([super.interpreter]);
  @override
  Object? call(List<Object?> args) {
    final table = TableStorage();
    for (var i = 0; i < args.length; i++) {
      final value = args[i];
      if (isLuaNilValue(value)) {
        continue;
      }
      table.setDense(i + 1, _wrapTableLibraryValue(interpreter, value));
    }
    table['n'] = primitiveValue(args.length);
    return ValueClass.table(table)..interpreter = interpreter;
  }
}

class _TableUnpack extends BuiltinFunction {
  _TableUnpack([super.interpreter]);
  @override
  Object? call(List<Object?> args) async {
    final bool log = Logger.enabled;
    if (log) {
      Logger.debugLazy(
        () => "_TableUnpack: Starting unpack with ${args.length} args",
      );
    }

    if (args.isEmpty) {
      throw LuaError.typeError("table.unpack requires a table argument");
    }

    final table = _wrapTableLibraryValue(interpreter, args[0]);
    checktab(table, TablePermission.read);
    if (log) {
      Logger.debugLazy(
        () => "_TableUnpack: Got table value ${rawLuaSlot(table).runtimeType}",
      );
    }

    int i, j;

    // Handle start index (default to 1)
    if (args.length > 1) {
      final startArg = rawLuaSlot(args[1]);
      if (log) {
        Logger.debugLazy(
          () =>
              "_TableUnpack: Start arg raw value: $startArg, type: ${startArg.runtimeType}",
        );
      }
      if (startArg == null) {
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected, got nil)",
        );
      }
      try {
        i = NumberUtils.toInt(startArg);
        if (log) {
          Logger.debugLazy(
            () =>
                "_TableUnpack: Converted start index to: $i, type: ${i.runtimeType}",
          );
        }
      } catch (e) {
        if (log) {
          Logger.debugLazy(
            () => "_TableUnpack: Error converting start index: $e",
          );
        }
        throw LuaError.typeError(
          "bad argument #2 to 'unpack' (number expected)",
        );
      }
    } else {
      i = 1;
      if (log) {
        Logger.debugLazy(() => "_TableUnpack: Using default start index: $i");
      }
    }

    // Handle end index (default to table length using Lua semantics)
    if (args.length > 2) {
      final endArg = rawLuaSlot(args[2]);
      if (log) {
        Logger.debugLazy(
          () =>
              "_TableUnpack: End arg raw value: $endArg, type: ${endArg.runtimeType}",
        );
      }
      if (endArg == null) {
        // nil means use table length (same as not providing the argument)
        if (log) {
          Logger.debugLazy(
            () => "_TableUnpack: End arg is nil, getting table length",
          );
        }
        j = await getTableLength(table, context: null);
      } else {
        try {
          j = NumberUtils.toInt(endArg);
          if (log) {
            Logger.debugLazy(
              () =>
                  "_TableUnpack: Converted end index to: $j, type: ${j.runtimeType}",
            );
          }
        } catch (e) {
          if (log) {
            Logger.debugLazy(
              () => "_TableUnpack: Error converting end index: $e",
            );
          }
          throw LuaError.typeError(
            "bad argument #3 to 'unpack' (number expected)",
          );
        }
      }
    } else {
      if (log) {
        Logger.debugLazy(
          () => "_TableUnpack: No end arg, getting table length",
        );
      }
      j = await getTableLength(table, context: null);
    }

    if (log) {
      Logger.debugLazy(
        () => "_TableUnpack: i=$i (${i.runtimeType}), j=$j (${j.runtimeType})",
      );
    }

    final int start = i;
    final int end = j;
    if (start > end) {
      if (log) {
        Logger.debugLazy(
          () => "_TableUnpack: Empty range (i > j), returning zero values",
        );
      }
      return const LuaResults.empty();
    }

    final BigInt startBig = NumberUtils.toBigInt(start);
    final BigInt endBig = NumberUtils.toBigInt(end);
    final BigInt rawCount = endBig - startBig + BigInt.one;
    if (rawCount.isNegative || rawCount >= BigInt.from(NumberLimits.maxInt32)) {
      if (log) {
        Logger.debugLazy(
          () => "_TableUnpack: count=$rawCount outside limits, throwing error",
        );
      }
      throw LuaError("too many results to unpack");
    }

    final int count = rawCount.toInt();
    final result = List<Value?>.filled(count, null, growable: false);
    for (var offset = 0; offset < count; offset++) {
      result[offset] = await _tableSequenceReadAsync(table, start + offset);
    }

    if (count == 0) {
      return const LuaResults.empty();
    }
    if (count == 1) {
      return result[0]!;
    }
    return LuaResults(result.cast<Value>());
  }
}
