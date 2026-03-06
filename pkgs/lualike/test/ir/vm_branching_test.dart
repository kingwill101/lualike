@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  dynamic _unwrap(dynamic value) => value is Value ? value.raw : value;

  group('LualikeIrVm branching', () {
    test('executes if/else branches', () async {
      final program = parse('''
        if cond then
          tbl.value = tbl.value + 1
        else
          tbl.value = tbl.value - 1
        end
        return tbl.value
      ''');
      final chunk = LualikeIrCompiler().compile(program);

      final envTrue = Environment()
        ..define('cond', Value(true))
        ..define('tbl', Value.wrap({'value': 1}));
      final resultTrue = await LualikeIrVm(environment: envTrue).execute(chunk);
      expect(_unwrap(resultTrue), equals(2));

      final envFalse = Environment()
        ..define('cond', Value(false))
        ..define('tbl', Value.wrap({'value': 1}));
      final resultFalse = await LualikeIrVm(
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
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()..define('state', Value.wrap({'i': 0}));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      expect(_unwrap(result), equals(3));
    });

    test('short-circuit and/or expressions', () async {
      final compiler = LualikeIrCompiler();
      final andChunk = compiler.compile(parse('return cond and arr[1]'));
      final orChunk = compiler.compile(parse('return cond or arr[1]'));

      final envAndTrue = Environment()
        ..define('cond', Value(true))
        ..define('arr', Value.wrap({1: 42}));
      final andTrue = await LualikeIrVm(
        environment: envAndTrue,
      ).execute(andChunk);
      expect(_unwrap(andTrue), equals(42));

      final envAndFalse = Environment()
        ..define('cond', Value(false))
        ..define('arr', Value.wrap({1: 42}));
      final andFalse = await LualikeIrVm(
        environment: envAndFalse,
      ).execute(andChunk);
      expect(_unwrap(andFalse), isFalse);

      final envOrTrue = Environment()
        ..define('cond', Value(true))
        ..define('arr', Value.wrap({1: 7}));
      final orTrue = await LualikeIrVm(environment: envOrTrue).execute(orChunk);
      expect(_unwrap(orTrue), isTrue);

      final envOrFalse = Environment()
        ..define('cond', Value(false))
        ..define('arr', Value.wrap({1: 7}));
      final orFalse = await LualikeIrVm(
        environment: envOrFalse,
      ).execute(orChunk);
      expect(_unwrap(orFalse), equals(7));
    });
  });
}
