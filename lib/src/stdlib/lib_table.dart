import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';

import '../value_class.dart';

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
    if (args.length < 2) {
      throw LuaError.typeError("table.insert requires at least 2 arguments");
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
      throw LuaError.typeError("table.concat requires a table argument");
    }
    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError.typeError(
        "table.concat requires a table as first argument",
      );
    }

    final map = table.raw as Map;
    final sep = args.length > 1 ? (args[1] as Value).raw.toString() : "";
    final start = args.length > 2 ? (args[2] as Value).raw as int : 1;
    final end = args.length > 3 ? (args[3] as Value).raw as int : map.length;

    final buffer = StringBuffer();
    for (var i = start; i <= end; i++) {
      if (i > start) {
        buffer.write(sep);
      }
      final value = map[i];
      if (value != null) {
        buffer.write((value as Value).raw.toString());
      }
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

    if (f > e) return a2; // Nothing to move

    // Calculate the direction of movement to avoid overwriting values
    // when source and destination tables are the same
    if (a1 == a2 && t > f) {
      // Move from right to left (highest index first)
      for (var i = e; i >= f; i--) {
        final value = srcTable[i];
        destTable[t + (i - f)] = value;
      }
    } else {
      // Move from left to right (lowest index first)
      for (var i = f; i <= e; i++) {
        final value = srcTable[i];
        destTable[t + (i - f)] = value;
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
    if (keys.isEmpty) return Value(null);

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
    try {
      i = args.length > 1 ? (args[1] as Value).raw as int : 1;
      j = args.length > 2 ? (args[2] as Value).raw as int : map.length;
    } catch (e) {
      throw LuaError.typeError("table.unpack requires a table argument");
    }

    final result = <Value>[];
    for (var k = i; k <= j; k++) {
      final v = map[k];
      if (v == null || (v is Value && v.raw == null)) {
        break;
      }
      result.add(v is Value ? v : Value(v));
    }
    if (result.isEmpty) return Value(null);
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
