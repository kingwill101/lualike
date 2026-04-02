@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

dynamic _unwrap(dynamic value) => value is Value ? value.raw : value;

class _CloseCounter {
  int value = 0;
}

Value _closeableResource(_CloseCounter counter) {
  return Value(
    <String, dynamic>{},
    metatable: <String, dynamic>{
      '__close': (List<Object?> _) {
        counter.value += 1;
        return null;
      },
    },
  );
}

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
  group('IR repeat-until loops', () {
    test('executes body before checking condition', () async {
      final result = await executeCode(
        '''
        local count = 0
        repeat
          count = count + 1
        until count >= 3
        return count
      ''',
        mode: EngineMode.ir,
      );

      expect(_unwrap(result), equals(3));
    });

    test('condition can reference locals declared in the body', () async {
      final result = await executeCode(
        '''
        local result = 0
        repeat
          local nextValue = result + 2
          result = nextValue
        until nextValue >= 4
        return result
      ''',
        mode: EngineMode.ir,
      );

      expect(_unwrap(result), equals(4));
    });
  });

  group('IR break statements', () {
    test('exits while loops', () async {
      final result = await executeCode(
        '''
        local count = 0
        while true do
          count = count + 1
          break
        end
        return count
      ''',
        mode: EngineMode.ir,
      );

      expect(_unwrap(result), equals(1));
    });

    test('exits repeat-until loops', () async {
      final result = await executeCode(
        '''
        local count = 0
        repeat
          count = count + 1
          break
        until false
        return count
      ''',
        mode: EngineMode.ir,
      );

      expect(_unwrap(result), equals(1));
    });
  });

  group('IR numeric for loops', () {
    test('executes ascending loop', () async {
      final result = await executeCode(
        '''
        for i = 1, 3 do
          tbl.sum = tbl.sum + i
        end
        return tbl.sum
      ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('tbl', Value.wrap({'sum': 0}));
        },
      );
      expect(_unwrap(result), equals(6));
    });

    test('executes descending loop', () async {
      final result = await executeCode(
        '''
        for i = 3, 1, -1 do
          tbl.count = tbl.count + 1
        end
        return tbl.count
      ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('tbl', Value.wrap({'count': 0}));
        },
      );
      expect(_unwrap(result), equals(3));
    });
  });

  group('IR generic for loops', () {
    test('executes iterator-based loop', () async {
      final result = await executeCode(
        '''
        for _, key, value in iter, state, control do
          tbl.sum = tbl.sum + value
        end
        return tbl.sum
      ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          final entries = <List<Object?>>[
            [1, 10],
            [2, 20],
          ];
          final iterator = Value((List<Object?> args) {
            final state = args[0];
            final control = args[1];
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
          runtime.globals
            ..define('iter', iterator)
            ..define('state', Value(entries))
            ..define('control', Value(0))
            ..define('tbl', Value.wrap({'sum': 0}));
        },
      );
      expect(_unwrap(result), equals(30));
    });

    test('iterates using pairs-style protocol', () async {
      final result = await executeCode(
        '''
        local acc = 0
        for _, value in pairs(items) do
          acc = acc + value
        end
        return acc
      ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('pairs', _testPairs())
            ..define('items', Value.wrap({1: 10, 2: 20, 3: 5}));
        },
      );
      expect(_unwrap(result), equals(35));
    });

    test('closes explicit fourth iterator value on break', () async {
      final counter = _CloseCounter();
      final result = await executeCode(
        '''
        local seen = 0
        for key, value in iter, state, nil, closer do
          seen = seen + value
          break
        end
        return seen
      ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          final entries = <List<int>>[
            [1, 10],
            [2, 20],
          ];
          final iterator = Value((List<Object?> args) {
            final stateArg = args[0];
            final controlArg = args.length > 1 ? args[1] : null;
            final state = stateArg is Value
                ? stateArg.raw as List<List<int>>
                : stateArg as List<List<int>>;
            final currentIndex = controlArg is Value
                ? controlArg.raw as int?
                : controlArg as int?;
            final nextIndex = currentIndex == null ? 0 : currentIndex + 1;
            if (nextIndex >= state.length) {
              return Value.multi(const []);
            }
            final entry = state[nextIndex];
            return Value.multi([entry[0], entry[1]]);
          });
          runtime.globals
            ..define('iter', iterator)
            ..define('state', Value(entries))
            ..define('closer', _closeableResource(counter));
        },
      );
      expect(_unwrap(result), equals(10));
      expect(counter.value, equals(1));
    });

    test('closes loop resources returned by iterator factory', () async {
      final counter = _CloseCounter();
      final result = await executeCode(
        '''
        local sum = 0
        for i in open(3) do
          sum = sum + i
        end
        return sum
      ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          final open = Value((List<Object?> _) {
            var remaining = 3;
            final iterator = Value((List<Object?> __) {
              if (remaining <= 0) {
                return Value.multi(const []);
              }
              final next = remaining;
              remaining -= 1;
              return Value.multi([next]);
            });
            return Value.multi([
              iterator,
              Value(null),
              Value(null),
              _closeableResource(counter),
            ]);
          });
          runtime.globals.define('open', open);
        },
      );
      expect(_unwrap(result), equals(6));
      expect(counter.value, equals(1));
    });

    test('accepts raw IR closures as generic-for iterators', () async {
      final counter = _CloseCounter();
      final result = await executeCode(
        '''
        local function open()
          return (function () return nil end), nil, nil, closer
        end

        for k in open() do
          open = k
        end

        return 99
      ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('closer', _closeableResource(counter));
        },
      );
      expect(_unwrap(result), equals(99));
      expect(counter.value, equals(1));
    });
  });
}
