import 'package:lualike_test/test.dart';
import 'package:lualike/src/interpreter/ast_local_frame.dart';

void main() {
  group('pooled function bindings', () {
    test('nested capture analysis never marks outer-only identifiers', () {
      final names = potentiallyCapturedAstNames(<AstNode>[
        LocalDeclaration(
          <Identifier>[Identifier('hot')],
          <String>[''],
          <AstNode>[NumberLiteral(0)],
        ),
        LocalFunctionDef(
          Identifier('reader'),
          FunctionBody(const <Identifier>[], <AstNode>[
            LocalDeclaration(
              <Identifier>[Identifier('own')],
              <String>[''],
              <AstNode>[NumberLiteral(1)],
            ),
            ReturnStatement(<AstNode>[
              BinaryExpression(Identifier('captured'), '+', Identifier('own')),
            ]),
          ], false),
        ),
      ]);

      expect(names, containsAll(<String>['reader', 'captured', 'own']));
      expect(names, isNot(contains('hot')));
    });

    test('direct uncaptured locals coexist with a returned closure', () async {
      AstLocalFrame.resetDiagnostics();
      final lua = LuaLike();

      final result = await lua.execute('''
        local function make_reader(value, count)
          local captured = value
          local total = 0
          local function read() return captured end
          for i = 1, count do
            local increment = i
            total = total + increment
          end
          return total, read
        end

        local total, read = make_reader(9, 4)
        return total, read()
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[10, 9]),
      );
      if (AstLocalFrame.diagnosticsEnabled) {
        final diagnostics = AstLocalFrame.diagnostics();
        expect(diagnostics['slotOnlyParameterBinds'], greaterThanOrEqualTo(2));
        expect(diagnostics['slotOnlyLocalBinds'], greaterThanOrEqualTo(5));
      }
    });

    test('keeps captured parameters boxed beside direct parameters', () async {
      AstLocalFrame.resetDiagnostics();
      final lua = LuaLike();

      final result = await lua.execute('''
        local function make_reader(value, count)
          local total = 0
          local function read() return value end
          for i = 1, count do
            total = total + i
          end
          value = value + 1
          return total, read
        end

        local total, read = make_reader(9, 3)
        return total, read()
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[6, 10]),
      );
      if (AstLocalFrame.diagnosticsEnabled) {
        expect(
          AstLocalFrame.diagnostics()['slotOnlyParameterBinds'],
          greaterThanOrEqualTo(1),
        );
      }
    });

    test(
      'stores uncaptured identity locals without changing identity',
      () async {
        final lua = LuaLike();

        final result = await lua.execute('''
        local function exercise(target)
          local alias = target
          local label = "relay"
          local operation = math.abs
          alias.value = operation(-41) + #label
          return alias == target, alias.value, label
        end

        local target = {value = 0}
        return exercise(target)
      ''');

        expect(
          (result.raw as List<Object?>)
              .map((value) => (value as Value).unwrap())
              .toList(),
          equals(<Object?>[true, 46, 'relay']),
        );
        if (AstLocalFrame.diagnosticsEnabled) {
          expect(
            AstLocalFrame.diagnostics()['slotOnlyIdentityLocalBinds'],
            greaterThanOrEqualTo(3),
          );
        }
      },
    );

    test('roots a direct table local across collection', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local observed = setmetatable({}, {__mode = "v"})
        local function retain()
          local target = {value = 42}
          observed[1] = target
          collectgarbage("collect")
          return observed[1] == target and target.value
        end

        return retain()
      ''');

      expect(result.unwrap(), equals(42));
    });

    test('preserves a direct table local across coroutine yield', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local thread = coroutine.create(function()
          local state = {value = 20}
          coroutine.yield(state.value)
          state.value = state.value + 22
          return state.value
        end)

        local first_ok, first = coroutine.resume(thread)
        local second_ok, second = coroutine.resume(thread)
        return first_ok, first, second_ok, second
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[true, 20, true, 42]),
      );
    });

    test('reinitializes parameters and direct locals on every call', () async {
      final lua = LuaLike();

      await lua.execute('''
        local function adjusted(value, low, high)
          local result = value + 1
          if result < low then return low end
          if result > high then return high end
          return result
        end

        first = adjusted(1, 5, 95)
        second = adjusted(50, 5, 95)
        third = adjusted(100, 5, 95)
      ''');

      expect(lua.getGlobal('first')?.unwrap(), equals(5));
      expect(lua.getGlobal('second')?.unwrap(), equals(51));
      expect(lua.getGlobal('third')?.unwrap(), equals(95));
    });

    test('keeps closure-free parameter slots live across writes', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local function mutate(value)
          value = value + 1
          value = value * 2
          return value
        end

        return mutate(10), mutate(-2)
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[22, -2]),
      );
    });

    test('keeps primitive top-level leaf locals live across writes', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local function calculate(value)
          local doubled = value * 2
          local adjusted = doubled + 3
          adjusted = adjusted * 4
          return doubled, adjusted
        end

        return calculate(5)
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[10, 52]),
      );
    });

    test('preserves top-level local shadowing in a leaf function', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local function shadow()
          local value = 10
          local before = value
          local value = 20
          return before, value
        end

        return shadow()
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[10, 20]),
      );
    });

    test('keeps nested local shadowing in lexical slots', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local function shadow()
          local value = 10
          local inside = 0
          do
            local value = 20
            inside = value
          end
          return inside, value
        end

        return shadow()
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[20, 10]),
      );
    });

    test('expires branch-local slots when the branch scope exits', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local function choose(use_inner)
          local value = 10
          local observed = 0
          if use_inner then
            local value = 20
            observed = value
          else
            local value = 30
            observed = value
          end
          return observed, value
        end

        return choose(true), choose(false)
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        // Only the final call in a Lua return list expands to all results.
        equals(<Object?>[20, 30, 10]),
      );
    });

    test(
      'rebinds loop-body slots without leaking them after the loop',
      () async {
        final lua = LuaLike();

        final result = await lua.execute('''
        local function accumulate(limit)
          local total = 0
          local value = 100
          for i = 1, limit do
            local value = i * 3
            total = total + value
          end
          return total, value
        end

        return accumulate(4)
      ''');

        expect(
          (result.raw as List<Object?>)
              .map((value) => (value as Value).unwrap())
              .toList(),
          equals(<Object?>[30, 100]),
        );
      },
    );

    test('keeps repeat locals visible to the until condition only', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local function advance(limit)
          local value = 40
          local count = 0
          repeat
            local value = count + 1
            count = value
          until value >= limit
          return count, value
        end

        return advance(4)
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[4, 40]),
      );
    });

    test('keeps local _ENV as a dynamic environment binding', () async {
      final lua = LuaLike();

      final result = await lua.execute('''
        local function read_from(target)
          local _ENV = target
          return answer
        end

        return read_from({answer = 42})
      ''');

      expect(result.unwrap(), equals(42));
    });

    test('reports slot-only leaf locals as locals in errors', () async {
      final lua = LuaLike();

      await expectLater(
        lua.execute('''
          local function fail()
            local target = nil
            return target.value
          end

          return fail()
        '''),
        throwsA(
          isA<LuaError>().having(
            (error) => error.toString(),
            'message',
            contains("local 'target'"),
          ),
        ),
      );
    });

    test('debug APIs read and mutate live parameter slots', () async {
      final lua = LuaLike();

      final result = await lua.execute(r'''
        local function inspect(value)
          value = value + 1
          local name, before = debug.getlocal(1, 1)
          local changed = debug.setlocal(1, 1, 41)
          return name, before, changed, value
        end

        return inspect(10)
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>['value', 11, 'value', 41]),
      );
    });

    test(
      'restores direct caller slots after nested Lua and builtin calls',
      () async {
        final lua = LuaLike();

        final result = await lua.execute('''
        local function inner(value)
          local shifted = math.abs(value - 3)
          return shifted * 2
        end

        local function outer(value)
          local before = value + 1
          local nested = inner(before)
          local after = before + math.floor(nested / 2)
          return before, nested, after
        end

        return outer(9)
      ''');

        expect(
          (result.raw as List<Object?>)
              .map((value) => (value as Value).unwrap())
              .toList(),
          equals(<Object?>[10, 14, 17]),
        );
      },
    );

    test(
      'debug APIs can mutate a direct local in the Lua caller frame',
      () async {
        final lua = LuaLike();

        final result = await lua.execute(r'''
        local function mutate_caller()
          local changed = debug.setlocal(2, 2, 41)
          return changed
        end

        local function caller(value)
          local direct = value + 1
          local changed = mutate_caller()
          return changed, direct
        end

        return caller(10)
      ''');

        expect(
          (result.raw as List<Object?>)
              .map((value) => (value as Value).unwrap())
              .toList(),
          equals(<Object?>['direct', 41]),
        );
      },
    );

    test('preserves direct locals across coroutine yield and resume', () async {
      final lua = LuaLike();

      final result = await lua.execute(r'''
        local function worker(value)
          local direct = value + 1
          local resumed = coroutine.yield(direct)
          direct = direct + resumed
          return direct
        end

        local co = coroutine.create(worker)
        local first_ok, yielded = coroutine.resume(co, 10)
        local second_ok, completed = coroutine.resume(co, 7)
        return first_ok, yielded, second_ok, completed
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[true, 11, true, 18]),
      );
    });

    test(
      'restores direct caller slots after protected coroutine overflow',
      () async {
        final lua = LuaLike();

        final result = await lua.execute(r'''
        local function checkerror(message, target)
          local success, failure = pcall(target)
          return not success and string.find(failure, message) ~= nil
        end

        local count = 0
        local function overflow()
          count = count + 1
          pcall(1)
          coroutine.wrap(overflow)()
        end

        return checkerror("C stack overflow", overflow), count > 0
      ''');

        expect(
          (result.raw as List<Object?>)
              .map((value) => (value as Value).unwrap())
              .toList(),
          equals(<Object?>[true, true]),
        );
      },
    );

    test('_ENV parameters remain dynamic environment bindings', () async {
      final lua = LuaLike();

      final result = await lua.execute(r'''
        local function initialize(_ENV)
          global a, b, c = 10, 20, 30
        end

        local target = {}
        initialize(target)
        return target.a, target.b, target.c
      ''');

      expect(
        (result.raw as List<Object?>)
            .map((value) => (value as Value).unwrap())
            .toList(),
        equals(<Object?>[10, 20, 30]),
      );
    });

    test('reuses closure-free frames with captured state and calls', () async {
      final lua = LuaLike();

      await lua.execute('''
        local offset = -3
        local calls = 0
        local function adjusted(value)
          local magnitude = math.abs(value + offset)
          calls = calls + 1
          return magnitude
        end

        first = adjusted(1)
        second = adjusted(10)
        third = adjusted(-4)
        call_count = calls
      ''');

      expect(lua.getGlobal('first')?.unwrap(), equals(2));
      expect(lua.getGlobal('second')?.unwrap(), equals(7));
      expect(lua.getGlobal('third')?.unwrap(), equals(7));
      expect(lua.getGlobal('call_count')?.unwrap(), equals(3));
    });

    test('does not share an active pooled frame with recursion', () async {
      final lua = LuaLike();

      await lua.execute('''
        local bias = 2
        local function sum_to(value)
          local current = value + bias
          if value == 0 then return current end
          local nested = sum_to(value - 1)
          return current + nested
        end

        recursive_total = sum_to(3)
        recursive_total_again = sum_to(1)
      ''');

      expect(lua.getGlobal('recursive_total')?.unwrap(), equals(14));
      expect(lua.getGlobal('recursive_total_again')?.unwrap(), equals(5));
    });

    test('reinitializes a pooled frame after an error', () async {
      final lua = LuaLike();

      await lua.execute('''
        local calls = 0
        local function guarded(value)
          local result = value + calls
          calls = calls + 1
          if value < 0 then error("expected") end
          return result
        end

        before_error = guarded(10)
        error_caught = not pcall(guarded, -1)
        after_error = guarded(10)
      ''');

      expect(lua.getGlobal('before_error')?.unwrap(), equals(10));
      expect(lua.getGlobal('error_caught')?.unwrap(), isTrue);
      expect(lua.getGlobal('after_error')?.unwrap(), equals(12));
    });

    test('never recycles boxes retained by returned closures', () async {
      final lua = LuaLike();

      await lua.execute('''
        local function make_reader(value)
          local captured = value
          return function() return captured end
        end

        local first_reader = make_reader(10)
        local second_reader = make_reader(20)
        first_value = first_reader()
        second_value = second_reader()
        first_value_again = first_reader()
      ''');

      expect(lua.getGlobal('first_value')?.unwrap(), equals(10));
      expect(lua.getGlobal('second_value')?.unwrap(), equals(20));
      expect(lua.getGlobal('first_value_again')?.unwrap(), equals(10));
    });

    test(
      'does not park captures restored from dumped nested functions',
      () async {
        final lua = LuaLike();

        await lua.execute(r'''
        local source = [[
          return function(x)
            return function(y)
              return x + y
            end
          end
        ]]

        local original_chunk = assert(load(source))
        local loaded_chunk = assert(load(string.dump(original_chunk)))
        local make_adder = loaded_chunk()
        local add_two = make_adder(2)
        dumped_nested_result = add_two(3)
      ''');

        expect(lua.getGlobal('dumped_nested_result')?.unwrap(), equals(5));
      },
    );
  });
}
