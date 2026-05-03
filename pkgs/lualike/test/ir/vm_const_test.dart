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
  group('IR const locals', () {
    test('initialises const locals and returns their values', () async {
      const source = '''
local a <const>, b <const> = 1, 2
return a, b
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = _unwrapResult(await bridge.execute(source));
      expect(result, equals(<dynamic>[1, 2]));
    });

    test('propagates const locals through varargs', () async {
      const source = '''
local function pair(...)
  local x <const>, y <const> = ...
  return x, y
end

return pair(3, 4, 5)
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = _unwrapResult(await bridge.execute(source));
      expect(result, equals(<dynamic>[3, 4]));
    });

    test('raises when reassigning const local directly', () async {
      const source = '''
local a <const> = 1
a = 2
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      await expectLater(
        bridge.execute(source),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('raises when reassigning const local via upvalue', () async {
      const source = '''
local function outer()
  local a <const> = 10
  local function mutate()
    a = 20
  end
  mutate()
  return a
end

outer()
''';
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      await expectLater(
        bridge.execute(source),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('attempt to assign to const variable'),
          ),
        ),
      );
    });
  });
}
