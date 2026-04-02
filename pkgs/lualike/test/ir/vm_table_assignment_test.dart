@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

Object? _unwrapValue(Object? value) {
  if (value is Value) {
    return _unwrapValue(value.raw);
  }
  if (value is LuaString) {
    return value.toString();
  }
  return value;
}

void main() {
  group('IR table assignments', () {
    test('executes table field assignment', () async {
      final result = await executeCode(
        'tbl.value = 99; return tbl.value',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('tbl', Value.wrap({'value': 1}));
        },
      );
      final actual = _unwrapValue(result);
      expect(actual, equals(99));
    });

    test('executes table index assignment with literal', () async {
      final result = await executeCode(
        'arr[1] = "first"; return arr[1]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('arr', Value.wrap({}));
        },
      );
      final actual = _unwrapValue(result);
      expect(actual, equals('first'));
    });

    test('executes table index assignment with dynamic key', () async {
      final result = await executeCode(
        'arr[idx] = 7; return arr[idx]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('arr', Value.wrap({}))
            ..define('idx', Value('foo'));
        },
      );
      final actual = _unwrapValue(result);
      expect(actual, equals(7));
    });

    test('executes table index assignment with large literal fallback', () async {
      final result = await executeCode(
        'arr[999] = "big"; return arr[999]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('arr', Value.wrap({}));
        },
      );
      final actual = _unwrapValue(result);
      expect(actual, equals('big'));
    });

    test('honours __newindex metamethod', () async {
      final backing = Value.wrap({});
      final proxy = Value.wrap({})
        ..metatable = {
          '__newindex': (List<Object?> args) {
            final key = args[1] is Value ? args[1] as Value : Value(args[1]);
            final value = args[2] is Value ? args[2] as Value : Value(args[2]);
            backing[key] = value;
            return null;
          },
        };
      final result = await executeCode(
        'proxy.key = 1; return backing.key',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('proxy', proxy)
            ..define('backing', backing);
        },
      );
      final actual = _unwrapValue(result);
      expect(actual, equals(1));
    });

    test('executes multi-target table field assignment', () async {
      Value? tableValue;
      final result = await executeCode(
        'tbl.one, tbl.two = 10, 20; return tbl.one == 10 and tbl.two == 20',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          tableValue = Value.wrap({'one': 0, 'two': 0});
          runtime.globals.define('tbl', tableValue!);
        },
      );
      final actual = _unwrapValue(result);
      expect(actual, isTrue);

      final table = tableValue?.raw;
      expect(table, isA<Map>());
      final mapTable = table as Map;
      final first = mapTable['one'];
      final second = mapTable['two'];
      expect(first, isA<Value>());
      expect(second, isA<Value>());
      expect((first as Value).raw, equals(10));
      expect((second as Value).raw, equals(20));
    });
  });
}
