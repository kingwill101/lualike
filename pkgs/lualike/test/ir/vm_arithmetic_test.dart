@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrVm arithmetic', () {
    Object? unwrap(Object? candidate) => switch (candidate) {
      Value(:final raw) when raw is LuaString => raw.toString(),
      Value(:final raw) => raw,
      LuaString value => value.toString(),
      final other => other,
    };

    test('uses globals in arithmetic expressions', () async {
      final program = parse('return x * 2');
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment();
      env.define('x', Value(4));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      expect(result, equals(8));
    });

    test('executes bitwise operations', () async {
      final chunk = LualikeIrCompiler().compile(parse('return (6 & 3) | 1'));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(3));
    });

    test('executes xor and shifts', () async {
      final chunk = LualikeIrCompiler().compile(parse('return (5 ~ 3) << 1'));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(12));
    });

    test('coerces string operands via NumberUtils', () async {
      final addChunk = LualikeIrCompiler().compile(parse('return "2" + 3'));
      final divChunk = LualikeIrCompiler().compile(parse('return "6" / "2"'));
      expect(await LualikeIrVm().execute(addChunk), equals(5));
      expect(await LualikeIrVm().execute(divChunk), equals(3));
    });

    test('executes string concatenation', () async {
      final chunk = LualikeIrCompiler().compile(parse('return "foo" .. "bar"'));
      final result = await LualikeIrVm().execute(chunk);
      expect(unwrap(result), equals('foobar'));
    });

    test('executes modulo, floor division, and exponent', () async {
      final modChunk = LualikeIrCompiler().compile(parse('return 7 % 4'));
      final idivChunk = LualikeIrCompiler().compile(parse('return 7 // 3'));
      final powChunk = LualikeIrCompiler().compile(parse('return 2 ^ 3'));
      expect(await LualikeIrVm().execute(modChunk), equals(3));
      expect(await LualikeIrVm().execute(idivChunk), equals(2));
      expect(await LualikeIrVm().execute(powChunk), equals(8));
    });

    test('coerces string operands for modulo', () async {
      final chunk = LualikeIrCompiler().compile(parse('return "9" % "4"'));
      expect(await LualikeIrVm().execute(chunk), equals(1));
    });

    test('executes unary operators', () async {
      final chunks = [
        LualikeIrCompiler().compile(parse('return not false')),
        LualikeIrCompiler().compile(parse('return -(-3)')),
        LualikeIrCompiler().compile(parse('return ~5')),
        LualikeIrCompiler().compile(parse('return #"hello"')),
      ];
      final vm = LualikeIrVm();
      expect(await vm.execute(chunks[0]), isTrue);
      expect(await vm.execute(chunks[1]), equals(3));
      expect(await vm.execute(chunks[2]), equals(-6));
      expect(await vm.execute(chunks[3]), equals(5));
    });

    test('unary minus coerces strings via NumberUtils', () async {
      final chunk = LualikeIrCompiler().compile(parse('return -"4"'));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(-4));
    });
  });
}
