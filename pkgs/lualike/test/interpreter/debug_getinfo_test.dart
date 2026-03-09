import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('Debug library tests', () {
    late LuaLike luaLike;

    setUp(() {
      luaLike = LuaLike();
    });

    test('debug library should be available', () async {
      const script = '''
      return type(debug)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 'table');
    });

    test('debug.getinfo function should exist', () async {
      const script = '''
      return type(debug.getinfo)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 'function');
    });

    test('debug.getinfo should accept a level parameter', () async {
      const script = '''
      local status, result = pcall(function() 
        return debug.getinfo(1) 
      end)
      return status
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isTrue);
    });

    test('debug.getinfo should return a table', () async {
      const script = '''
      local status, result = pcall(function()
        local info = debug.getinfo(1)
        return type(info)
      end)
      
      return {status = status, result = result}
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<Map>());

      final resultMap = result.raw as Map;
      expect(resultMap['status'], isTrue);
      expect(resultMap['result'].raw, 'table');
    });

    test('debug.getinfo should include path in source field', () async {
      const scriptPath = 'custom_test_script.lua';
      const script = '''
      local function check_source()
        local info = debug.getinfo(1)
        return info.source
      end
      return check_source()
      ''';

      final result = (await luaLike.execute(script, scriptPath: scriptPath));
      // We expect the source to include the @ symbol followed by the script path
      expect(result.raw is String, isTrue);
      expect((result.raw as String).contains('@'), isTrue);
    });

    test('debug.getinfo should reject invalid option strings', () async {
      const script = '''
      local ok1 = pcall(debug.getinfo, print, "X")
      local ok2 = pcall(debug.getinfo, 0, ">")
      return ok1, ok2
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[false, false]),
      );
    });

    test('debug.getinfo should return nil for invalid stack levels', () async {
      const script = '''
      return debug.getinfo(1000), debug.getinfo(-1)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[null, null]),
      );
    });

    test('debug.getinfo should report builtin functions as C', () async {
      const script = '''
      local info = debug.getinfo(print)
      return info.what, info.short_src
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>['C', '[C]']),
      );
    });

    test('debug.getinfo should expose main chunk function metadata', () async {
      const script = r'''
      local info = debug.getinfo(1, 'fu')
      local upname = debug.getupvalue(info.func, 1)
      return info.isvararg, info.nparams, info.nups, upname
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[true, 0, 1, '_ENV']),
      );
    });

    test('debug.getinfo should format load chunk names like Lua', () async {
      const script = r'''
      local a = "function f () end"
      local function dostring (s, x) return load(s, x)() end
      dostring(a)
      local infoA = debug.getinfo(f)
      dostring(a, "")
      local infoEmpty = debug.getinfo(f)
      dostring(a, '[string "xuxu"]')
      local infoCustom = debug.getinfo(f)
      return infoA.short_src, infoEmpty.short_src, infoCustom.short_src
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[
          '[string "function f () end"]',
          '[string ""]',
          '[string "[string "xuxu"]"]',
        ]),
      );
    });

    test('debug.getinfo should classify active field calls', () async {
      const script = r'''
      local g = {x = function ()
        local info = debug.getinfo(1)
        return info.name, info.namewhat
      end}
      local function f() return g.x() end
      return f()
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>['x', 'field']),
      );
    });

    test('debug.getinfo should prefer caller local alias names', () async {
      const script = r'''
      local function f(x, expected)
        local info = debug.getinfo(1)
        return info.name, info.namewhat, x
      end
      local function g(x)
        return x('a', 'x')
      end
      return g(f)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      final values = (result.raw as List).cast<Value>();
      expect(values[0].raw, 'x');
      expect(values[1].raw, 'local');
      final third = values[2].raw;
      final thirdString = switch (third) {
        final Value nested => nested.raw.toString(),
        _ => third.toString(),
      };
      expect(thirdString, 'a');
    });

    test('debug.getinfo should report extraargs through __call chains', () async {
      const script = r'''
      local function u (...)
        return debug.getinfo(1, 't').extraargs, select('#', ...)
      end

      local a, b = u()
      u = setmetatable({}, {__call = u})
      local c, d = u()
      u = setmetatable({}, {__call = u})
      local e, f = u()
      return a, b, c, d, e, f
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[0, 0, 1, 1, 2, 2]),
      );
    });

    test('debug.getinfo should report sparse activelines like Lua', () async {
      const script = r'''
      local function checkactivelines (f, lines)
        local t = debug.getinfo(f, "SL")
        for _, l in pairs(lines) do
          l = l + t.linedefined
          assert(t.activelines[l])
          t.activelines[l] = nil
        end
        return next(t.activelines) == nil
      end

      return
        checkactivelines(function (...)
          -- 1st line is empty
          -- 2nd line is empty
          -- 3th line is empty
          local a = 20
          -- 5th line is empty
          local b = 30
          -- 7th line is empty
        end, {4, 6, 8}),
        checkactivelines(function (a, b, ...) end, {0}),
        checkactivelines(function (a, b)
        end, {1})
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[true, true, true]),
      );
    });

    test('debug.getinfo should return empty activelines for stripped chunks', () async {
      const script = r'''
      local func = load(string.dump(load("print(10)"), true))
      local actl = debug.getinfo(func, "L").activelines
      return next(actl) == nil
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isTrue);
    });

    test('stripped chunks should hide local names and source details', () async {
      const script = r'''
      local prog = [[
        local a = 12
        local function foo()
          return a
        end
        local lname, lvalue = debug.getlocal(1, 1)
        local uname, uvalue = debug.getupvalue(foo, 1)
        local sname = debug.setupvalue(foo, 1, 13)
        local info = debug.getinfo(foo, "SluL")
        return lname, lvalue, uname, uvalue, sname,
               info.short_src, info.linedefined > 0,
               info.lastlinedefined == info.linedefined,
               info.currentline, next(info.activelines) == nil
      ]]
      local f = assert(load(string.dump(load(prog), true)))
      return f()
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[
          '(temporary)',
          12,
          '(no name)',
          12,
          '(no name)',
          '?',
          true,
          true,
          -1,
          true,
        ]),
      );
    });

    test('re-dumping a function from a stripped chunk should keep stripped debug info', () async {
      const script = r'''
      local prog = [[
        local a = 12
        local f = function (x, y) return x + y + a end
        f = load(string.dump(f))
        local t = debug.getinfo(f)
        return t.name, t.linedefined > 0, t.lastlinedefined == t.linedefined, t.short_src
      ]]
      local f = assert(load(string.dump(load(prog), true)))
      return f()
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[null, true, true, '?']),
      );
    });

    test('stripped functions should fire line hooks without a line payload', () async {
      const script = r'''
      local prog = [[
        local function foo()
          local b = 2
          return b
        end
        local s = load(string.dump(foo, true))
        local line = true
        debug.sethook(function (e, l)
          line = l
        end, "l")
        local result = s()
        debug.sethook(nil)
        return result, line
      ]]
      local f = assert(load(string.dump(load(prog), true)))
      return f()
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[2, null]),
      );
    });

    test('debug.getregistry should expose a stable weak-key hook table', () async {
      const script = r'''
      local r1 = debug.getregistry()
      local r2 = debug.getregistry()
      local mt = getmetatable(r1._HOOKKEY)
      return type(r1), r1 == r2, type(r1._HOOKKEY), mt and mt.__mode
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>['table', true, 'table', 'k']),
      );
    });

    test('debug.getinfo currentline should not jump ahead of the active statement', () async {
      const script = r'''
      local L = nil
      local glob = 1
      local oldglob = glob

      debug.sethook(function (e, l)
        if e == "line" and glob ~= oldglob then
          L = l - 1
          oldglob = glob
        end
      end, "l")

      local function foo()
        glob = glob + 1
        return debug.getinfo(1, "l").currentline, L
      end

      local current, marker = foo()
      debug.sethook()
      return current, marker
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[14, 13]),
      );
    });

    test('debug.setlocal should account for the implicit vararg table slot', () async {
      const script = r'''
      local debug = require "debug"
      local function f(a, b)
        return debug.setlocal(2, 4, "pera"), debug.setlocal(2, 5, "manga")
      end
      local function g(...)
        local arg = {...}
        local feijao
        local AAAA, B = "xuxu", "abacate"
        local n1, n2 = f(AAAA, B)
        return n1, n2, AAAA, B
      end
      return g()
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      Object? normalize(Object? value) => switch (value) {
        final LuaString luaString => luaString.toString(),
        _ => value,
      };
      expect(
        (result.raw as List)
            .map((value) => normalize((value as Value).raw))
            .toList(),
        equals(<Object?>['AAAA', 'B', 'pera', 'manga']),
      );
    });

    test('debug.getlocal should see locals from the current block scope', () async {
      const script = r'''
      local debug = require "debug"
      local function g(...)
        local arg = {...}
        local feijao
        local AAAA, B = "xuxu", "abacate"
        do
          local B = 13
          local x, y = debug.getlocal(1, 6)
          return x, y
        end
      end
      return g()
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      Object? normalize(Object? value) => switch (value) {
        final LuaString luaString => luaString.toString(),
        _ => value,
      };
      expect(
        (result.raw as List)
            .map((value) => normalize((value as Value).raw))
            .toList(),
        equals(<Object?>['B', 13]),
      );
    });

    test('debug.setlocal should mutate caller Lua temporaries', () async {
      const script = r'''
      local debug = require "debug"

      local function f()
        local name, value = debug.getlocal(2, 3)
        assert(value == 1)
        assert(not debug.getlocal(2, 4))
        debug.setlocal(2, 3, 10)
        return 20
      end

      local function g(a, b)
        return (a + 1) + f()
      end

      return g(0, 0)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 30);
    });

    test('debug.setuservalue should reject file handles like Lua', () async {
      const script = r'''
      local a = debug.setuservalue(io.stdin, 10)
      local b, c = debug.getuservalue(io.stdin, 10)
      return a, b, c
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[null, null, null]),
      );
    });

    test('debug.getinfo should report current line inside nested line hooks', () async {
      const script = r'''
      local observed

      debug.sethook(function ()
        assert(not pcall(load("a='joao'+1")))
        debug.sethook(function (event, line)
          observed = debug.getinfo(2, "l").currentline == line
          debug.sethook(nil)
        end, "l")
      end, "c")

      local a = {}
      function a:f() local c = 13 end
      a:f()
      debug.sethook(nil)
      return observed
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isTrue);
    });

    test('debug.getlocal should preserve hooked frame locals after hook calls load', () async {
      const script = r'''
      local function dostring(s)
        local f, err = load(s)
        if not f then error(err) end
        return f()
      end

      local function collectlocals(level)
        local tab = {}
        for i = 1, math.huge do
          local n, v = debug.getlocal(level + 1, i)
          if not (n and string.find(n, "^[a-zA-Z0-9_]+$") or
                  n == "(vararg table)") then
             break
          end
          tab[n] = v
        end
        return tab
      end

      local X = nil
      local a = {}
      function a:f(a, b, ...) local arg = {...}; local c = 13 end

      debug.sethook(function(e)
        assert(e == "call")
        dostring("XX = 12")
        assert(not pcall(load("a='joao'+1")))
        debug.sethook(function(event, line)
          assert(debug.getinfo(2, "l").currentline == line)
          debug.sethook(nil)
          X = collectlocals(2)
        end, "l")
      end, "c")

      a:f(1, 2, 3, 4, 5)
      debug.sethook(nil)
      return X.self == a, X.a, X.b, X.c, XX
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[true, 1, 2, null, 12]),
      );
    });

    test('hooked method calls should restore the main frame after returning', () async {
      const script = r'''
      local function dostring(s)
        local f, err = load(s)
        if not f then error(err) end
        return f()
      end

      local function collectlocals(level)
        local tab = {}
        for i = 1, math.huge do
          local n, v = debug.getlocal(level + 1, i)
          if not (n and string.find(n, "^[a-zA-Z0-9_]+$") or
                  n == "(vararg table)") then
             break
          end
          tab[n] = v
        end
        return tab
      end

      local X = nil
      local a = {}
      function a:f(a, b, ...) local arg = {...}; local c = 13 end

      debug.sethook(function(e)
        assert(e == "call")
        dostring("XX = 12")
        assert(not pcall(load("a='joao'+1")))
        debug.sethook(function(event, line)
          assert(debug.getinfo(2, "l").currentline == line)
          debug.sethook(nil)
          X = collectlocals(2)
        end, "l")
      end, "c")

      a:f(1, 2, 3, 4, 5)
      debug.sethook(nil)
      return debug.getinfo(1, "S").what
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 'main');
    });

    test('debug.getlocal should expose completed local function definitions in loaded chunks', () async {
      const script = r'''
      local co = load[[
        local A = function ()
          return x
        end
        return
      ]]

      local seen3, seen4
      debug.sethook(function (event, line)
        if line == 3 then
          seen3 = debug.getlocal(2, 1)
        elseif line == 4 then
          seen4 = debug.getlocal(2, 1)
        end
      end, "l")
      co()
      debug.sethook(nil)
      return seen3, seen4
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>['(temporary)', 'A']),
      );
    });

    test('debug.getinfo should support coroutine thread levels', () async {
      const script = r'''
      local co = coroutine.create(function (x)
        local a = 1
        coroutine.yield(debug.getinfo(1, "l"))
        coroutine.yield(debug.getinfo(1, "l").currentline)
        return a
      end)

      local _, l = coroutine.resume(co, 10)
      local x = debug.getinfo(co, 1, "lfLS")
      return x.currentline, l.currentline, x.activelines[x.currentline], type(x.func)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      final values = (result.raw as List).map((value) => (value as Value).raw).toList();
      expect(values[0], equals(values[1]));
      expect(values[2], equals(true));
      expect(values[3], equals('function'));
    });

    test('debug.getlocal and setlocal should resolve coroutine lexical frames', () async {
      const script = r'''
      local co = coroutine.create(function (x)
        local a = 1
        coroutine.yield(debug.getinfo(1, "l"))
        coroutine.yield(debug.getinfo(1, "l").currentline)
        return a
      end)

      coroutine.resume(co, 10)
      local n1, v1 = debug.getlocal(co, 1, 1)
      local n2, v2 = debug.getlocal(co, 1, 2)
      debug.setlocal(co, 1, 2, "hi")
      coroutine.resume(co)
      local _, resumed = coroutine.resume(co)
      return n1, v1, n2, v2, resumed
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      Object? normalize(Object? value) => switch (value) {
        final LuaString luaString => luaString.toString(),
        _ => value,
      };
      expect(
        (result.raw as List)
            .map((value) => normalize((value as Value).raw))
            .toList(),
        equals(<Object?>['x', 10, 'a', 1, 'hi']),
      );
    });
  });
}
