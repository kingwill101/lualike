import 'package:lualike_test/test.dart';

void main() {
  late LuaLike lua;

  setUp(() => lua = LuaLike());

  Object? unwrapRaw(Object? value) => switch (value) {
    final Value wrapper => unwrapRaw(wrapper.raw),
    final LuaString luaString => luaString.toString(),
    _ => value,
  };

  test('pcall(load(...)) reports chunk source for runtime errors', () async {
    const script = r'''
      local function doit (s)
        local f, msg = load(s)
        if not f then return msg end
        local ok, msg = pcall(f)
        return (not ok) and msg
      end

      return doit("local a = 2.0^100; x = a << 2")
    ''';

    final result = await lua.execute(script) as Value;
    final message = result.raw as String;

    expect(
      message,
      contains('[string "local a = 2.0^100; x = a << 2"]:1:'),
    );
    expect(message, contains("local 'a'"));
  });

  test('pcall(load(...)) preserves error(message, 0) location suppression', () async {
    const script = r'''
      local function doit (s)
        local f, msg = load(s)
        if not f then return msg end
        local ok, msg = pcall(f)
        return (not ok) and msg
      end

      return doit("error('hi', 0)")
    ''';

    final result = await lua.execute(script) as Value;
    expect(result.raw, equals('hi'));
  });

  test('pcall(require(...)) preserves builtin module-not-found messages', () async {
    const script = r'''
      local oldpath = package.path
      local oldcpath = package.cpath

      package.path = "?.lua;?/?"
      package.cpath = "?.so;?/init"

      local ok, msg = pcall(require, "XXX")

      package.path = oldpath
      package.cpath = oldcpath

      return ok, msg
    ''';

    final result = await lua.execute(script) as List<Object?>;
    final ok = unwrapRaw(result[0]);
    final message = unwrapRaw(result[1]) as String;

    expect(ok, isFalse);
    expect(
      message,
      equals(
        "module 'XXX' not found:\n"
        "\tno field package.preload['XXX']\n"
        "\tno file 'XXX.lua'\n"
        "\tno file 'XXX/XXX'\n"
        "\tno file 'XXX.so'\n"
        "\tno file 'XXX/init'",
      ),
    );
  });

  test('pcall preserves stripped-debug unknown location prefixes', () async {
    const script = r'''
      local f = function (a) return a + 1 end
      f = assert(load(string.dump(f, true)))
      local ok, err = pcall(f, {})
      assert(not ok)
      return err
    ''';

    final result = await lua.execute(script) as Value;
    expect(result.raw, startsWith('?:?: '));
    expect(result.raw, contains('table value'));
  });

  test('pcall(load(...)) preserves field diagnostics when SELF overflows', () async {
    const script = r'''
      local t = {}
      for i = 1, 1000 do
        t[i] = "aaa = x" .. i
      end
      local s = table.concat(t, "; ")

      local f = assert(load(s .. "; local t = {}; t:bbb()"))
      local ok, err = pcall(f)
      assert(not ok)
      return err
    ''';

    final result = await lua.execute(script) as Value;
    final message = result.raw as String;

    expect(message, contains("field 'bbb'"));
    expect(message, isNot(contains("method 'bbb'")));
  });

  test('load syntax errors cap @ and = chunk ids at LUA_IDSIZE - 1', () async {
    const script = r'''
      local function prefix_for (source)
        local _, msg = load("x", source)
        return string.match(msg, "^([^:]*):")
      end

      return prefix_for("@" .. string.rep("x", 70)),
             prefix_for("=" .. string.rep("x", 70))
    ''';

    final result = await lua.execute(script) as List<Object?>;
    String normalize(Object? raw) => switch (raw) {
      final LuaString value => value.toString(),
      final String value => value,
      final Value value => normalize(value.raw),
      final Object? other => throw StateError('unexpected prefix value: $other'),
    };
    final expected = '...${List.filled(56, 'x').join()}';
    final atPrefix = normalize(result[0]);
    final exactPrefix = normalize(result[1]);

    expect(atPrefix.length, equals(59));
    expect(atPrefix, equals(expected));
    expect(exactPrefix.length, equals(59));
    expect(exactPrefix, equals(List.filled(59, 'x').join()));
  });

  test('dotted function definitions preserve Lua index diagnostics', () async {
    const script = r'''
      local f = assert(load("function a.x.y ()\n a = a + 1\n end"))
      local _, msg = pcall(f)
      return msg
    ''';

    final result = await lua.execute(script) as Value;
    final message = result.raw as String;

    expect(message, contains(':1:'));
    expect(message, contains("attempt to index a nil value (global 'a')"));
  });

  test('multiline load runtime errors report operator and call lines', () async {
    const script = r'''
      local function lineerror (s)
        local f = assert(load(s))
        local _, msg = pcall(f)
        return tonumber(string.match(msg, ":(%d+):")), msg
      end

      local line1, msg1 = lineerror("a = \na\n+\n{}")
      local lineUnary, msgUnary = lineerror("a\n=\n-\n\nprint\n;")
      local line2, msg2 = lineerror([[
        a
        (     -- <<
        23)
      ]])

      return line1, msg1, lineUnary, msgUnary, line2, msg2
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect((result[0] as Value).raw, equals(3));
    expect((result[1] as Value).raw, contains('arithmetic'));
    expect((result[2] as Value).raw, equals(3));
    expect((result[3] as Value).raw, contains('arithmetic'));
    expect((result[4] as Value).raw, equals(2));
    expect((result[5] as Value).raw, contains('call'));
  });

  test('global function definitions write through active _ENV', () async {
    const script = r'''
      local function lineerror (s)
        local f = assert(load(s))
        local _, msg = pcall(f)
        return tonumber(string.match(msg, ":(%d+):")), msg
      end

      local line, msg = lineerror([[
        _ENV = 1
        global function foo ()
          local a = 10
          return a
        end
      ]])

      return line, msg
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect((result[0] as Value).raw, equals(2));
    expect((result[1] as Value).raw, contains('index'));
  });

  test('load-created chunks do not capture caller locals as globals', () async {
    const script = r'''
      global <const> *

      local function dostring (x)
        return assert(load("x = 'ok'"), "")()
      end

      dostring("shadow")
      return x
    ''';

    final result = await lua.execute(script) as Value;
    expect(unwrapRaw(result.raw), equals('ok'));
  });

  test('error(message, level) preserves requested runtime line', () async {
    const script = r'''
      local p = [[
        function g() f() end
        function f(x) error('a', XX) end
        g()
      ]]

      local function run(xx)
        XX = xx
        local _, msg = pcall(assert(load(p)))
        return tonumber(string.match(msg or "", ":(%d+):")), msg
      end

      local l3, m3 = run(3)
      local l0, m0 = run(0)
      local l1, m1 = run(1)
      local l2, m2 = run(2)
      return l3, m3, l0, m0, l1, m1, l2, m2
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect((result[0] as Value).raw, equals(3));
    expect((result[1] as Value).raw, contains('a'));
    expect((result[2] as Value).raw, isNull);
    expect((result[3] as Value).raw, equals('a'));
    expect((result[4] as Value).raw, equals(2));
    expect((result[5] as Value).raw, contains('a'));
    expect((result[6] as Value).raw, equals(1));
    expect((result[7] as Value).raw, contains('a'));
  });

  test('load duplicate labels report the later label line', () async {
    const script = r'''
      local _, msg = load([[
        ::L1::
        ::L1::
      ]])
      return tonumber(string.match(msg, ":(%d+):")), msg
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect((result[0] as Value).raw, equals(2));
    expect((result[1] as Value).raw, contains('already defined'));
  });

  test('load reports goto barriers for wildcard global declarations', () async {
    const script = r'''
      local _, msg = load([[ goto l2; global *; ::l1:: ::l2:: print(3) ]])
      return msg
    ''';

    final result = await lua.execute(script) as Value;

    expect(result.raw, contains("scope of '*'"));
  });

  test('xpcall recurses through error-handler failures until completion', () async {
    const script = r'''
      local function err (n)
        if type(n) ~= "number" then
          return n
        elseif n == 0 then
          return "END"
        else
          error(n - 1)
        end
      end

      local res1, msg1 = xpcall(error, err, 170)
      local res2, msg2 = xpcall(error, err, 300)
      return res1, msg1, res2, msg2
    ''';

    final result = await lua.execute(script) as List<Object?>;
    expect(unwrapRaw(result[0]), isFalse);
    expect(unwrapRaw(result[1]), equals('END'));
    expect(unwrapRaw(result[2]), isFalse);
    expect(unwrapRaw(result[3]), equals('C stack overflow'));
  });

  test('assert preserves explicit message objects and defaults location text', () async {
    const script = r'''
      local t = {}

      local ok1, msg1 = pcall(assert, false, "X", t)
      local ok2, msg2 = pcall(function () assert(false) end)
      local ok3, msg3 = pcall(assert, false, t)
      local ok4, msg4 = pcall(assert, nil, nil)
      local ok5, msg5 = pcall(assert)

      return ok1, msg1, ok2, msg2, ok3, msg3 == t, ok4, msg4, ok5, msg5
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect(unwrapRaw(result[0]), isFalse);
    expect(unwrapRaw(result[1]), equals('X'));
    expect(unwrapRaw(result[2]), isFalse);
    expect(unwrapRaw(result[3]), contains('assertion failed!'));
    expect(unwrapRaw(result[4]), isFalse);
    expect(unwrapRaw(result[5]), isTrue);
    expect(unwrapRaw(result[6]), isFalse);
    expect(unwrapRaw(result[7]), isA<String>());
    expect(unwrapRaw(result[8]), isFalse);
    expect(unwrapRaw(result[9]), contains('value expected'));
  });

  test('xpcall preserves message-handler objects for bad string.find arguments', () async {
    const script = r'''
      local a, b, c = xpcall(string.find, function (x) return {} end, true, "al")
      return a, type(b), c == nil
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect(unwrapRaw(result[0]), isFalse);
    expect(unwrapRaw(result[1]), equals('table'));
    expect(unwrapRaw(result[2]), isTrue);
  });

  test('load syntax errors report whole offending tokens', () async {
    const script = r'''
      local function syntaxmsg (source)
        local _, msg = load(source)
        return msg
      end

      return syntaxmsg("syntax error"),
             syntaxmsg("1.000"),
             syntaxmsg("[[a]]"),
             syntaxmsg("'aa'"),
             syntaxmsg("while << do end"),
             syntaxmsg("for >> do end"),
             syntaxmsg("a" .. string.char(1) .. "a = 1"),
             syntaxmsg(string.char(255) .. "a = 1")
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect(unwrapRaw(result[0]), contains("near 'error'"));
    expect(unwrapRaw(result[1]), contains("near '1.000'"));
    expect(unwrapRaw(result[2]), contains("near '[[a]]'"));
    expect(unwrapRaw(result[3]), contains("near ''aa''"));
    expect(unwrapRaw(result[4]), contains("near '<<'"));
    expect(unwrapRaw(result[5]), contains("<name> expected near '>>'"));
    expect(unwrapRaw(result[6]), contains("near '<\\1>'"));
    expect(unwrapRaw(result[7]), contains("near '<\\255>'"));
  });

  test('load rejects oversized syntax forms before execution', () async {
    const script = r'''
      local function gencode (init, rep, close, repc, n)
        return init .. string.rep(rep, n) .. close .. string.rep(repc, n)
      end

      local _, localsMsg = load(gencode("local a", ",a", ";", "", 500))
      local _, assignMsg = load(gencode("local a; a", ",a", "= 1", ",1", 500))
      local _, groupMsg = load(gencode("return ", "(", "2", ")", 500))
      local _, callMsg = load(gencode(
        "local function a (x) return x end; return ",
        "a(",
        "2.2",
        ")",
        500))

      return localsMsg, assignMsg, groupMsg, callMsg
    ''';

    final result = await lua.execute(script) as List<Object?>;

    expect(unwrapRaw(result[0]), anyOf(contains('too many'), contains('overflow')));
    expect(unwrapRaw(result[1]), anyOf(contains('too many'), contains('overflow')));
    expect(unwrapRaw(result[2]), anyOf(contains('too many'), contains('overflow')));
    expect(unwrapRaw(result[3]), anyOf(contains('too many'), contains('overflow')));
  });

  test('load rejects calls with too many registers', () async {
    const script = r'''
      local _, msg = load("a = f(x" .. string.rep(",x", 260) .. ")")
      return msg
    ''';

    final result = await lua.execute(script) as Value;
    expect(result.raw, contains('too many registers'));
  });

  test('load rejects functions with too many upvalues before expression overflow', () async {
    const script = r'''
      local lim = 127
      local s = "local function fooA ()\n  local "
      for j = 1, lim do
        s = s .. "a" .. j .. ", "
      end
      s = s .. "b,c\n"
      s = s .. "local function fooB ()\n  local "
      for j = 1, lim do
        s = s .. "b" .. j .. ", "
      end
      s = s .. "b\n"
      s = s .. "function fooC () return b+c"
      for j = 1, lim do
        s = s .. "+a" .. j .. "+b" .. j
      end
      s = s .. "\nend  end end"
      local _, msg = load(s)
      return msg
    ''';

    final result = await lua.execute(script) as Value;
    final message = result.raw as String;

    expect(message, contains('too many upvalues'));
    expect(message, contains('line 5'));
  });

  test('load rejects oversized local declarations before missing-end parser failures', () async {
    const script = r'''
      local s = "\nfunction foo ()\n  local "
      for j = 1, 200 do
        s = s .. "a" .. j .. ", "
      end
      s = s .. "b\n"
      local _, msg = load(s)
      return msg
    ''';

    final result = await lua.execute(script) as Value;
    final message = result.raw as String;

    expect(message, contains('too many local variables'));
    expect(message, contains('line 2'));
  });
}
