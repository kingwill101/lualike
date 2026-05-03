@Tags(['ir'])
library;

import 'package:lualike/src/interop.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

Object? _unwrap(dynamic value) {
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

void main() {
  group('IR unary metamethods', () {
    test('__unm receives operand twice and returns first result', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final outcome = await bridge.execute(r'''
        local captures = {}
        local subject = setmetatable({}, {
          __unm = function(...)
            local args = {...}
            captures.count = #args
            captures.first = args[1]
            captures.second = args[2]
            return ...
          end
        })
        local result = -subject
        return captures.count, captures.first, captures.second, result
      ''');
      expect(outcome, isA<List>());
      final results = outcome as List<dynamic>;
      expect(results, hasLength(4));
      expect(_unwrap(results[0]), equals(2));
      final first = results[1] as Value;
      final second = results[2] as Value;
      final unary = results[3] as Value;
      expect(identical(first, second), isTrue);
      expect(identical(first.raw, second.raw), isTrue);
      expect(identical(unary, first), isTrue);
    });

    test('__bnot receives operand twice', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final outcome = await bridge.execute(r'''
        local captures = {}
        local subject = setmetatable({}, {
          __bnot = function(...)
            local args = {...}
            captures.count = #args
            captures.first = args[1]
            captures.second = args[2]
            return ...
          end
        })
        local result = ~subject
        return captures.count, captures.first, captures.second, result
      ''');
      expect(outcome, isA<List>());
      final results = outcome as List<dynamic>;
      expect(results, hasLength(4));
      expect(_unwrap(results[0]), equals(2));
      expect(results[1], isA<Value>());
      expect(results[2], isA<Value>());
      expect(results[3], isA<Value>());
    });

    test('__len receives operand twice', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final outcome = await bridge.execute(r'''
        local captures = {}
        local subject = setmetatable({}, {
          __len = function(...)
            local args = {...}
            captures.count = #args
            captures.first = args[1]
            captures.second = args[2]
            return ...
          end
        })
        local result = #subject
        return captures.count, captures.first, captures.second, result
      ''');
      expect(outcome, isA<List>());
      final results = outcome as List<dynamic>;
      expect(results, hasLength(4));
      expect(_unwrap(results[0]), equals(2));
      expect(results[1], isA<Value>());
      expect(results[2], isA<Value>());
      expect(results[3], isA<Value>());
    });
  });
}
