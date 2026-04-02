@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('Lualike IR lowered tables', () {
    test('executes table field access', () async {
      final result = await executeCode(
        'return tbl.value',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('tbl', Value.wrap({'value': 42}));
        },
      );
      expect(result is Value ? result.raw : result, equals(42));
    });

    test('executes table index access with literal', () async {
      final result = await executeCode(
        'return arr[1]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('arr', Value.wrap({1: 'first'}));
        },
      );
      expect(result is Value ? result.raw : result, equals('first'));
    });

    test('executes table index access with dynamic key', () async {
      final result = await executeCode(
        'return arr[idx]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('arr', Value.wrap({'foo': 99}))
            ..define('idx', Value('foo'));
        },
      );
      expect(result is Value ? result.raw : result, equals(99));
    });

    test('executes table index access with large literal fallback', () async {
      final result = await executeCode(
        'return arr[999]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('arr', Value.wrap({999: 'big'}));
        },
      );
      expect(result is Value ? result.raw : result, equals('big'));
    });

    test('constructs table literal with sequential elements', () async {
      final result = await executeCode('return {1, 2, 3}', mode: EngineMode.ir)
          as Value;

      expect(result[Value(1)]?.raw, equals(1));
      expect(result[Value(2)]?.raw, equals(2));
      expect(result[Value(3)]?.raw, equals(3));
    });

    test('constructs table literal with keyed and indexed fields', () async {
      final result = await executeCode(
        'return {foo = 5, [3] = 7, 9}',
        mode: EngineMode.ir,
      ) as Value;

      expect(result[Value('foo')]?.raw, equals(5));
      expect(result[Value(3)]?.raw, equals(7));
      expect(result[Value(1)]?.raw, equals(9));
    });

    test('preserves __close field through setmetatable helper', () async {
      const source = '''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local function marker() end
local value = func2close(marker)
local mt = getmetatable(value)
return type(mt), mt.__close == marker
''';
      final result = await executeCode(source, mode: EngineMode.ir) as Value;
      final normalized = (result.raw as List<Object?>)
          .map((value) => value is Value ? value.raw : value)
          .toList(growable: false);

      expect(normalized, equals(<Object?>['table', true]));
    });

    test('constructs table literal with vararg tail', () async {
      const source = '''
local function build(...)
  return {1, 2, ...}
end

return build(3, 4, 5)
''';
      final result = await executeCode(source, mode: EngineMode.ir) as Value;

      expect(result[Value(1)]?.raw, equals(1));
      expect(result[Value(2)]?.raw, equals(2));
      expect(result[Value(3)]?.raw, equals(3));
      expect(result[Value(4)]?.raw, equals(4));
      expect(result[Value(5)]?.raw, equals(5));
    });

    test('constructs large sequential table literal', () async {
      final literals = List<String>.generate(
        60,
        (index) => '${index + 1}',
      ).join(', ');
      final result = await executeCode(
        'return {$literals}',
        mode: EngineMode.ir,
      ) as Value;

      for (var i = 1; i <= 60; i++) {
        expect(result[Value(i)]?.raw, equals(i));
      }
    });
  });
}
