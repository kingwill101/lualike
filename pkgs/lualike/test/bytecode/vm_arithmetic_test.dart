import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm arithmetic', () {
    test('uses globals in arithmetic expressions', () async {
      final program = parse('return x * 2');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment();
      env.define('x', Value(4));
      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(result, equals(8));
    });

    test('executes bitwise operations', () async {
      final chunk = BytecodeCompiler().compile(parse('return (6 & 3) | 1'));
      final result = await BytecodeVm().execute(chunk);
      expect(result, equals(3));
    });

    test('executes xor and shifts', () async {
      final chunk = BytecodeCompiler().compile(parse('return (5 ~ 3) << 1'));
      final result = await BytecodeVm().execute(chunk);
      expect(result, equals(12));
    });

    test('coerces string operands via NumberUtils', () async {
      final addChunk = BytecodeCompiler().compile(parse('return "2" + 3'));
      final divChunk = BytecodeCompiler().compile(parse('return "6" / "2"'));
      expect(await BytecodeVm().execute(addChunk), equals(5));
      expect(await BytecodeVm().execute(divChunk), equals(3));
    });

    test('executes modulo, floor division, and exponent', () async {
      final modChunk = BytecodeCompiler().compile(parse('return 7 % 4'));
      final idivChunk = BytecodeCompiler().compile(parse('return 7 // 3'));
      final powChunk = BytecodeCompiler().compile(parse('return 2 ^ 3'));
      expect(await BytecodeVm().execute(modChunk), equals(3));
      expect(await BytecodeVm().execute(idivChunk), equals(2));
      expect(await BytecodeVm().execute(powChunk), equals(8));
    });

    test('coerces string operands for modulo', () async {
      final chunk = BytecodeCompiler().compile(parse('return "9" % "4"'));
      expect(await BytecodeVm().execute(chunk), equals(1));
    });

    test('executes unary operators', () async {
      final chunks = [
        BytecodeCompiler().compile(parse('return not false')),
        BytecodeCompiler().compile(parse('return -(-3)')),
        BytecodeCompiler().compile(parse('return ~5')),
        BytecodeCompiler().compile(parse('return #"hello"')),
      ];
      final vm = BytecodeVm();
      expect(await vm.execute(chunks[0]), isTrue);
      expect(await vm.execute(chunks[1]), equals(3));
      expect(await vm.execute(chunks[2]), equals(-6));
      expect(await vm.execute(chunks[3]), equals(5));
    });

    test('unary minus coerces strings via NumberUtils', () async {
      final chunk = BytecodeCompiler().compile(parse('return -"4"'));
      final result = await BytecodeVm().execute(chunk);
      expect(result, equals(-4));
    });
  });
}
