import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  dynamic _unwrap(dynamic value) => value is Value ? value.raw : value;

  group('BytecodeVm branching', () {
    test('executes if/else branches', () async {
      final program = parse('''
        if cond then
          tbl.value = tbl.value + 1
        else
          tbl.value = tbl.value - 1
        end
        return tbl.value
      ''');
      final chunk = BytecodeCompiler().compile(program);

      final envTrue = Environment()
        ..define('cond', Value(true))
        ..define('tbl', Value.wrap({'value': 1}));
      final resultTrue = await BytecodeVm(environment: envTrue).execute(chunk);
      expect(_unwrap(resultTrue), equals(2));

      final envFalse = Environment()
        ..define('cond', Value(false))
        ..define('tbl', Value.wrap({'value': 1}));
      final resultFalse = await BytecodeVm(
        environment: envFalse,
      ).execute(chunk);
      expect(_unwrap(resultFalse), equals(0));
    });

    test('executes while loop', () async {
      final program = parse('''
        while state.i < 3 do
          state.i = state.i + 1
        end
        return state.i
      ''');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()..define('state', Value.wrap({'i': 0}));
      final result = await BytecodeVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(3));
    });

    test('short-circuit and/or expressions', () async {
      final compiler = BytecodeCompiler();
      final andChunk = compiler.compile(parse('return cond and arr[1]'));
      final orChunk = compiler.compile(parse('return cond or arr[1]'));

      final envAndTrue = Environment()
        ..define('cond', Value(true))
        ..define('arr', Value.wrap({1: 42}));
      final andTrue = await BytecodeVm(
        environment: envAndTrue,
      ).execute(andChunk);
      expect(_unwrap(andTrue), equals(42));

      final envAndFalse = Environment()
        ..define('cond', Value(false))
        ..define('arr', Value.wrap({1: 42}));
      final andFalse = await BytecodeVm(
        environment: envAndFalse,
      ).execute(andChunk);
      expect(_unwrap(andFalse), isFalse);

      final envOrTrue = Environment()
        ..define('cond', Value(true))
        ..define('arr', Value.wrap({1: 7}));
      final orTrue = await BytecodeVm(environment: envOrTrue).execute(orChunk);
      expect(_unwrap(orTrue), isTrue);

      final envOrFalse = Environment()
        ..define('cond', Value(false))
        ..define('arr', Value.wrap({1: 7}));
      final orFalse = await BytecodeVm(
        environment: envOrFalse,
      ).execute(orChunk);
      expect(_unwrap(orFalse), equals(7));
    });
  });
}
