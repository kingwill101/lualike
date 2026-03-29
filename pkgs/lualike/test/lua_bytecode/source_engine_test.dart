@Tags(['lua_bytecode'])
library;

import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:lualike/command/lualike_command_runner.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:test/test.dart';

void main() {
  final luacBinary = _resolveLuacBinary();
  final skipReason = luacBinary == null
      ? 'luac55 not available for lua_bytecode CLI chunk tests'
      : null;

  group('lua_bytecode source engine', () {
    late EngineMode originalMode;

    setUp(() {
      originalMode = LuaLikeConfig().defaultEngineMode;
    });

    tearDown(() {
      LuaLikeConfig().defaultEngineMode = originalMode;
    });

    test(
      'executeCode runs supported structured source via emitted chunks',
      () async {
        final result = await executeCode('''
local sum = 0
for i = 1, 4, 1 do
  if i == 3 then
    break
  end
  sum = sum + i
end
return sum
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(3));
      },
    );

    test(
      'executeCode runs supported labels and goto via emitted chunks',
      () async {
        final result = await executeCode('''
local i = 0
goto start
::loop::
i = i + 1
goto done
::start::
goto loop
::done::
return i
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(1));
      },
    );

    test(
      'executeCode allows goto to terminal labels at while-body boundaries',
      () async {
        final result = await executeCode('''
local x = 13
while true do
  goto exit
  goto done
  local y = 45
  ::done::
end
::exit::
return x
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(13));
      },
    );

    test(
      'executeCode closes <close> locals when goto leaves their scope',
      () async {
        final result = await executeCode(r'''
local closed = false
do
  local a <close> = setmetatable({}, {
    __close = function()
      closed = true
    end
  })
  goto done
end
::done::
return closed
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), isTrue);
      },
    );

    test(
      'executeCode preserves upvalue identities across goto-created closures',
      () async {
        final result = await executeCode(r'''
local debug = require 'debug'

local function foo ()
  local t = {}
  do
    local i = 1
    local a, b, c, d
    t[1] = function () return a, b, c, d end
    ::l1::
    local b
    do
      local c
      t[#t + 1] = function () return a, b, c, d end
      if i > 2 then goto l2 end
      do
        local d
        t[#t + 1] = function () return a, b, c, d end
        i = i + 1
        local a
        goto l1
      end
    end
  end
  ::l2:: return t
end

local a = foo()

return
  #a,
  debug.upvalueid(a[1], 1) == debug.upvalueid(a[2], 1),
  debug.upvalueid(a[1], 1) == debug.upvalueid(a[6], 1),
  debug.upvalueid(a[1], 2) ~= debug.upvalueid(a[2], 2),
  debug.upvalueid(a[3], 2) == debug.upvalueid(a[2], 2),
  debug.upvalueid(a[3], 2) ~= debug.upvalueid(a[4], 2)
''', mode: EngineMode.luaBytecode);

        expect(
          _flatten(result),
          equals(<Object?>[6, true, true, true, true, true]),
        );
      },
    );

    test('executeCode runs do blocks via emitted chunks', () async {
      final result = await executeCode('''
local x = 1
do
  local y = 4
  x = x + y
end
return x
''', mode: EngineMode.luaBytecode);

      expect(_unwrap(result), equals(5));
    });

    test(
      'executeCode preserves open-result calls used as outer call arguments',
      () async {
        final result = await executeCode('''
local function c12(...)
  return 55, 2
end

local call = function (f, args)
  return f(table.unpack(args, 1, args.n))
end

local a, b = assert(call(c12, {1, 2}))
return a, b
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[55, 2]));
      },
    );

    test(
      'executeCode runs const local declarations via emitted chunks',
      () async {
        final result = await executeCode('''
local prefix <const> = "byte"
local suffix <const> = "code"
return prefix .. suffix
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals('bytecode'));
      },
    );

    test(
      'executeCode keeps declaration-only globals bound in emitted chunks',
      () async {
        final result = await executeCode('''
global<const> print
return print ~= nil
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), isTrue);
      },
    );

    test(
      'executeCode supports named vararg tables in emitted chunks',
      () async {
        final result = await executeCode('''
local function pack(...t)
  return t.n, t[1], t[2], t[3]
end

return pack(10, nil, 30)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[3, 10, null, 30]));
      },
    );

    test(
      'executeCode preserves global declaration goto barriers in emitted chunks',
      () async {
        final result = await executeCode(r'''
local st1, msg1 = load([[ goto l1; global a; ::l1:: ]])
local st2, msg2 = load([[ goto l2; global *; ::l1:: ::l2:: print(3) ]])
return st1 == nil and string.find(msg1, "scope of 'a'", 1, true) ~= nil,
       st2 == nil and string.find(msg2, "scope of '*'", 1, true) ~= nil
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[true, true]));
      },
    );

    test(
      'executeCode validates load semantics for emitted source chunks',
      () async {
        final result = await executeCode(r'''
local st1, msg1 = load([[ global none; X = 1 ]])
local st2, msg2 = load([[
global foo <const>;
function foo (x)
  return
end
]])
local st3, msg3 = load([[ for v, k in pairs{} do v = 10 end ]])
return st1 == nil and string.find(msg1, "variable 'X'", 1, true) ~= nil,
       st2 == nil and string.find(msg2, ":2:", 1, true) ~= nil,
       st3 == nil and string.find(msg3, "assign to const variable 'v'", 1, true) ~= nil
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[true, true, true]));
      },
    );

    test('executeCode disables tail calls inside close-local scopes', () async {
      final result = await executeCode(r'''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local X, Y

local function foo ()
  local _ <close> = func2close(function () Y = 10 end)
  return X == true and Y == nil, 1, 2, 3
end

local function bar ()
  local _ <close> = func2close(function () X = false end)
  X = true
  return foo()
end

local ok, a, b, c = bar()
return ok, a, b, c, X, Y
''', mode: EngineMode.luaBytecode);

      expect(_flatten(result), equals(<Object?>[true, 1, 2, 3, false, 10]));
    });

    test(
      'executeCode disables tail calls inside generic for close scopes',
      () async {
        final result = await executeCode(r'''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local closed = false

local function foo ()
  return function () return true end, 0, 0,
         func2close(function () closed = true end)
end

local function tail() return closed end

local function foo1 ()
  for k in foo() do
    return tail()
  end
end

return foo1(), closed
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[false, true]));
      },
    );

    test(
      'executeCode threads close errors through later bytecode close handlers',
      () async {
        final result = await executeCode(r'''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local function foo ()
  local x <close> =
    func2close(function (self, msg)
      assert(string.find(msg, "@y"))
      error("@x")
    end)

  local y <close> =
    func2close(function (self, msg)
      assert(string.find(msg, "@z"))
      error("@y")
    end)

  local z <close> =
    func2close(function (self, msg)
      assert(msg == nil)
      error("@z")
    end)

  return 200
end

local ok, msg = pcall(foo)
return ok, string.find(msg, "@x", 1, true) ~= nil
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[false, true]));
      },
    );

    test(
      'executeCode hides failing bytecode frames before error close handlers',
      () async {
        final result = await executeCode(r'''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local function foo ()
  local x1 <close> =
    func2close(function (self, msg)
      assert(debug.getinfo(2).name == "pcall")
      assert(string.find(msg, "@y"))
      error("@x1")
    end)

  local y <close> =
    func2close(function (self, msg)
      assert(debug.getinfo(2).name == "pcall")
      assert(string.find(msg, "@z"))
      error("@y")
    end)

  local first = true
  local z <close> =
    func2close(function (self, msg)
      assert(debug.getinfo(2).name == "pcall")
      assert(first and msg == 4)
      first = false
      error("@z")
    end)

  error(4)
end

local ok, msg = pcall(foo)
return ok, string.find(msg, "@x1", 1, true) ~= nil
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[false, true]));
      },
    );

    test(
      'executeCode preserves raw close errors for xpcall traceback handlers',
      () async {
        final result = await executeCode(r'''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local function foo ()
  do
    local x1 <close> =
      func2close(function (self, msg)
        assert(string.find(msg, "@X"))
        error("@Y")
      end)

    local x123 <close> =
      func2close(function (_, msg)
        assert(msg == nil)
        error("@X")
      end)
  end
  os.exit(false)
end

local st, msg = xpcall(foo, debug.traceback)
return st, string.match(msg, "^[^ ]* @Y") ~= nil
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[false, true]));
      },
    );

    test(
      'executeCode preserves nested dofile script paths in xpcall close tracebacks',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'lualike-bytecode-dofile-',
        );
        final nestedFile = File('${tempDir.path}/nested.lua');
        try {
          await nestedFile.writeAsString(r'''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local function foo (...)
  do
    local x1 <close> =
      func2close(function (self, msg)
        assert(string.find(msg, "@X"))
        error("@Y")
      end)

    local x123 <close> =
      func2close(function (_, msg)
        assert(msg == nil)
        error("@X")
      end)
  end
  os.exit(false)
end

local st, msg = xpcall(foo, debug.traceback)
return st, msg
''');

          final scriptPath = nestedFile.path.replaceAll(r'\', r'\\');
          final result = await executeCode(
            "return dofile('$scriptPath')",
            mode: EngineMode.luaBytecode,
          );

          final flattened = _flatten(result);
          expect(flattened[0], isFalse);

          final message = flattened[1] as String;
          final normalizedMessage = _normalizePathSeparators(message);

          // Tracebacks surface the nested chunk source name, not necessarily
          // its absolute host path. Assert on the stable cross-platform signal.
          expect(normalizedMessage, contains(nestedFile.uri.pathSegments.last));
          expect(normalizedMessage, contains('@Y'));
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test(
      'executeCode coerces numeric-for string bounds in emitted chunks',
      () async {
        final result = await executeCode(r'''
local count = 0
for i = "10", "1", "-2" do
  count = count + 1
end
return count
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(5));
      },
    );

    test(
      'executeCode skips integer loops whose coerced limits are out of range',
      () async {
        final result = await executeCode(r'''
local executed = 0
for i = math.mininteger, -10e100 do
  executed = executed + 1
end
for i = math.maxinteger, 10e100, -1 do
  executed = executed + 1
end
return executed
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(0));
      },
    );

    test(
      'executeCode preserves wrapped integer-for progressions in emitted chunks',
      () async {
        final result = await executeCode(r'''
local mini = math.mininteger
local maxi = math.maxinteger
local seen = {}
for i = mini, maxi, maxi do
  seen[#seen + 1] = i
end
return #seen, seen[1], seen[2], seen[3]
''', mode: EngineMode.luaBytecode);

        expect(
          _flatten(result),
          equals(<Object?>[3, -9223372036854775808, -1, 9223372036854775806]),
        );
      },
    );

    test(
      'executeCode resolves named globals before outer locals in emitted chunks',
      () async {
        final result = await executeCode(r'''
local X = 10
do
  global X
  X = 20
end
return X, _ENV.X
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[10, 20]));
      },
    );

    test(
      'executeCode resolves simple global functions before outer locals in emitted chunks',
      () async {
        final result = await executeCode(r'''
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
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[true, 16, 16]));
      },
    );

    test(
      'executeCode evaluates global declaration initializers before installing emitted globals',
      () async {
        final result = await executeCode(r'''
local a, b = 100, 200
do
  global a, b = a, b
end
return _ENV.a, _ENV.b, a, b
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[100, 200, 100, 200]));
      },
    );

    test(
      'executeCode rejects redefinition of initialized globals in emitted chunks',
      () async {
        final result = await executeCode(r'''
global pcall, assert, string, load
local f = assert(load("global print = 10"))
local st, msg = pcall(f)
return st == false,
       string.find(msg, "global 'print' already defined", 1, true) ~= nil
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[true, true]));
      },
    );

    test(
      'executeCode preserves escaped string literal bytes via emitted chunks',
      () async {
        final result = await executeCode(r'''
local replaced = string.gsub("a\nb", "\n", "|")
local folded = "a\z
  b"
return replaced, folded, string.byte("\t", 1), string.byte("\n", 1)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>['a|b', 'ab', 9, 10]));
      },
    );

    test(
      'executeCode preserves high-byte string literal escapes via emitted chunks',
      () async {
        final result = await executeCode(r'''
local s = "\0\255\0"
local a, b, c = string.byte(s, 1, 3)
return a, b, c, string.char(0, 255, 0) == s
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[0, 255, 0, true]));
      },
    );

    test(
      'executeCode preserves utf8 string literals through load and %q',
      () async {
        final result = await executeCode(r'''
local x = "\"�lo\"\n\\"
return assert(load(string.format('return %q', x)))() == x
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), isTrue);
      },
    );

    test(
      'executeCode reports currentline for loaded bytecode source chunks',
      () async {
        final result = await executeCode(r'''
local source = "return 'abc\z  
   efg', require'debug'.getinfo(1).currentline"
local f = assert(load(source, ''))
return f()
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>['abcefg', 1]));
      },
    );

    test('executeCode preserves local function names in debug info', () async {
      final result = await executeCode(r'''
local debug = require 'debug'

local function F(a)
  return debug.getinfo(1, "n").name, a
end

return F(1)
''', mode: EngineMode.luaBytecode);

      expect(_flatten(result), equals(<Object?>['F', 1]));
    });

    test(
      'executeCode reuses identical emitted string literal identities',
      () async {
        final result = await executeCode(r'''
local function getadd(s) return string.format("%p", s) end
local s1 <const> = "01234567890123456789012345678901234567890123456789"
local s2 <const> = "01234567890123456789012345678901234567890123456789"
local function foo() return "01234567890123456789012345678901234567890123456789" end
return getadd(s1) == getadd(s2), getadd(s1) == getadd(foo())
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[true, true]));
      },
    );

    test(
      'executeCode resolves string methods through bytecode SELF lookups',
      () async {
        final result = await executeCode(r'''
return ("abc"):sub(2), ("alo(.)alo"):find("(.)", 1, true)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>['bc', 4, 6]));
      },
    );

    test(
      'executeCode preserves trailing open results in table constructors',
      () async {
        final result = await executeCode(r'''
local function unlpack(t, i)
  i = i or 1
  return t[i], t[i + 1], t[i + 2], t[i + 3]
end

local t = { unlpack{1, 2, 3}, unlpack{3, 2, 1}, unlpack{"a", "b"} }
return t[1], t[2], t[3], t[4], t[5], t[6]
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[1, 3, 'a', 'b', null, null]));
      },
    );

    test(
      'executeCode preserves nested table constructor values under temp pressure',
      () async {
        final result = await executeCode(r'''
local binops = {
  {" and ", function(a, b) if not a then return a else return b end end},
  {" or ", function(a, b) if a then return a else return b end end},
}
return type(binops[1][1]), binops[1][1], type(binops[1][2]), binops[2][1]
''', mode: EngineMode.luaBytecode);

        expect(
          _flatten(result),
          equals(<Object?>['string', ' and ', 'function', ' or ']),
        );
      },
    );

    test(
      'executeCode collects weak values while a bytecode frame is active',
      () async {
        final result = await executeCode(r'''
local lim=3
local undef=nil
local a={}
setmetatable(a,{__mode="v"})
a[1]=string.rep("b",21)
collectgarbage()
a[1]=undef
for i=1,lim do a[i]={} end
for i=1,lim do a[i.."x"]={} end
for i=1,lim do local t={}; a[t]=t end
for i=1,lim do a[i+lim]=i.."x" end
collectgarbage()
local count = 0
for k, v in pairs(a) do
  count = count + 1
end
return count
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(6));
      },
    );

    test(
      'executeCode preserves primitive weak keys during active bytecode execution',
      () async {
        final result = await executeCode(r'''
local a = setmetatable({}, {__mode = "vk"})
local x, y, z = {}, {}, {}

a[1] = x
a[2] = y
a[3] = z
a[string.rep("$", 11)] = string.rep("$", 11)

return a[1] == x, a[2] == y, a[3] == z, a[string.rep("$", 11)] == string.rep("$", 11)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[true, true, true, true]));
      },
    );

    test('executeCode emits arithmetic metamethod follow-up opcodes', () async {
      final result = await executeCode(r'''
local smt = getmetatable("")
smt.__band = function(x, y) return 42 end
return "x" & "y"
''', mode: EngineMode.luaBytecode);

      expect(_unwrap(result), equals(42));
    });

    test(
      'executeCode widens fixed-result assignment for final calls',
      () async {
        final result = await executeCode(r'''
local function oneless(a, ...) return ... end

local function f(n, a, ...)
  local b
  if n == 0 then
    local b, c, d = ...
    return a, b, c, d, oneless(oneless(oneless(...)))
  end

  n, b, a = n - 1, ..., a
  return f(n, a, ...)
end

local a, b, c, d, e = f(4)
return a == nil, b == nil, c == nil, d == nil, e == nil
''', mode: EngineMode.luaBytecode);

        expect(
          _flatten(result),
          equals(<Object?>[true, true, true, true, true]),
        );
      },
    );

    test(
      'executeCode clears globals assigned from an empty fixed-result call',
      () async {
        final result = await executeCode(r'''
local function g(...) return ... end

a, b, c = assert(g(1, 2, 3))
a, b, c = g()

return a, b, c, rawget(_G, 'a'), rawget(_G, 'b'), rawget(_G, 'c')
''', mode: EngineMode.luaBytecode);

        expect(
          _flatten(result),
          equals(<Object?>[null, null, null, null, null, null]),
        );
      },
    );

    test(
      'executeCode rejects assignment to const locals in emitted chunks',
      () async {
        await expectLater(
          executeCode('''
local x <const> = 1
x = 2
return x
''', mode: EngineMode.luaBytecode),
          throwsA(
            predicate(
              (Object? error) => error.toString().contains(
                "attempt to assign to const variable 'x'",
              ),
            ),
          ),
        );
      },
    );

    test(
      'executeCode allows assignment to generic for loop variables',
      () async {
        final result = await executeCode('''
local sum = 0
for _, value in ipairs({1, 2, 3}) do
  value = value + 1
  sum = sum + value
end
return sum
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(9));
      },
    );

    test(
      'executeCode continues generic-for iteration after deleting current hash keys',
      () async {
        final result = await executeCode(r'''
local t = {a = 1, b = 2, c = 3, d = 4, e = 5}
local count = 0
for k, v in pairs(t) do
  count = count + 1
  assert(t[k] == v)
  t[k] = nil
  collectgarbage()
  assert(t[k] == nil)
end
return count
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(5));
      },
    );

    test(
      'executeCode treats explicit nil next cursors as start of iteration',
      () async {
        final result = await executeCode(r'''
local t = {x = 1, y = 2, z = 3}
local k, v = next(t, nil)
return k ~= nil and v ~= nil and t[k] == v
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), isTrue);
      },
    );

    test(
      'executeCode continues generic-for iteration after deleting current dense key',
      () async {
        final result = await executeCode(r'''
local t = {[1] = 'a', [2] = 'b', [3] = 'c', tail = 'z'}
local seen = {}
for k, v in pairs(t) do
  seen[#seen + 1] = k
  if k == 2 then
    t[k] = nil
    collectgarbage()
  end
end
return #seen, seen[3], seen[4]
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[4, 3, 'tail']));
      },
    );

    test(
      'executeCode continues generic-for iteration after deleting current table keys',
      () async {
        final result = await executeCode(r'''
local t = {[{1}] = 1, [{2}] = 2, [string.rep("x ", 4)] = 3,
           [100.3] = 4, [4] = 5}
local count = 0
for k, v in pairs(t) do
  count = count + 1
  assert(t[k] == v)
  t[k] = nil
  collectgarbage()
  assert(t[k] == nil)
end
return count
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(5));
      },
    );

    test('config-selected bridge uses LuaBytecodeRuntime', () async {
      LuaLikeConfig().defaultEngineMode = EngineMode.luaBytecode;
      final bridge = LuaLike();
      expect(bridge.vm, isA<LuaBytecodeRuntime>());

      final result = await bridge.execute('''
        local x = 1
        local function bump(y)
          x = x + y
          return x
        end
        return bump(2), bump(3)
      ''');

      expect(_flatten(result), equals(<Object?>[3, 6]));
    });

    test('executeCode runs table constructors and table stores', () async {
      final result = await executeCode('''
local key = "y"
local t = {1, 2, x = 3, [key] = 7}
t.x = t.x + t[1]
t[2] = t[2] + 4
t[key] = t[key] + 1
return t[1], t[2], t.x, t[key]
''', mode: EngineMode.luaBytecode);

      expect(_flatten(result), equals(<Object?>[1, 6, 4, 8]));
    });

    test(
      'executeCode runs setlist-backed constructors and trailing open results',
      () async {
        final result = await executeCode(
          _setlistBackedConstructorSource(),
          mode: EngineMode.luaBytecode,
        );

        expect(_flatten(result), equals(<Object?>[1, 63, 64, 80, 81, 82]));
      },
    );

    test(
      'executeCode runs dotted and method-style function definitions',
      () async {
        LuaLikeConfig().defaultEngineMode = EngineMode.luaBytecode;
        final bridge = LuaLike();

        final result = await bridge.execute('''
-- Keep this focused on source-engine lowering. Using a Dart-provided nested
-- map here would exercise interop table wrapping instead of emitted function
-- definition semantics.
t = { a = { b = { base = 4 } } }

function t.a.b.add(x)
  return x + 2
end

function t.a.b:scale(x)
  return self.base * x
end

return t.a.b.add(3), t.a.b:scale(5)
''');

        expect(_flatten(result), equals(<Object?>[5, 20]));
      },
    );

    test('executeCode runs coroutine yield and resume via bytecode', () async {
      final result = await executeCode('''
local co = coroutine.create(function(a)
  local resumed = coroutine.yield(a + 1)
  return a + resumed
end)

local ok1, yielded = coroutine.resume(co, 4)
local midStatus = coroutine.status(co)
local ok2, finalValue = coroutine.resume(co, 6)
local finalStatus = coroutine.status(co)

return ok1, yielded, midStatus, ok2, finalValue, finalStatus
''', mode: EngineMode.luaBytecode);

      expect(
        _flatten(result),
        equals(<Object?>[true, 5, 'suspended', true, 10, 'dead']),
      );
    });

    test(
      'executeCode preserves pcall results across close yields in bytecode',
      () async {
        final result = await executeCode(r'''
local function func2close(f)
  return setmetatable({}, {__close = f})
end

local co = coroutine.wrap(function ()
  local x <close> = func2close(function ()
    coroutine.yield("x")
  end)

  return pcall(function ()
    do
      local z <close> = func2close(function ()
        coroutine.yield("z")
      end)
    end

    local y <close> = func2close(function ()
      coroutine.yield("y")
    end)

    return 10, 20, 30
  end)
end)

return co(), co(), co(), co()
''', mode: EngineMode.luaBytecode);

        expect(
          _flatten(result),
          equals(<Object?>['z', 'y', 'x', true, 10, 20, 30]),
        );
      },
    );

    test(
      'executeCode allows dofile to yield via bytecode coroutines',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('lbc_dofile_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final chunkFile = File('${tempDir.path}/yield.lua');
        await chunkFile.writeAsString('''
local x, z = coroutine.yield(10)
local y = coroutine.yield(20)
return x + y * z
''');

        final result = await executeCode('''
local f = coroutine.wrap(dofile)
return f(${_luaStringLiteral(chunkFile.path.replaceAll('\\', '/'))}),
       f(100, 101),
       f(200)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[10, 20, 20300]));
      },
    );

    test(
      'executeCode allows dofile to yield via coroutine resume in bytecode',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'lbc_dofile_resume_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final chunkFile = File('${tempDir.path}/yield.lua');
        await chunkFile.writeAsString('''
local x, z = coroutine.yield(10)
local y = coroutine.yield(20)
return x + y * z
''');

        final result = await executeCode('''
local co = coroutine.create(dofile)
return coroutine.resume(co, ${_luaStringLiteral(chunkFile.path.replaceAll('\\', '/'))}),
       coroutine.resume(co, 100, 101),
       coroutine.resume(co, 200)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[true, true, true, 20300]));
      },
    );

    test(
      'executeCode resolves local recursive functions before declared globals',
      () async {
        final result = await executeCode('''
global <const> *
global fact = false

local function fact(n)
  if n == 0 then
    return 1
  end
  return n * fact(n - 1)
end

return fact(5)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[120]));
      },
    );

    test(
      'executeCode tracks extraargs across __call chains in bytecode',
      () async {
        final result = await executeCode('''
local N = 5

local function u(...)
  local n = debug.getinfo(1, 't').extraargs
  assert(select("#", ...) == n)
  return n
end

local results = {}
for i = 0, N do
  results[#results + 1] = u()
  u = setmetatable({}, {__call = u})
end

return table.unpack(results)
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[0, 1, 2, 3, 4, 5]));
      },
    );

    test(
      'executeCode passes loader arguments to required source chunks',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('lbc_require_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final moduleFile = File('${tempDir.path}/names.lua');
        await moduleFile.writeAsString('return {...}\n');

        final modulePath = moduleFile.path;
        final searchPath = '${tempDir.path.replaceAll('\\', '/')}/?.lua';

        final result = await executeCode('''
package.path = ${_luaStringLiteral(searchPath)}
local loaded = require("names")
return loaded[1], loaded[2]
''', mode: EngineMode.luaBytecode);

        final flattened = _flatten(result);
        expect(flattened[0], equals('names'));
        expect(
          _normalizePathSeparators(flattened[1] as String),
          equals(_normalizePathSeparators(modulePath)),
        );
      },
    );

    test('executeCode stores globals through a local _ENV table', () async {
      final result = await executeCode(r'''
local loader = function (...)
  local _ENV = {...}
  function xuxu(x)
    return x + 20
  end
  return _ENV
end

local pl = loader("pl", ":preload:")
return pl[1], pl[2], pl.xuxu(10)
''', mode: EngineMode.luaBytecode);

      expect(_flatten(result), equals(<Object?>['pl', ':preload:', 30]));
    });

    test(
      'executeCode snapshots right-hand values before mixed assignment stores',
      () async {
        final result = await executeCode(r'''
function f(a) return a end

local a, b, c
a = {10, 9, [f] = print}
a[1], f(a)[2], b, c = {alo = assert}, 10, a[1], a[f], 6, 10

return a[2], b, c == print, a[1].alo == assert
''', mode: EngineMode.luaBytecode);

        expect(_flatten(result), equals(<Object?>[10, 10, true, true]));
      },
    );

    test('load and string.dump use the emitted lua_bytecode path', () async {
      LuaLikeConfig().defaultEngineMode = EngineMode.luaBytecode;
      final bridge = LuaLike();

      await bridge.execute('''
        loaded = assert(load([[
          local sum = 0
          for i = 1, 4, 1 do
            sum = sum + i
          end
          return sum
        ]], "=(source)", "t"))
        source_result = loaded()

        function bump(x)
          if x > 1 then
            return x + 1
          end
          return x
        end

        dumped = string.dump(bump)
        dumped_magic = string.byte(dumped, 1)
        reloaded = assert(load(dumped, nil, "b"))
        dumped_result = reloaded(2)
      ''');

      expect((bridge.getGlobal('source_result') as Value?)?.raw, equals(10));
      expect((bridge.getGlobal('dumped_magic') as Value?)?.raw, equals(27));
      expect((bridge.getGlobal('dumped_result') as Value?)?.raw, equals(3));
    });

    test(
      'load leaves dumped non-_ENV upvalues unset in lua_bytecode',
      () async {
        LuaLikeConfig().defaultEngineMode = EngineMode.luaBytecode;
        final bridge = LuaLike();

        await bridge.execute('''
        local a, b = 20, 30
        local f = function (x)
          if x == "set" then
            a = 10 + b
            b = b + 1
          else
            return a
          end
        end

        local loaded = assert(load(string.dump(f), "", "b", nil))
        first = loaded()
        up1 = debug.getupvalue(loaded, 1)
        up2 = debug.getupvalue(loaded, 2)
      ''');

        expect((bridge.getGlobal('first') as Value?)?.raw, isNull);
        expect((bridge.getGlobal('up1') as Value?)?.raw, equals('a'));
        expect((bridge.getGlobal('up2') as Value?)?.raw, equals('b'));
      },
    );

    test(
      'string.dump reuses repeated source strings in lua_bytecode',
      () async {
        LuaLikeConfig().defaultEngineMode = EngineMode.luaBytecode;
        final bridge = LuaLike();

        await bridge.execute(r'''
        local str = "|" .. string.rep("X", 50) .. "|"
        local foo = load(string.format([[
          local str <const> = "%s"
          return {
            function () return str end,
            function () return str end,
            function () return str end
          }
        ]], str))
        local dump = string.dump(foo)
        _, count = string.gsub(dump, str, {})
      ''');

        expect((bridge.getGlobal('count') as Value?)?.raw, equals(2));
      },
    );

    test('command runner flag selects lua_bytecode engine mode', () async {
      LuaLikeConfig().defaultEngineMode = EngineMode.ast;

      final runner = LuaLikeCommandRunner();
      await runner.run(['--lua-bytecode', '--version']);

      expect(LuaLikeConfig().defaultEngineMode, EngineMode.luaBytecode);
    });

    test(
      'CLI runs raw luac chunks under --lua-bytecode',
      () async {
        // This exercises the real `dart run bin/main.dart` path, so a clean
        // machine can spend most of the default test budget compiling the CLI.
        final tempDir = Directory.systemTemp.createTempSync(
          'lualike_lua_bytecode_cli_',
        );
        final sourceFile = File('${tempDir.path}/fixture.lua');
        final chunkFile = File('${tempDir.path}/fixture.luac');

        try {
          sourceFile.writeAsStringSync("print('bytecode cli ok')");
          final compile = Process.runSync(luacBinary!, <String>[
            '-o',
            chunkFile.path,
            sourceFile.path,
          ]);
          expect(compile.exitCode, equals(0), reason: '${compile.stderr}');

          final result = await Process.run(
            Platform.resolvedExecutable,
            <String>[
              'run',
              'pkgs/lualike/bin/main.dart',
              '--lua-bytecode',
              chunkFile.path,
            ],
          );

          expect(result.exitCode, equals(0), reason: '${result.stderr}');
          expect(result.stdout as String, contains('bytecode cli ok'));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
      skip: skipReason,
      timeout: Timeout.factor(4),
    );

    test(
      'command runner auto-selects lua_bytecode engine mode for raw luac chunks',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'lualike_lua_bytecode_runner_auto_',
        );
        final sourceFile = File('${tempDir.path}/fixture.lua');
        final chunkFile = File('${tempDir.path}/fixture.luac');

        try {
          LuaLikeConfig().defaultEngineMode = EngineMode.ast;
          sourceFile.writeAsStringSync('return 42');
          final compile = Process.runSync(luacBinary!, <String>[
            '-o',
            chunkFile.path,
            sourceFile.path,
          ]);
          expect(compile.exitCode, equals(0), reason: '${compile.stderr}');

          final runner = LuaLikeCommandRunner();
          await runner.run([chunkFile.path]);

          expect(LuaLikeConfig().defaultEngineMode, EngineMode.luaBytecode);
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
      skip: skipReason,
      timeout: Timeout.factor(4),
    );

    test(
      'unsupported source subsets fail explicitly without AST fallback',
      () async {
        await expectLater(
          executeCode(
            'goto finish; local x = 1; ::finish:: return x',
            mode: EngineMode.luaBytecode,
          ),
          throwsA(
            predicate(
              (Object? error) =>
                  error.toString().contains("jumps into the scope of 'x'"),
            ),
          ),
        );
      },
    );
  });
}

