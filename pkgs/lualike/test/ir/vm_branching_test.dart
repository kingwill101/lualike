@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  dynamic unwrap(dynamic value) => value is Value ? value.raw : value;

  group('IR branching', () {
    test('executes if/else branches', () async {
      final resultTrue = await executeCode(
        '''
        if cond then
          tbl.value = tbl.value + 1
        else
          tbl.value = tbl.value - 1
        end
        return tbl.value
        ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('cond', Value(true))
            ..define('tbl', Value.wrap({'value': 1}));
        },
      );
      expect(unwrap(resultTrue), equals(2));

      final resultFalse = await executeCode(
        '''
        if cond then
          tbl.value = tbl.value + 1
        else
          tbl.value = tbl.value - 1
        end
        return tbl.value
        ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('cond', Value(false))
            ..define('tbl', Value.wrap({'value': 1}));
        },
      );
      expect(unwrap(resultFalse), equals(0));
    });

    test('executes while loop', () async {
      final result = await executeCode(
        '''
        while state.i < 3 do
          state.i = state.i + 1
        end
        return state.i
        ''',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('state', Value.wrap({'i': 0}));
        },
      );
      expect(unwrap(result), equals(3));
    });

    test('short-circuit and/or expressions', () async {
      final andTrue = await executeCode(
        'return cond and arr[1]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('cond', Value(true))
            ..define('arr', Value.wrap({1: 42}));
        },
      );
      expect(unwrap(andTrue), equals(42));

      final andFalse = await executeCode(
        'return cond and arr[1]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('cond', Value(false))
            ..define('arr', Value.wrap({1: 42}));
        },
      );
      expect(unwrap(andFalse), isFalse);

      final orTrue = await executeCode(
        'return cond or arr[1]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('cond', Value(true))
            ..define('arr', Value.wrap({1: 7}));
        },
      );
      expect(unwrap(orTrue), isTrue);

      final orFalse = await executeCode(
        'return cond or arr[1]',
        mode: EngineMode.ir,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('cond', Value(false))
            ..define('arr', Value.wrap({1: 7}));
        },
      );
      expect(unwrap(orFalse), equals(7));
    });
  });
}
