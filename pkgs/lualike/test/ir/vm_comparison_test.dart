@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrVm comparisons', () {
    test('executes comparisons', () async {
      final ltChunk = LualikeIrCompiler().compile(parse('return 3 < 4'));
      final geChunk = LualikeIrCompiler().compile(parse('return 4 >= 4'));
      final gtChunk = LualikeIrCompiler().compile(parse('return 4 > 5'));
      final leChunk = LualikeIrCompiler().compile(parse('return 5 <= 5'));
      expect(await LualikeIrVm().execute(ltChunk), isTrue);
      expect(await LualikeIrVm().execute(geChunk), isTrue);
      expect(await LualikeIrVm().execute(gtChunk), isFalse);
      expect(await LualikeIrVm().execute(leChunk), isTrue);
    });

    test('executes equality and inequality', () async {
      final eqChunk = LualikeIrCompiler().compile(parse('return 3 == 3'));
      final neqChunk = LualikeIrCompiler().compile(parse('return 3 ~= 4'));
      expect(await LualikeIrVm().execute(eqChunk), isTrue);
      expect(await LualikeIrVm().execute(neqChunk), isTrue);
    });

    test('executes equality with string literal', () async {
      final program = parse('return x == "foo"');
      final chunk = LualikeIrCompiler().compile(program);
      final env = EnvironmentFactory.stringEnv('foo');
      final vm = LualikeIrVm(environment: env);
      expect(await vm.execute(chunk), isTrue);
    });

    test('executes literal comparisons with integers', () async {
      final eqChunk = LualikeIrCompiler().compile(parse('return x == 5'));
      final ltChunk = LualikeIrCompiler().compile(parse('return x < 10'));
      final geChunk = LualikeIrCompiler().compile(parse('return x >= 3'));
      final env = EnvironmentFactory.intEnv(5);
      final vm = LualikeIrVm(environment: env);
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
