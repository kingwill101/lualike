import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm comparisons', () {
    test('executes comparisons', () async {
      final ltChunk = BytecodeCompiler().compile(parse('return 3 < 4'));
      final geChunk = BytecodeCompiler().compile(parse('return 4 >= 4'));
      final gtChunk = BytecodeCompiler().compile(parse('return 4 > 5'));
      final leChunk = BytecodeCompiler().compile(parse('return 5 <= 5'));
      expect(await BytecodeVm().execute(ltChunk), isTrue);
      expect(await BytecodeVm().execute(geChunk), isTrue);
      expect(await BytecodeVm().execute(gtChunk), isFalse);
      expect(await BytecodeVm().execute(leChunk), isTrue);
    });

    test('executes equality and inequality', () async {
      final eqChunk = BytecodeCompiler().compile(parse('return 3 == 3'));
      final neqChunk = BytecodeCompiler().compile(parse('return 3 ~= 4'));
      expect(await BytecodeVm().execute(eqChunk), isTrue);
      expect(await BytecodeVm().execute(neqChunk), isTrue);
    });

    test('executes equality with string literal', () async {
      final program = parse('return x == "foo"');
      final chunk = BytecodeCompiler().compile(program);
      final env = EnvironmentFactory.stringEnv('foo');
      final vm = BytecodeVm(environment: env);
      expect(await vm.execute(chunk), isTrue);
    });

    test('executes literal comparisons with integers', () async {
      final eqChunk = BytecodeCompiler().compile(parse('return x == 5'));
      final ltChunk = BytecodeCompiler().compile(parse('return x < 10'));
      final geChunk = BytecodeCompiler().compile(parse('return x >= 3'));
      final env = EnvironmentFactory.intEnv(5);
      final vm = BytecodeVm(environment: env);
      expect(await vm.execute(eqChunk), isTrue);
      expect(await vm.execute(ltChunk), isTrue);
      expect(await vm.execute(geChunk), isTrue);
    });
  });
}

/// Helpers for constructing VMs with pre-populated environments.
class EnvironmentFactory {
  static Environment stringEnv(String value) {
    return Environment()..define('x', Value(value));
  }

  static Environment intEnv(int value) {
    return Environment()..define('x', Value(value));
  }
}
