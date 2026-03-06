import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/disassembler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';

Future<void> main() async {
  final program = parse('''
for idx, value in iter, state, control do
  tbl.sum = tbl.sum + value
end
return tbl.sum
''');
  final chunk = LualikeIrCompiler().compile(program);
  // ignore: avoid_print
  print(
    disassembleChunk(
      chunk,
      includeSubPrototypes: true,
      includeConstants: true,
      includeLineInfo: false,
    ),
  );
  final entries = <List<Object?>>[
    [1, 3],
    [2, 7],
  ];
  final iterator = Value((List<Object?> args) {
    final state = args[0];
    final control = args[1];
    // ignore: avoid_print
    print('iterator args: $args');
    final data = state is Value
        ? state.raw as List<List<Object?>>
        : state as List<List<Object?>>;
    final currentIndex = control is Value
        ? control.raw as int?
        : control as int?;
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

  final result = await LualikeIrVm(environment: env).execute(chunk);
  final unwrapped = result is Value ? result.raw : result;
  // ignore: avoid_print
  print('result=$unwrapped');
}
