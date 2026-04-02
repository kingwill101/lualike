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
  group('IR metamethods', () {
    test('invokes __add when operands provide metamethod', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = await bridge.execute('''
        local mt = {
          __add = function(left, right)
            return left.value + right.value + 10
          end,
        }
        local lhs = setmetatable({value = 2}, mt)
        local rhs = setmetatable({value = 3}, mt)
        return lhs + rhs
      ''');
      expect(result, equals(15));
    });

    test('invokes __concat when operands provide metamethod', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final result = _unwrapResult(await bridge.execute('''
        local mt = {
          __concat = function(left, right)
            return 'meta:' .. left.value .. '+' .. right.value
          end,
        }
        local left = setmetatable({value = 'A'}, mt)
        local right = setmetatable({value = 'B'}, mt)
        return left .. right
      '''));
      expect(result, equals('meta:A+B'));
    });
  });
}
