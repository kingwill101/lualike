@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

dynamic _unwrap(dynamic value) => value is Value ? value.raw : value;

Value _testPairs() {
  return Value((List<Object?> args) {
    if (args.isEmpty) {
      throw StateError('pairs requires a table argument');
    }
    final tableArg = args[0];
    final table = tableArg is Value ? tableArg : Value.wrap(tableArg);
    final rawTable = table.raw;
    Iterable<dynamic> keyIterable;
    if (rawTable is TableStorage) {
      keyIterable = rawTable.keys;
    } else if (rawTable is Map) {
      keyIterable = rawTable.keys;
    } else {
      throw StateError('pairs requires a table argument');
    }
    final keys = keyIterable.toList();
    final iterator = Value((List<Object?> iterArgs) {
      final stateArg = iterArgs[0];
      final controlArg = iterArgs.length > 1 ? iterArgs[1] : null;
      final lastKey = controlArg is Value ? controlArg.raw : controlArg;
      var nextIndex = 0;
      if (lastKey != null) {
        final matchIndex = keys.indexWhere((key) {
          final rawKey = key is Value ? key.raw : key;
          return rawKey == lastKey;
        });
        if (matchIndex >= 0) {
          nextIndex = matchIndex + 1;
        }
      }
      if (nextIndex >= keys.length) {
        return Value(null);
      }
      final key = keys[nextIndex];
      final normalizedKey = key is Value ? key.raw : key;
      final stateRaw = stateArg is Value ? stateArg.raw : stateArg;
      dynamic valueRaw;
      if (stateRaw is TableStorage) {
        valueRaw = stateRaw[normalizedKey];
      } else if (stateRaw is Map) {
        valueRaw = stateRaw[normalizedKey];
      } else {
        valueRaw = null;
      }
      final value = valueRaw is Value ? valueRaw : Value.wrap(valueRaw);
      return Value.multi([Value(normalizedKey), value]);
    });
    return Value.multi([iterator, table, Value(null)]);
  });
}

void main() {
  group('LualikeIrVm numeric for loops', () {
    test('executes ascending loop', () async {
      final program = parse('''
        for i = 1, 3 do
          tbl.sum = tbl.sum + i
        end
        return tbl.sum
      ''');
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()..define('tbl', Value.wrap({'sum': 0}));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(6));
    });

    test('executes descending loop', () async {
      final program = parse('''
        for i = 3, 1, -1 do
          tbl.count = tbl.count + 1
        end
        return tbl.count
      ''');
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()..define('tbl', Value.wrap({'count': 0}));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(3));
    });
  });

  group('LualikeIrVm generic for loops', () {
    test('executes iterator-based loop', () async {
      final program = parse('''
        for _, key, value in iter, state, control do
          tbl.sum = tbl.sum + value
        end
        return tbl.sum
      ''');
      final chunk = LualikeIrCompiler().compile(program);

      final entries = <List<Object?>>[
        [1, 10],
        [2, 20],
      ];

      final iterator = Value((List<Object?> args) {
        final state = args[0];
        final control = args[1];
        // ignore: avoid_print
        print('iterator state=$state control=$control');
        final data = state is Value
            ? state.raw as List<List<Object?>>
            : state as List<List<Object?>>;
        final currentIndex = control is Value
            ? control.raw as int?
            : control as int?;
        final nextIndex = (currentIndex ?? 0) + 1;
        if (nextIndex > data.length) {
          return Value.multi(const []);
        }
        final entry = data[nextIndex - 1];
        return Value.multi([nextIndex, entry[0], entry[1]]);
      });

      final env = Environment()
        ..define('iter', iterator)
        ..define('state', Value(entries))
        ..define('control', Value(0))
        ..define('tbl', Value.wrap({'sum': 0}));

      final result = await LualikeIrVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(30));
    });

    test('iterates using pairs-style protocol', () async {
      final program = parse('''
        local acc = 0
        for _, value in pairs(items) do
          acc = acc + value
        end
        return acc
      ''');
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()
        ..define('pairs', _testPairs())
        ..define('items', Value.wrap({1: 10, 2: 20, 3: 5}));

      final result = await LualikeIrVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(35));
    });
  });
}
