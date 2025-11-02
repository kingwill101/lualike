import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm metamethods', () {
    test('invokes __add when operands provide metamethod', () async {
      final chunk = BytecodeCompiler().compile(parse('return lhs + rhs'));
      final metatable = <String, dynamic>{
        '__add': (List<Object?> args) {
          final left = args[0] as Value;
          final right = args[1] as Value;
          final leftValue = (left.raw as Map)['value'] as num;
          final rightValue = (right.raw as Map)['value'] as num;
          return Value(leftValue + rightValue + 10);
        },
      };
      final lhs = Value(<String, dynamic>{'value': 2})..metatable = metatable;
      final rhs = Value(<String, dynamic>{'value': 3})..metatable = metatable;
      final env = Environment()
        ..define('lhs', lhs)
        ..define('rhs', rhs);

      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(result, equals(15));
    });

    test('invokes __concat when operands provide metamethod', () async {
      final chunk = BytecodeCompiler().compile(parse('return left .. right'));
      final metatable = <String, dynamic>{
        '__concat': (List<Object?> args) {
          final left = args[0] as Value;
          final right = args[1] as Value;
          final leftText = (left.raw as Map)['value'] as String;
          final rightText = (right.raw as Map)['value'] as String;
          return Value('meta:$leftText+$rightText');
        },
      };
      final left = Value(<String, dynamic>{'value': 'A'})
        ..metatable = metatable;
      final right = Value(<String, dynamic>{'value': 'B'})
        ..metatable = metatable;
      final env = Environment()
        ..define('left', left)
        ..define('right', right);

      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(result, equals('meta:A+B'));
    });
  });
}
