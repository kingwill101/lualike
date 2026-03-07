@Tags(['lua_bytecode'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/command/lualike_command_runner.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:test/test.dart';

void main() {
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

Object? _unwrap(Object? value) {
  return switch (value) {
    final Value wrapped => wrapped.raw,
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
