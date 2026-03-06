@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrVm calls', () {
    test('executes direct function call', () async {
      final chunk = LualikeIrCompiler().compile(parse('return inc(1)'));
      final env = Environment()
        ..define(
          'inc',
          Value((List<Object?> args) => ((args[0] as Value).raw as int) + 1),
        );
      final result = await LualikeIrVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(2));
    });

    test('executes tailcall and returns result', () async {
      final chunk = LualikeIrCompiler().compile(
        parse('return identity(value)'),
      );
      final env = Environment()
        ..define(
          'identity',
          Value((List<Object?> args) {
            if (args.isEmpty) {
              return null;
            }
            return args.first;
          }),
        )
        ..define('value', Value(42));

      final result = await LualikeIrVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(42));
    });
  });
}
