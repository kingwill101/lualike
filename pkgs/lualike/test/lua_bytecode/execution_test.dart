@Tags(['lua_bytecode'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  final luacBinary = _resolveLuacBinary();
  final skipReason = luacBinary == null
      ? 'luac55 not available for lua_bytecode execution tests'
      : null;

  group('lua_bytecode execution', () {
    test('executes global access and compare/jump control flow', () async {
      final results = await _executeFixture(
        luacBinary!,
        'return math.sqrt(49), (_ENV == _G)',
      );

      expect(results, equals(<Object?>[7, true]));
    }, skip: skipReason);

    test('executes raw and metamethod comparison bytecode', () async {
      final results = await _executeFixture(luacBinary!, '''
local eq = {
  __eq = function(a, b)
    return a.id == b.id
  end
}
local lt = {
  __lt = function(a, b)
    local left = type(a) == 'table' and a.value or a
    local right = type(b) == 'table' and b.value or b
    return left < right
  end
}
local le = {
  __le = function(a, b)
    local left = type(a) == 'table' and a.value or a
    local right = type(b) == 'table' and b.value or b
    return left <= right
  end
}

local rawLeft = {}
local rawRight = {}
local eqLeft = setmetatable({id = 1}, eq)
local eqRight = setmetatable({id = 1}, { __eq = eq.__eq })
local ltLeft = setmetatable({value = 1}, lt)
local ltRight = setmetatable({value = 2}, { __lt = lt.__lt })
local leLeft = setmetatable({value = 2}, le)
local leRight = setmetatable({value = 2}, { __le = le.__le })
local immediateLt = setmetatable({value = 2}, lt)
local immediateLe = setmetatable({value = 2}, le)

return rawLeft == rawRight,
       eqLeft == eqRight,
       ltLeft < ltRight,
       leLeft <= leRight,
       immediateLt < 3,
       immediateLt > 1,
       immediateLe <= 2,
       immediateLe >= 2,
       rawLeft == 1
''');

      expect(
        results,
        equals(<Object?>[
          false,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          false,
        ]),
      );
    }, skip: skipReason);

    test('executes nested closures with captured upvalues', () async {
      final results = await _executeFixture(luacBinary!, '''
local function outer(x)
  local function inner(y)
    return x + y
  end
  return inner
end
return outer(40)(2)
''');

      expect(results, equals(<Object?>[42]));
    }, skip: skipReason);

    test(
      'executes local recursive closures that shadow declared globals',
      () async {
        final results = await _executeFixture(luacBinary!, '''
global <const> *
global fact = false
do
  local res = 1
  local function fact(n)
    if n == 0 then
      return res
    end
    return n * fact(n - 1)
  end
  return fact(5), fact == false
end
''');

        expect(results, equals(<Object?>[120, false]));
      },
      skip: skipReason,
    );

    test('executes numeric for loops', () async {
      final results = await _executeFixture(luacBinary!, '''
local sum = 0
for i = 1, 4 do
  sum = sum + i
end
return sum
''');

      expect(results, equals(<Object?>[10]));
    }, skip: skipReason);

    test('executes generic for loops over stdlib iterators', () async {
      final results = await _executeFixture(luacBinary!, '''
local total = 0
for _, value in ipairs({1, 2, 3}) do
  total = total + value
end
return total
''');

      expect(results, equals(<Object?>[6]));
    }, skip: skipReason);

    test('executes vararg return flow', () async {
      final results = await _executeFixture(luacBinary!, '''
local function first(...)
  return ...
end
return first(10, 20, 30)
''');

      expect(results, equals(<Object?>[10, 20, 30]));
    }, skip: skipReason);

    test(
      'executes coroutine yield and resume for bytecode closures',
      () async {
        final results = await _executeFixture(luacBinary!, '''
local co = coroutine.create(function(a)
  local resumed = coroutine.yield(a + 1)
  return a + resumed
end)

local ok1, yielded = coroutine.resume(co, 4)
local midStatus = coroutine.status(co)
local ok2, finalValue = coroutine.resume(co, 6)
local finalStatus = coroutine.status(co)

return ok1, yielded, midStatus, ok2, finalValue, finalStatus
''');

        expect(
          results,
          equals(<Object?>[true, 5, 'suspended', true, 10, 'dead']),
        );
      },
      skip: skipReason,
    );

    test('executes arithmetic and bitwise opcode families', () async {
      final results = await _executeFixture(luacBinary!, '''
local function sample(a, b, c)
  return a % b, a ^ b, a // b, a - c, a * 5, a / c,
         a & b, a | c, a ~ b, c << b, a >> c, ~a
end
return sample(7, 3, 2)
''');

      expect(
        results,
        equals(<Object?>[1, 343, 2, 5, 35, 3.5, 3, 7, 4, 16, 1, -8]),
      );
    }, skip: skipReason);

    test('executes float modulo edge cases like upstream Lua', () async {
      final results = await _executeFixture(luacBinary!, '''
return 0.0 % 0,
       1.3 % 0,
       1 % math.huge,
       1e30 % math.huge,
       1e30 % -math.huge,
       -1 % math.huge,
       -1 % -math.huge
''');

      expect(results[0] is double && (results[0] as double).isNaN, isTrue);
      expect(results[1] is double && (results[1] as double).isNaN, isTrue);
      expect(
        results.sublist(2),
        equals(<Object?>[
          1,
          1e30,
          double.negativeInfinity,
          double.infinity,
          -1,
        ]),
      );
    }, skip: skipReason);

    test('skips dead placeholder CLOSE emitted after goto', () async {
      final results = await _executeFixture(luacBinary!, '''
local events = {}
local mt = {
  __close = function(x)
    events[#events + 1] = x.name
  end
}

do
  local x <close> = setmetatable({name = 'x'}, mt)
  goto skip
  events[#events + 1] = 'body'
  ::skip::
  events[#events + 1] = 'after'
end

return table.concat(events, ',')
''');

      expect(results, equals(<Object?>['after,x']));
    }, skip: skipReason);

    test('rejects invalid ordering comparisons', () async {
      await expectLater(
        _executeFixture(luacBinary!, '''
local x = {}
return x < 1
'''),
        throwsA(
          predicate(
            (Object? error) => error.toString().contains(
              'attempt to compare table with number',
            ),
          ),
        ),
      );
    }, skip: skipReason);

    test('rejects <= when only __lt exists', () async {
      await expectLater(
        _executeFixture(luacBinary!, '''
local x = setmetatable({value = 2}, {
  __lt = function(a, b)
    local left = type(a) == 'table' and a.value or a
    local right = type(b) == 'table' and b.value or b
    return left < right
  end
})
return x <= 2
'''),
        throwsA(
          predicate(
            (Object? error) => error.toString().contains(
              'attempt to compare table with number',
            ),
          ),
        ),
      );
    }, skip: skipReason);

    test('executes concatenation and method-call bytecode', () async {
      final results = await _executeFixture(luacBinary!, '''
local function join(a, b)
  return a .. b, a .. 1 .. b
end

local t = {x = 41}
function t:add(y)
  return self.x + y
end

local first, second = join('x', 'y')
return first, second, t:add(1)
''');

      expect(results, equals(<Object?>['xy', 'x1y', 42]));
    }, skip: skipReason);

    test('executes arithmetic and concat metamethod fallback', () async {
      final results = await _executeFixture(luacBinary!, '''
local addMt = {
  __add = function(a, b)
    return a.value + b.value
  end
}
local subMt = {
  __sub = function(a, b)
    return a.value - b
  end
}
local mulMt = {
  __mul = function(a, b)
    return a.value * b
  end
}
local concatMt = {
  __concat = function(a, b)
    return a.value .. b.value
  end
}

local addLeft = setmetatable({value = 40}, addMt)
local addRight = setmetatable({value = 2}, addMt)
local subValue = setmetatable({value = 7}, subMt)
local mulValue = setmetatable({value = 7}, mulMt)
local concatLeft = setmetatable({value = 'x'}, concatMt)
local concatRight = setmetatable({value = 'y'}, concatMt)

return addLeft + addRight, subValue - 2, mulValue * 5, concatLeft .. concatRight
''');

      expect(results, equals(<Object?>[42, 5, 35, 'xy']));
    }, skip: skipReason);

    test('executes table access and store metamethod bytecode', () async {
      final results = await _executeFixture(luacBinary!, '''
local viaTable = setmetatable({}, { __index = {foo = 41} })
local viaFunction = setmetatable({}, {
  __index = function(_, key)
    return 'idx:' .. key
  end
})

local sink = {}
local writeThroughTable = setmetatable({}, { __newindex = sink })
local writeThroughFunction = setmetatable({}, {
  __newindex = function(t, key, value)
    rawset(t, 'seen', key .. '=' .. tostring(value))
  end
})

writeThroughTable.answer = 42
writeThroughFunction.result = 99

return viaTable.foo, viaFunction.bar, sink.answer, writeThroughFunction.seen
''');

      expect(results, equals(<Object?>[41, 'idx:bar', 42, 'result=99']));
    }, skip: skipReason);

    test('executes open-result call and table construction flow', () async {
      final results = await _executeFixture(luacBinary!, '''
local function all(...)
  return ...
end
local function id(...)
  return ...
end
local function pick(a, b, c)
  return a, b, c
end

local first, second, third = id(all(7, 8, 9))
local x, y, z = pick(all(1, 2, 3))
local t = {all(4, 5, 6)}

return first, second, third, x, y, z, t[1], t[2], t[3]
''');

      expect(results, equals(<Object?>[7, 8, 9, 1, 2, 3, 4, 5, 6]));
    }, skip: skipReason);

    test('executes large table constructors with SETLIST EXTRAARG', () async {
      final items = List<String>.generate(
        1100,
        (index) => '${index + 1}',
        growable: false,
      ).join(', ');
      final results = await _executeFixture(
        luacBinary!,
        'local t = {$items}\nreturn t[1], t[1024], t[1100], #t\n',
      );

      expect(results, equals(<Object?>[1, 1024, 1100, 1100]));
    }, skip: skipReason);

    test('executes length for supported table cases', () async {
      final results = await _executeFixture(luacBinary!, '''
local withMeta = setmetatable({1, nil, 3}, {
  __len = function()
    return 77
  end
})
local plain = {1, 2, 3, 4}
local dict = {answer = 42}
local holey = {[1] = 'a', [3] = 'c'}

return #plain, #withMeta, #dict, #holey
''');

      expect(results, equals(<Object?>[4, 77, 0, 1]));
    }, skip: skipReason);

    test(
      'executes to-be-closed locals on return and tailcall paths',
      () async {
        final results = await _executeFixture(luacBinary!, '''
local mt = {
  __close = function(self, err)
    _G.trace = (_G.trace or '') .. 'c'
  end
}

local function g()
  return 99
end

local function normal()
  local value <close> = setmetatable({}, mt)
  return 42
end

local function tail()
  local value <close> = setmetatable({}, mt)
  return g()
end

return normal(), tail(), trace
''');

        expect(results, equals(<Object?>[42, 99, 'cc']));
      },
      skip: skipReason,
    );

    test(
      'executes generic-for close slots and validates close attributes',
      () async {
        final results = await _executeFixture(luacBinary!, '''
local mt = {
  __close = function(self, err)
    _G.trace = (_G.trace or '') .. 'c'
  end
}

local function iter(state, control)
  if control == nil then
    return 1
  end
  return nil
end

local function looped()
  for v in iter, nil, nil, setmetatable({}, mt) do
    return v
  end
end

return looped(), trace
''');

        expect(results, equals(<Object?>[1, 'c']));
      },
      skip: skipReason,
    );

    test('rejects invalid to-be-closed values at runtime', () async {
      await expectLater(
        _executeFixture(luacBinary!, '''
local function f()
  local value <close> = {}
  return value
end
return f()
'''),
        throwsA(
          predicate(
            (Object? error) => error.toString().contains(
              "variable 'value' got a non-closable value",
            ),
          ),
        ),
      );
    }, skip: skipReason);

    test(
      'does not count cloned shared string constants in collectgarbage count deltas',
      () async {
        final results = await _executeFixture(luacBinary!, '''
local m = collectgarbage('count')
local n = collectgarbage('count')
return n - m
''');

        expect(results, equals(<Object?>[0.0]));
      },
      skip: skipReason,
    );
  });
}

Future<List<Object?>> _executeFixture(String luacBinary, String source) async {
  final fixture = _compileFixture(luacBinary, source);
  final runtime = Interpreter();
  final loadResult = await runtime.loadChunk(
    LuaChunkLoadRequest(
      source: Value(
        LuaString.fromBytes(Uint8List.fromList(fixture.chunkBytes)),
      ),
      chunkName: fixture.sourcePath,
      mode: 'b',
    ),
  );

  if (!loadResult.isSuccess) {
    fail('failed to load upstream chunk: ${loadResult.errorMessage}');
  }

  final execution = await loadResult.chunk!.call(const []);
  return _flattenResult(execution);
}

List<Object?> _flattenResult(Object? result) {
  return switch (result) {
    final Value value when value.isMulti =>
      (value.raw as List<Object?>).map(_unwrapValue).toList(growable: false),
    final Value value => <Object?>[_unwrapValue(value)],
    final List<Object?> values =>
      values.map(_unwrapValue).toList(growable: false),
    _ => <Object?>[_unwrapValue(result)],
  };
}

Object? _unwrapValue(Object? value) {
  return switch (value) {
    final Value wrapped when wrapped.raw is LuaString =>
      (wrapped.raw as LuaString).toString(),
    final Value wrapped => wrapped.raw,
    final LuaString stringValue => stringValue.toString(),
    _ => value,
  };
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

({List<int> chunkBytes, String sourcePath}) _compileFixture(
  String luacBinary,
  String source,
) {
  final tempDir = Directory.systemTemp.createTempSync(
    'lualike_lua_bytecode_execution_',
  );
  final sourceFile = File('${tempDir.path}/fixture.lua');
  final chunkFile = File('${tempDir.path}/fixture.luac');

  try {
    sourceFile.writeAsStringSync(source);
    final compile = Process.runSync(luacBinary, <String>[
      '-o',
      chunkFile.path,
      sourceFile.path,
    ]);
    if (compile.exitCode != 0) {
      fail('luac compile failed: ${compile.stderr}');
    }

    return (
      chunkBytes: chunkFile.readAsBytesSync(),
      sourcePath: sourceFile.path,
    );
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}
