import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

dynamic _unwrap(dynamic value) => value is Value ? value.raw : value;

void main() {
  group('BytecodeVm numeric for loops', () {
    test('executes ascending loop', () async {
      final program = parse('''
        for i = 1, 3 do
          tbl.sum = tbl.sum + i
        end
        return tbl.sum
      ''');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()..define('tbl', Value.wrap({'sum': 0}));
      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(6));
    });

    test('executes descending loop', () async {
      final program = parse('''
        for i = 3, 1, -1 do
          tbl.count = tbl.count + 1
        end
        return tbl.count
      ''');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()..define('tbl', Value.wrap({'count': 0}));
      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(3));
    });
  });

  group('BytecodeVm generic for loops', () {
    test('executes iterator-based loop', () async {
      final program = parse('''
        for idx, value in iter, state, control do
          tbl.sum = tbl.sum + value
        end
        return tbl.sum
      ''');
      final chunk = BytecodeCompiler().compile(program);

      final entries = <List<Object?>>[
        [1, 10],
        [2, 20],
      ];

      final iterator = Value((List<Object?> args) {
        final state = args[0];
        final control = args[1];
        final data = state is Value ? state.raw as List<List<Object?>> : state as List<List<Object?>>;
        final currentIndex = control is Value ? control.raw as int? : control as int?;
        final nextIndex = (currentIndex ?? 0) + 1;
        if (nextIndex > data.length) {
          return Value.multi(const []);
        }
        final entry = data[nextIndex - 1];
        return Value.multi([nextIndex, entry[0], entry[1]]);
      });

      final env = Environment()
        ..define('iter', iterator)
        ..define('state', Value(entries))
        ..define('control', Value(0))
        ..define('tbl', Value.wrap({'sum': 0}));

      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(30));
    });
  });
}
