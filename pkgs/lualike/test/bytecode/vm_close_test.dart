import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm to-be-closed locals', () {
    test('invokes __close before evaluating return expression', () async {
      final env = _buildEnv();
      const script = '''
local resource <close> = make()
return closed
''';

      final chunk = BytecodeCompiler().compile(parse(script));
      final result = await BytecodeVm(
        environment: env.environment,
      ).execute(chunk);

      expect(result, equals(true));
      expect(env.closedValue.raw, isTrue);
    });

    test('closes resources in do block scope', () async {
      final env = _buildEnv();
      const script = '''
do
  local resource <close> = make()
end
return closed
''';

      final chunk = BytecodeCompiler().compile(parse(script));
      final result = await BytecodeVm(
        environment: env.environment,
      ).execute(chunk);

      expect(result, equals(true));
      expect(env.closedValue.raw, isTrue);
    });

    test('closes resources in conditional branches', () async {
      final env = _buildEnv(extraBindings: {'flag': Value(true)});
      const script = '''
if flag then
  local resource <close> = make()
end
return closed
''';

      final chunk = BytecodeCompiler().compile(parse(script));
      final result = await BytecodeVm(
        environment: env.environment,
      ).execute(chunk);

      expect(result, equals(true));
      expect(env.closedValue.raw, isTrue);
    });

    test('closes resources inside while loop body each iteration', () async {
      final env = _buildCountingEnv();
      const script = '''
local closed = 0
while closed < 2 do
  local resource <close> = make()
  closed = closed + 1
end
return closed
''';

      final chunk = BytecodeCompiler().compile(parse(script));
      final result = await BytecodeVm(
        environment: env.environment,
      ).execute(chunk);

      expect(result, equals(2));
      expect(env.closeCount.value, equals(2));
    });
  });
}

class _EnvContext {
  _EnvContext({required this.environment, required this.closedValue});

  final Environment environment;
  final Value closedValue;
}

class _CountingContext {
  _CountingContext({required this.environment, required this.closeCount});

  final Environment environment;
  final _CloseCounter closeCount;
}

_EnvContext _buildEnv({Map<String, Value> extraBindings = const {}}) {
  final closedValue = Value(false);
  final environment = Environment()
    ..define('closed', closedValue)
    ..define(
      'make',
      Value((List<Object?> _) {
        final resource = Value(<String, dynamic>{});
        resource.metatable = {
          '__close': (List<Object?> _) {
            closedValue.raw = true;
            return null;
          },
        };
        return resource;
      }),
    );
  for (final entry in extraBindings.entries) {
    environment.define(entry.key, entry.value);
  }
  return _EnvContext(environment: environment, closedValue: closedValue);
}

_CountingContext _buildCountingEnv() {
  final counter = _CloseCounter();
  final environment = Environment()
    ..define('closed', Value(0))
    ..define(
      'make',
      Value((List<Object?> _) {
        final resource = Value(<String, dynamic>{});
        resource.metatable = {
          '__close': (List<Object?> _) {
            counter.value += 1;
            return null;
          },
        };
        return resource;
      }),
    );
  return _CountingContext(environment: environment, closeCount: counter);
}

class _CloseCounter {
  int value = 0;
}
