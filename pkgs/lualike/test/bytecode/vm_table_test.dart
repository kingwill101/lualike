import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm tables', () {
    test('executes table field access', () async {
      final program = parse('return tbl.value');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()..define('tbl', Value.wrap({'value': 42}));
      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(result is Value ? result.raw : result, equals(42));
    });

    test('executes table index access with literal', () async {
      final program = parse('return arr[1]');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()..define('arr', Value.wrap({1: 'first'}));
      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(result is Value ? result.raw : result, equals('first'));
    });

    test('executes table index access with dynamic key', () async {
      final program = parse('return arr[idx]');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()
        ..define('arr', Value.wrap({'foo': 99}))
        ..define('idx', Value('foo'));
      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(result is Value ? result.raw : result, equals(99));
    });
  });
}
