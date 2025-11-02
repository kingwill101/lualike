import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm table assignments', () {
    test('executes table field assignment', () async {
      final program = parse('tbl.value = 99; return tbl.value');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()..define('tbl', Value.wrap({'value': 1}));
      final result = await BytecodeVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(99));
    });

    test('executes table index assignment with literal', () async {
      final program = parse('arr[1] = "first"; return arr[1]');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()..define('arr', Value.wrap({}));
      final result = await BytecodeVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals('first'));
    });

    test('executes table index assignment with dynamic key', () async {
      final program = parse('arr[idx] = 7; return arr[idx]');
      final chunk = BytecodeCompiler().compile(program);
      final env = Environment()
        ..define('arr', Value.wrap({}))
        ..define('idx', Value('foo'));
      final result = await BytecodeVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(7));
    });

    test('honours __newindex metamethod', () async {
      final program = parse('proxy.key = 1; return backing.key');
      final chunk = BytecodeCompiler().compile(program);
      final backing = Value.wrap({});
      final proxy = Value.wrap({})
        ..metatable = {
          '__newindex': (List<Object?> args) {
            final table = args[0] as Value;
            final key = args[1] is Value ? args[1] as Value : Value(args[1]);
            final value = args[2] is Value ? args[2] as Value : Value(args[2]);
            backing[key] = value;
            return null;
          },
        };
      final env = Environment()
        ..define('proxy', proxy)
        ..define('backing', backing);
      final result = await BytecodeVm(environment: env).execute(chunk);
      final actual = result is Value ? result.raw : result;
      expect(actual, equals(1));
    });
  });
}
