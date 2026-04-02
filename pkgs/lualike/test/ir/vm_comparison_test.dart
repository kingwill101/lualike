@Tags(['ir'])
library;

import 'package:lualike/src/environment.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('Lualike IR lowered comparisons', () {
    test('executes comparisons', () async {
      expect(await executeCode('return 3 < 4', mode: EngineMode.ir), isTrue);
      expect(await executeCode('return 4 >= 4', mode: EngineMode.ir), isTrue);
      expect(await executeCode('return 4 > 5', mode: EngineMode.ir), isFalse);
      expect(await executeCode('return 5 <= 5', mode: EngineMode.ir), isTrue);
    });

    test('executes equality and inequality', () async {
      expect(await executeCode('return 3 == 3', mode: EngineMode.ir), isTrue);
      expect(await executeCode('return 3 ~= 4', mode: EngineMode.ir), isTrue);
    });

    test('executes equality with string literal', () async {
      final env = EnvironmentFactory.stringEnv('foo');
      expect(
        await executeCode(
          'return x == "foo"',
          mode: EngineMode.ir,
          onRuntimeSetup: (runtime) => runtime.globals.define('x', env.get('x')!),
        ),
        isTrue,
      );
    });

    test('executes literal comparisons with integers', () async {
      final env = EnvironmentFactory.intEnv(5);
      expect(
        await executeCode(
          'return x == 5',
          mode: EngineMode.ir,
          onRuntimeSetup: (runtime) => runtime.globals.define('x', env.get('x')!),
        ),
        isTrue,
      );
      expect(
        await executeCode(
          'return x < 10',
          mode: EngineMode.ir,
          onRuntimeSetup: (runtime) => runtime.globals.define('x', env.get('x')!),
        ),
        isTrue,
      );
      expect(
        await executeCode(
          'return x >= 3',
          mode: EngineMode.ir,
          onRuntimeSetup: (runtime) => runtime.globals.define('x', env.get('x')!),
        ),
        isTrue,
      );
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
