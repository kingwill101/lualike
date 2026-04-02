@Tags(['ir'])
library;

import 'package:lualike/src/interop.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('IR to-be-closed locals', () {
    test('captures return values before invoking __close', () async {
      final env = _buildEnv();
      const script = '''
local resource <close> = make()
return closed == false
''';

      final result = await _executeWithBindings(script, env.bindings);

      expect(_unwrap(result), isTrue);
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

      final result = await _executeWithBindings(script, env.bindings);

      expect(_unwrap(result), equals(true));
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

      final result = await _executeWithBindings(script, env.bindings);

      expect(_unwrap(result), equals(true));
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

      final result = await _executeWithBindings(script, env.bindings);

      expect(_unwrap(result), equals(2));
      expect(env.closeCount.value, equals(2));
    });
  });
}

Future<Object?> _executeWithBindings(
  String source,
  Map<String, Value> bindings,
) async {
  final bridge = LuaLike(runtime: LualikeIrRuntime());
  for (final entry in bindings.entries) {
    bridge.vm.globals.define(entry.key, entry.value);
  }
  return bridge.execute(source);
}

Object? _unwrap(Object? value) {
  if (value is Value) {
    return _unwrap(value.raw);
  }
  if (value is List) {
    return value.map(_unwrap).toList();
  }
  return value;
}

class _EnvContext {
  _EnvContext({required this.bindings, required this.closedValue});

  final Map<String, Value> bindings;
  final Value closedValue;
}

class _CountingContext {
  _CountingContext({required this.bindings, required this.closeCount});

  final Map<String, Value> bindings;
  final _CloseCounter closeCount;
}

_EnvContext _buildEnv({Map<String, Value> extraBindings = const {}}) {
  final closedValue = Value(false);
  final bindings = <String, Value>{
    'closed': closedValue,
    'make': Value((List<Object?> _) {
      final resource = Value(<String, dynamic>{});
      resource.metatable = {
        '__close': (List<Object?> _) {
          closedValue.raw = true;
          return null;
        },
      };
      return resource;
    }),
    ...extraBindings,
  };
  return _EnvContext(bindings: bindings, closedValue: closedValue);
}

_CountingContext _buildCountingEnv() {
  final counter = _CloseCounter();
  final bindings = <String, Value>{
    'closed': Value(0),
    'make': Value((List<Object?> _) {
      final resource = Value(<String, dynamic>{});
      resource.metatable = {
        '__close': (List<Object?> _) {
          counter.value += 1;
          return null;
        },
      };
      return resource;
    }),
  };
  return _CountingContext(bindings: bindings, closeCount: counter);
}

class _CloseCounter {
  int value = 0;
}
