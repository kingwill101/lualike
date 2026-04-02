@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike_test/test.dart';

void main() {
  group('LualikeIrRuntime.callFunction', () {
    test('invokes global function by name', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final runtime = bridge.vm;

      await bridge.execute('''
        function add(a, b)
          return a + b
        end
      ''');

      final argA = Value(2)..interpreter = runtime;
      final argB = Value(3)..interpreter = runtime;
      final result = await runtime.callFunction('add'.value, [argA, argB]);
      final numeric = result is Value ? result.raw : result;
      expect(numeric, equals(5));
    });

    test('invokes returned lowered bytecode closure', () async {
      final bridge = LuaLike(runtime: LualikeIrRuntime());
      final runtime = bridge.vm;

      await bridge.execute('''
        function make_const()
          return function()
            return 42
          end
        end

        closure = make_const()
      ''');

      final closure = bridge.getGlobal('closure');
      final closureValue = closure is Value ? closure : Value(closure);
      closureValue.interpreter ??= runtime;
      expect(closureValue.raw, isA<LuaBytecodeClosure>());

      final result = await runtime.callFunction(closureValue, const []);
      final numeric = result is Value ? result.raw : result;
      expect(numeric, equals(42));
    });
  });

  group('LualikeIrRuntime load & stdlib integration', () {
    late LuaLike bridge;
    Object? unwrap(Object? candidate) {
      if (candidate is Value) {
        final raw = candidate.unwrap();
        return raw is LuaString ? raw.toString() : raw;
      }
      if (candidate is LuaString) {
        return candidate.toString();
      }
      return candidate;
    }

    setUp(() {
      bridge = LuaLike(runtime: LualikeIrRuntime());
      LuaLikeConfig().dumpIr = false;
    });

    tearDown(() {
      LuaLikeConfig().dumpIr = false;
    });

    test('loaded chunk can access math library', () async {
      final result = await bridge.execute('''
        local chunk = assert(load("return math.sqrt(49)"))
        return chunk()
      ''');
      expect(unwrap(result), equals(7));
    });

    test('pcall surfaces math.huge shift error message', () async {
      final result = await bridge.execute(r'''
        local ok, err = pcall(function()
          return math.huge << 1
        end)
        return ok, err
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values, hasLength(2));

      final okValue = values[0];
      final errValue = values[1];

      expect(okValue, isFalse);
      expect(errValue, contains("field 'huge'"));
    });

    test('string colon methods resolve via lualike IR runtime', () async {
      final result = await bridge.execute(r"return ('value %d'):format(21)");
      expect(unwrap(result), equals('value 21'));
    });

    test('explicit global function shadows outer local at call site', () async {
      final result = await bridge.execute(r'''
        local foo = 20
        do
          global function foo (x)
            return x
          end
          return foo == _ENV.foo, foo(4), _ENV.foo(4), _ENV.foo == 20
        end
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values, equals(<Object?>[true, 4, 4, false]));
    });

    test('dumpIr prints without executing the chunk', () async {
      LuaLikeConfig().dumpIr = true;
      bridge.setGlobal('marker', 'before');

      final result = await bridge.execute(r'''
        _ENV.marker = 'after'
        return 99
      ''');

      expect(result, isNull);
      expect(unwrap(bridge.getGlobal('marker')), equals('before'));
    });

    test(
      'explicit global recursive function resolves simple name through global binding',
      () async {
        final result = await bridge.execute(r'''
          local foo = 20
          do
            global function foo (x)
              if x == 0 then
                return 1
              end
              return 2 * foo(x - 1)
            end
            return foo == _ENV.foo, foo(4), _ENV.foo(4)
          end
        ''');

        expect(result, isA<List>());
        final values = (result as List).map(unwrap).toList();
        expect(values, equals(<Object?>[true, 16, 16]));
      },
    );

    test(
      'explicit global recursive function works through explicit _ENV lookup',
      () async {
        final result = await bridge.execute(r'''
          local foo = 20
          do
            global function foo (x)
              if x == 0 then
                return 1
              end
              return 2 * _ENV.foo(x - 1)
            end
            return foo == _ENV.foo, foo(4), _ENV.foo(4)
          end
        ''');

        expect(result, isA<List>());
        final values = (result as List).map(unwrap).toList();
        expect(values, equals(<Object?>[true, 16, 16]));
      },
    );

    test(
      'explicit global recursive function terminates when recursive call uses literal base-case arg',
      () async {
        final result = await bridge.execute(r'''
          local foo = 20
          do
            global function foo (x)
              if x == 0 then
                return 1
              end
              return 2 * _ENV.foo(0)
            end
            return foo(4)
          end
        ''');

        expect(unwrap(result), equals(2));
      },
    );

    test(
      'explicit global function passes computed argument to global callee',
      () async {
        final result = await bridge.execute(r'''
          global function id(v)
            return v
          end

          local foo = 20
          do
            global function foo (x)
              return _ENV.id(x - 1)
            end
            return foo(4)
          end
        ''');

        expect(unwrap(result), equals(3));
      },
    );

    test('goto.lua global declaration block through local foo assertions', () async {
      final result = await bridge.execute(r'''
          local function checkerr (code, err)
          local st, msg = load(code)
          _ENV.assert(not st and string.find(msg, err))
        end

        do
          global T<const>

          checkerr("global none; X = 1", "variable 'X'")
          checkerr("global none; function XX() end", "variable 'XX'")
          checkerr("global X<close>", "cannot be")
          checkerr("global <close> *", "cannot be")

          do
            local X = 10
            do global X; X = 20 end
            _ENV.assert(X == 10)
          end
          _ENV.assert(_ENV.X == 20)

          checkerr("global _ENV, a; a = 10", "variable 'a'")
          checkerr([[
            global none
            local function foo () XXX = 1 end   --< ERROR]], "variable 'XXX'")

          if not T then
            _ENV.assert(load("global = 1; return global")() == 1)
          else
            _ENV.assert(not load("global = 1; return global"))
          end

          local foo = 20
          do
            global function foo (x)
              if x == 0 then return 1 else return 2 * foo(x - 1) end
            end
            _ENV.assert(foo == _ENV.foo and foo(4) == 16)
          end
          return _ENV.foo(4), foo
        end
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values, equals(<Object?>[16, 20]));
    });

    test('goto.lua global declaration block trailing const and wildcard cases', () async {
      final result = await bridge.execute(r'''
        local function checkerr (code, err)
          local st, msg = load(code)
          assert(not st and string.find(msg, err))
        end

        do
          global T<const>

          checkerr([[
            global<const> foo;
            function foo (x) return end
          ]], "assign to const variable 'foo'")

          checkerr([[
            global foo <const>;
            function foo (x)
              return
            end
          ]], "%:2%:")

          checkerr([[
            global<const> *;
            print(X)
            Y = 1
          ]], "assign to const variable 'Y'")

          checkerr([[
            global *;
            Y = X
            global<const> *;
            Y = 1
          ]], "assign to const variable 'Y'")

          global *
          Y = 10
          assert(_ENV.Y == 10)
          global<const> *
          local x = Y
          global *
          Y = x + Y
          return _ENV.Y
        end
      ''');

      expect(unwrap(result), equals(20));
    });

    test('global declaration checkerr helper sees load failure message', () async {
      final result = await bridge.execute(r'''
        global T<const>

        local function checkerr (code, err)
          local st, msg = _ENV.load(code)
          return st, msg, _ENV.string.find(msg, err)
        end

        return checkerr("global none; X = 1", "variable 'X'")
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values[0], isNull);
      expect(values[1], contains("variable 'X'"));
      expect(values[2], isNotNull);
    });

    test('global declaration checkerr sequence matches goto.lua opening cases', () async {
      final result = await bridge.execute(r'''
        global T<const>

        local function checkerr (code, err)
          local st, msg = _ENV.load(code)
          _ENV.assert(not st and _ENV.string.find(msg, err))
          return msg
        end

        local a = checkerr("global none; X = 1", "variable 'X'")
        local b = checkerr("global none; function XX() end", "variable 'XX'")
        local c = checkerr("global X<close>", "cannot be")
        local d = checkerr("global <close> *", "cannot be")
        return a, b, c, d
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values[0], contains("variable 'X'"));
      expect(values[1], contains("variable 'XX'"));
      expect(values[2], contains("cannot be"));
      expect(values[3], contains("cannot be"));
    });

    test('goto.lua global declaration initialization block around table.unpack', () async {
      final result = await bridge.execute(r'''
        do
          global<const> a, b, c = 10
          _ENV.assert(_ENV.a == 10 and b == nil and c == nil)
          _ENV.a = nil; _ENV.b = nil; _ENV.c = nil;

          global table
          global a, b, c, d = table.unpack{1, 2, 3, 6, 5}
          _ENV.assert(_ENV.a == 1 and b == 2 and c == 3 and d == 6)
          a = nil; b = nil; c = nil; d = nil

          local a, b = 100, 200
          do
            global a, b = a, b
          end
          _ENV.assert(_ENV.a == 100 and _ENV.b == 200)
          _ENV.a = nil; _ENV.b = nil

          return _ENV.a, _ENV.b, _ENV.c, _ENV.d
        end
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values, equals(<Object?>[null, null, null, null]));
    });

    test('large integer literal comparisons avoid inline compare overflow', () async {
      final result = await bridge.execute(r'''
        local x = 0xF0000000
        return x == 0xF0000000, x < 0xF0000001, x >= 0xF0000000
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values, equals(<Object?>[true, true, true]));
    });

    test('goto around to-be-closed variable clears global on scope exit', () async {
      final result = await bridge.execute(r'''
        do
          global *

          local function newobj (var)
            _ENV[var] = true
            return setmetatable({}, {__close = function ()
              _ENV[var] = nil
            end})
          end

          goto L1

          ::L4:: _ENV.assert(not varX); goto L5

          ::L1::
          local varX <close> = newobj("X")
          _ENV.assert(varX); goto L2

          ::L3::
          _ENV.assert(varX); goto L4

          ::L2:: _ENV.assert(varX); goto L3

          ::L5::
          return X
        end
      ''');

      expect(unwrap(result), isNull);
    });

    test('nested concatenation in error arguments compiles through IR runtime', () async {
      final result = await bridge.execute(r'''
        local type, error = type, error
        local strsub = string.sub

        local function trymt (x, y, mtname)
          error("attempt to '" .. strsub(mtname, 3) ..
                "' a " .. type(x) .. " with a " .. type(y), 4)
        end

        local ok, err = pcall(trymt, {}, "foo", "__band")
        return ok, err
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values[0], isFalse);
      expect(values[1], contains("attempt to 'band'"));
    });
  });
}
