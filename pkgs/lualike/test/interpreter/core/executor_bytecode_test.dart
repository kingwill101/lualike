import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

dynamic _unwrap(dynamic value) => value is Value ? value.raw : value;

void main() {
  group('executeCode bytecode mode', () {
    test('returns numeric literal', () async {
      final result = await executeCode('return 99', mode: EngineMode.bytecode);
      expect(result, equals(99));
    });

    test('returns nil when no explicit return', () async {
      final result = await executeCode('', mode: EngineMode.bytecode);
      expect(result, isNull);
    });

    test('evaluates arithmetic with globals', () async {
      final result = await executeCode(
        'return x + 3',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('x', Value(4));
        },
      );
      expect(result, equals(7));
    });

    test('evaluates bitwise expressions with globals', () async {
      final result = await executeCode(
        'return x & 3',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('x', Value(6));
        },
      );
      expect(result, equals(2));
    });

    test('evaluates comparison expressions', () async {
      final result = await executeCode(
        'return a < b',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('a', Value(3))
            ..define('b', Value(4));
        },
      );
      expect(result, isTrue);
    });

    test('evaluates unary expressions', () async {
      final result = await executeCode(
        'return not flag',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('flag', Value(false));
        },
      );
      expect(result, isTrue);
    });

    test('coerces string numbers via NumberUtils', () async {
      final result = await executeCode(
        'return "8" / "2"',
        mode: EngineMode.bytecode,
      );
      expect(result, equals(4));
    });

    test('evaluates modulo, floor division, and exponent', () async {
      final results = await Future.wait([
        executeCode('return 9 % 4', mode: EngineMode.bytecode),
        executeCode('return 9 // 4', mode: EngineMode.bytecode),
        executeCode('return "2" ^ 5', mode: EngineMode.bytecode),
      ]);
      expect(results[0], equals(1));
      expect(results[1], equals(2));
      expect(results[2], equals(32));
    });

    test('evaluates comparisons against literals', () async {
      final results = await Future.wait([
        executeCode(
          'return x == "foo"',
          mode: EngineMode.bytecode,
          onRuntimeSetup: (runtime) {
            runtime.globals.define('x', Value('foo'));
          },
        ),
        executeCode('return 5 < 10', mode: EngineMode.bytecode),
        executeCode('return 7 >= 7', mode: EngineMode.bytecode),
      ]);
      expect(results[0], isTrue);
      expect(results[1], isTrue);
      expect(results[2], isTrue);
    });

    test('evaluates table access expressions', () async {
      final result = await executeCode(
        'return tbl.value + arr[idx]',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('tbl', Value.wrap({'value': 5}))
            ..define('arr', Value.wrap({'foo': 7}))
            ..define('idx', Value('foo'));
        },
      );
      expect(result, equals(12));
    });

    test('evaluates table assignment expressions', () async {
      final result = await executeCode(
        'tbl.value = 10; arr[1] = tbl.value; return arr[1]',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals
            ..define('tbl', Value.wrap({'value': 5}))
            ..define('arr', Value.wrap({}));
        },
      );
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(10));
    });

    test('executes if/else control flow', () async {
      Future<dynamic> run(bool condValue) {
        return executeCode(
          '''
            if cond then
              state.value = state.value + 1
            else
              state.value = state.value - 1
            end
            return state.value
          ''',
          mode: EngineMode.bytecode,
          onRuntimeSetup: (runtime) {
            runtime.globals
              ..define('cond', Value(condValue))
              ..define('state', Value.wrap({'value': 2}));
          },
        );
      }

      final resultTrue = _unwrap(await run(true));
      final resultFalse = _unwrap(await run(false));
      expect(resultTrue, equals(3));
      expect(resultFalse, equals(1));
    });

    test('executes while loops', () async {
      final result = _unwrap(await executeCode(
        '''
          while state.i < 4 do
            state.i = state.i + 1
          end
          return state.i
        ''',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('state', Value.wrap({'i': 0}));
        },
      ));
      expect(result, equals(4));
    });

    test('applies short-circuit boolean semantics', () async {
      final andResults = await Future.wait([
        executeCode(
          'return cond and arr[1]',
          mode: EngineMode.bytecode,
          onRuntimeSetup: (runtime) {
            runtime.globals
              ..define('cond', Value(true))
              ..define('arr', Value.wrap({1: 42}));
          },
        ),
        executeCode(
          'return cond and arr[1]',
          mode: EngineMode.bytecode,
          onRuntimeSetup: (runtime) {
            runtime.globals
              ..define('cond', Value(false))
              ..define('arr', Value.wrap({1: 42}));
          },
        ),
      ]);

      final orResults = await Future.wait([
        executeCode(
          'return cond or arr[1]',
          mode: EngineMode.bytecode,
          onRuntimeSetup: (runtime) {
            runtime.globals
              ..define('cond', Value(true))
              ..define('arr', Value.wrap({1: 7}));
          },
        ),
        executeCode(
          'return cond or arr[1]',
          mode: EngineMode.bytecode,
          onRuntimeSetup: (runtime) {
            runtime.globals
              ..define('cond', Value(false))
              ..define('arr', Value.wrap({1: 7}));
          },
        ),
      ]);

      final unwrappedAnd = andResults.map(_unwrap).toList(growable: false);
      expect(unwrappedAnd[0], equals(42));
      expect(unwrappedAnd[1], isFalse);

      final unwrappedOr = orResults.map(_unwrap).toList(growable: false);
      expect(unwrappedOr[0], isTrue);
      expect(unwrappedOr[1], equals(7));
    });

    test('executes numeric for loops', () async {
      final result = await executeCode(
        '''
          for i = 1, 4 do
            tbl.sum = tbl.sum + i
          end
          return tbl.sum
        ''',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals.define('tbl', Value.wrap({'sum': 0}));
        },
      );

      expect(_unwrap(result), equals(10));
    });

    test('executes generic for loops', () async {
      final result = await executeCode(
        '''
          for idx, value in iter, state, control do
            tbl.sum = tbl.sum + value
          end
          return tbl.sum
        ''',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          final entries = <List<Object?>>[
            [1, 3],
            [2, 7],
          ];

          final iterator = Value((List<Object?> args) {
            final state = args[0];
            final control = args[1];
            final data = state is Value
                ? state.raw as List<List<Object?>>
                : state as List<List<Object?>>;
            final currentIndex = control is Value ? control.raw as int? : control as int?;
            final nextIndex = (currentIndex ?? 0) + 1;
            if (nextIndex > data.length) {
              return Value.multi(const []);
            }
            final entry = data[nextIndex - 1];
            return Value.multi([nextIndex, entry[0], entry[1]]);
          });

          runtime.globals
            ..define('iter', iterator)
            ..define('state', Value(entries))
            ..define('control', Value(0))
            ..define('tbl', Value.wrap({'sum': 0}));
        },
      );

      expect(_unwrap(result), equals(10));
    });

    test('executes function calls', () async {
      final result = await executeCode(
        'return inc(5)',
        mode: EngineMode.bytecode,
        onRuntimeSetup: (runtime) {
          runtime.globals.define(
            'inc',
            Value((List<Object?> args) => (args[0] as int) + 1),
          );
        },
      );

      expect(result, equals(6));
    });
  });
}
