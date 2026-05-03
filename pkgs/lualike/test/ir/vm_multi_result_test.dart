@Tags(['ir'])
library;

import 'package:lualike/src/interop.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

Object? _unwrapResult(Object? value) {
  if (value is Value) {
    return _unwrapResult(value.raw);
  }
  if (value is LuaString) {
    return value.toString();
  }
  if (value is List) {
    return value.map(_unwrapResult).toList();
  }
  return value;
}

void main() {
  group('IR multi-result execution', () {
    test('returns multiple explicit values', () async {
      const source = 'local function pair() return 2, 3 end\nreturn pair()';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = _unwrapResult(await bridge.execute(source));
      expect(result, equals(<dynamic>[2, 3]));
    });

    test(
      'returns trailing call results in addition to prefix values',
      () async {
        const source = '''
local function helper()
  return 4, 5, 6
end

local prefix = 1
return prefix, helper()
''';
        final bridge = LuaLike(runtime: LualikeIrRuntime());
        final result = _unwrapResult(await bridge.execute(source));
        expect(result, equals(<dynamic>[1, 4, 5, 6]));
      },
    );

    test('multi-target assignment stores all call results', () async {
      const source = '''
local function pair()
  return 7, 8
end

local a, b
a, b = pair()
return a, b
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = _unwrapResult(await bridge.execute(source));
      expect(result, equals(<dynamic>[7, 8]));
    });

    test('local declarations propagate varargs with nil fill', () async {
      const source =
          'local function passthrough(...) return ... end\n'
          'local x, y, z = passthrough(9)\nreturn x, y, z';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = _unwrapResult(await bridge.execute(source));
      expect(result, equals(<dynamic>[9, null, null]));
    });
  });
}