String? _resolveLuacBinary() {
  const candidates = <String>[
    '/home/kingwill101/Downloads/lua-5.5.0_Linux68_64_bin/luac55',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  final result = Process.runSync('sh', const [
    '-lc',
    'command -v luac55 || command -v luac',
  ]);
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}

Object? _unwrap(Object? value) {
  return switch (value) {
    final Value wrapped => _unwrap(wrapped.raw),
    final LuaString wrapped => wrapped.toLatin1String(),
    _ => value,
  };
}

List<Object?> _flatten(Object? value) {
  return switch (value) {
    final Value wrapped when wrapped.isMulti =>
      (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false),
    final Value wrapped => <Object?>[_unwrap(wrapped)],
    final List<Object?> values => values.map(_unwrap).toList(growable: false),
    _ => <Object?>[_unwrap(value)],
  };
}

String _luaStringLiteral(String value) {
  final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  return "'$escaped'";
}

String _normalizePathSeparators(String value) {
  return value.replaceAll(r'\', '/');
}

String _setlistBackedConstructorSource() {
  final prefix = List<String>.generate(
    80,
    (index) => '${index + 1}',
    growable: false,
  ).join(', ');
  return '''
local function tail()
  return 81, 82
end
local t = {$prefix, tail()}
return t[1], t[63], t[64], t[80], t[81], t[82]
''';
}
