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

    test('executeCode runs const local declarations via emitted chunks', () async {
      final result = await executeCode('''
local prefix <const> = "byte"
local suffix <const> = "code"
return prefix .. suffix
''', mode: EngineMode.luaBytecode);

      expect(_unwrap(result), equals('bytecode'));
    });

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
      'executeCode emits arithmetic metamethod follow-up opcodes',
      () async {
        final result = await executeCode(r'''
local smt = getmetatable("")
smt.__band = function(x, y) return 42 end
return "x" & "y"
''', mode: EngineMode.luaBytecode);

        expect(_unwrap(result), equals(42));
      },
    );

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

    test('executeCode rejects assignment to const locals in emitted chunks', () async {
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
    });

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
        bridge.setGlobal('t', <Object?, Object?>{
          'a': <Object?, Object?>{
            'b': <Object?, Object?>{'base': 4},
          },
        });

        final result = await bridge.execute('''
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

    test('executeCode passes loader arguments to required source chunks', () async {
      final tempDir = await Directory.systemTemp.createTemp('lbc_require_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final moduleFile = File('${tempDir.path}/names.lua');
      await moduleFile.writeAsString('return {...}\n');

      final modulePath = moduleFile.path.replaceAll('\\', '/');
      final searchPath = '${tempDir.path.replaceAll('\\', '/')}/?.lua';

      final result = await executeCode('''
package.path = ${_luaStringLiteral(searchPath)}
local loaded = require("names")
return loaded[1], loaded[2]
''', mode: EngineMode.luaBytecode);

      expect(_flatten(result), equals(<Object?>['names', modulePath]));
    });

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

    test('command runner flag selects lua_bytecode engine mode', () async {
      LuaLikeConfig().defaultEngineMode = EngineMode.ast;

      final runner = LuaLikeCommandRunner();
      await runner.run(['--lua-bytecode', '--version']);

      expect(LuaLikeConfig().defaultEngineMode, EngineMode.luaBytecode);
    });

    test('CLI runs raw luac chunks under --lua-bytecode', () async {
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

        final result = await Process.run(Platform.resolvedExecutable, <String>[
          'run',
          'bin/main.dart',
          '--lua-bytecode',
          chunkFile.path,
        ], workingDirectory: 'pkgs/lualike');

        expect(result.exitCode, equals(0), reason: '${result.stderr}');
        expect(result.stdout as String, contains('bytecode cli ok'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    }, skip: skipReason);

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
                  error.toString().contains('no visible label for goto finish'),
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
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'");
  return "'$escaped'";
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
