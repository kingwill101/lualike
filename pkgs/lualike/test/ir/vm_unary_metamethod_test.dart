@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

dynamic _unwrap(dynamic value) => value is Value ? value.raw : value;

dynamic _compile(String source) {
  final program = parse(source);
  return LualikeIrCompiler().compile(program);
}

void main() {
  group('LualikeIrVm unary metamethods', () {
    test('__unm receives operand twice and returns first result', () async {
      final chunk = _compile(r'''
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
      final runtime = LualikeIrRuntime();
      final vm = LualikeIrVm(environment: runtime.globals, runtime: runtime);
      final outcome = await vm.execute(chunk);
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
      final chunk = _compile(r'''
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
      final runtime = LualikeIrRuntime();
      final vm = LualikeIrVm(environment: runtime.globals, runtime: runtime);
      final outcome = await vm.execute(chunk);
      expect(outcome, isA<List>());
      final results = outcome as List<dynamic>;
      expect(results, hasLength(4));
      expect(_unwrap(results[0]), equals(2));
      expect(results[1], isA<Value>());
      expect(results[2], isA<Value>());
      expect(results[3], isA<Value>());
    });

    test('__len receives operand twice', () async {
      final chunk = _compile(r'''
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
      final runtime = LualikeIrRuntime();
      final vm = LualikeIrVm(environment: runtime.globals, runtime: runtime);
      final outcome = await vm.execute(chunk);
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
