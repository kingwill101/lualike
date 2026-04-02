@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('Lualike IR lowered arithmetic', () {
    Object? unwrap(Object? candidate) => switch (candidate) {
      Value(:final raw) when raw is LuaString => raw.toString(),
      Value(:final raw) => raw,
      LuaString value => value.toString(),
      final other => other,
    };

    test('uses globals in arithmetic expressions', () async {
      final result = await executeCode(
        'return x * 2',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('x', Value(4));
        },
      );
      expect(result, equals(8));
    });

    test('executes bitwise operations', () async {
      final result = await executeCode('return (6 & 3) | 1', mode: EngineMode.ir);
      expect(result, equals(3));
    });

    test('executes xor and shifts', () async {
      final result = await executeCode('return (5 ~ 3) << 1', mode: EngineMode.ir);
      expect(result, equals(12));
    });

    test('coerces string operands via NumberUtils', () async {
      expect(await executeCode('return "2" + 3', mode: EngineMode.ir), equals(5));
      expect(await executeCode('return "6" / "2"', mode: EngineMode.ir), equals(3));
    });

    test('executes string concatenation', () async {
      final result = await executeCode('return "foo" .. "bar"', mode: EngineMode.ir);
      expect(unwrap(result), equals('foobar'));
    });

    test('executes modulo, floor division, and exponent', () async {
      expect(await executeCode('return 7 % 4', mode: EngineMode.ir), equals(3));
      expect(await executeCode('return 7 // 3', mode: EngineMode.ir), equals(2));
      expect(await executeCode('return 2 ^ 3', mode: EngineMode.ir), equals(8));
    });

    test('coerces string operands for modulo', () async {
      expect(await executeCode('return "9" % "4"', mode: EngineMode.ir), equals(1));
    });

    test('executes unary operators', () async {
      expect(await executeCode('return not false', mode: EngineMode.ir), isTrue);
      expect(await executeCode('return -(-3)', mode: EngineMode.ir), equals(3));
      expect(await executeCode('return ~5', mode: EngineMode.ir), equals(-6));
      expect(await executeCode('return #"hello"', mode: EngineMode.ir), equals(5));
    });

    test('unary minus coerces strings via NumberUtils', () async {
      final result = await executeCode('return -"4"', mode: EngineMode.ir);
      expect(result, equals(-4));
    });
  });
}
