@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('IR calls', () {
    test('executes direct function call', () async {
      final result = await executeCode(
        'return inc(1)',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define(
            'inc',
            Value((List<Object?> args) => ((args[0] as Value).raw as int) + 1),
          );
        },
      );
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(2));
    });

    test('executes tailcall and returns result', () async {
      final result = await executeCode(
        'return identity(value)',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
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
        },
      );

      final actual = result is Value ? result.raw : result;
      expect(actual, equals(42));
    });
  });
}
