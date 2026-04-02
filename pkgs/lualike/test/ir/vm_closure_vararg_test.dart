@Tags(['ir'])
library;

import 'package:lualike/src/interop.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('IR closures and varargs', () {
    test('executes nested closure capturing outer variable', () async {
      const source = '''
local function outer(x)
  local function inner()
    return x
  end

  return inner()
end

return outer(5)
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute(source);
      expect(_unwrap(result), equals(5));
    });

    test('returns all varargs from lualike IR function', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute(
        'return (function(...) return ... end)(1, 2, 3)',
      );
      expect(_unwrap(result), equals(<dynamic>[1, 2, 3]));
    });

    test('forwards varargs through nested closure', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute(
        'return (function(...) return (function(...) return ... end)(...) end)(4, 5)',
      );
      expect(_unwrap(result), equals(<dynamic>[4, 5]));
    });

    test('packs named vararg tables for lualike IR functions', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute('''
local function pack(...t)
  return t.n, t[1], t[2], t[3]
end

return pack(10, nil, 30)
''');
      expect(_unwrap(result), equals(<dynamic>[3, 10, null, 30]));
    });

    test('evaluates tail recursive factorial', () async {
      const source = '''
function fact(n, acc)
  if n == 0 then
    return acc
  else
    return fact(n - 1, acc * n)
  end
end

return fact(5, 1)
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute(source);
      expect(_unwrap(result), equals(120));
    });

    test('mutates captured local through SETUPVAL', () async {
      const source = '''
local count = 0
local function bump()
  count = count + 1
  return count
end

bump()
return bump()
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute(source);
      expect(_unwrap(result), equals(2));
    });

    test('installs lualike IR-defined method and updates table', () async {
      const source = '''
function store(self, v)
  self.value = v
end

_ENV.value = 0
_ENV.store = store
_ENV:store(42)
return _ENV.value
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final globals = Value.wrap(<dynamic, dynamic>{});
      globals['_ENV'] = globals;
      globals['_G'] = globals;
      bridge.vm.globals
        ..define('_ENV', globals)
        ..define('_G', globals);
      final result = await bridge.execute(source);
      expect(_unwrap(result), equals(42));
    });

    test('_ENV assignments propagate via SETTABUP', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute('_ENV.result = 11; return result');
      expect(_unwrap(result), equals(11));
    });
  });
}

dynamic _unwrap(dynamic value) {
  if (value is Value) {
    return _unwrap(value.raw);
  }
  if (value is LuaString) {
    return value.toString();
  }
  if (value is List) {
    return value.map(_unwrap).toList();
  }
  return value;
}
