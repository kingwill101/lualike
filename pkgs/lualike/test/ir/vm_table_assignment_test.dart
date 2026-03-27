@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrVm table assignments', () {
    test('executes table field assignment', () async {
      final program = parse('tbl.value = 99; return tbl.value');
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()..define('tbl', Value.wrap({'value': 1}));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(99));
    });

    test('executes table index assignment with literal', () async {
      final program = parse('arr[1] = "first"; return arr[1]');
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()..define('arr', Value.wrap({}));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals('first'));
    });

    test('executes table index assignment with dynamic key', () async {
      final program = parse('arr[idx] = 7; return arr[idx]');
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()
        ..define('arr', Value.wrap({}))
        ..define('idx', Value('foo'));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(7));
    });

    test('honours __newindex metamethod', () async {
      final program = parse('proxy.key = 1; return backing.key');
      final chunk = LualikeIrCompiler().compile(program);
      final backing = Value.wrap({});
      final proxy = Value.wrap({})
        ..metatable = {
          '__newindex': (List<Object?> args) {
            final key = args[1] is Value ? args[1] as Value : Value(args[1]);
            final value = args[2] is Value ? args[2] as Value : Value(args[2]);
            backing[key] = value;
            return null;
          },
        };
      final env = Environment()
        ..define('proxy', proxy)
        ..define('backing', backing);
      final result = await LualikeIrVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(1));
    });

    test('executes multi-target table field assignment', () async {
      final program = parse(
        'tbl.one, tbl.two = 10, 20; return tbl.one == 10 and tbl.two == 20',
      );
      final chunk = LualikeIrCompiler().compile(program);
      final env = Environment()
        ..define('tbl', Value.wrap({'one': 0, 'two': 0}));
      final result = await LualikeIrVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, isTrue);

      final tblValue = env.get('tbl') as Value?;
      final table = tblValue?.raw;
      expect(table, isA<Map>());
      final mapTable = table as Map;
      final first = mapTable['one'];
      final second = mapTable['two'];
      expect(first, isA<Value>());
      expect(second, isA<Value>());
      expect((first as Value).raw, equals(10));
      expect((second as Value).raw, equals(20));
    });
  });
}
