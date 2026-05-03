import 'dart:typed_data';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/vararg_table.dart';
import 'package:lualike/src/stdlib/lib_base.dart';
import 'package:lualike/src/stdlib/metatables.dart';
import 'package:lualike/src/stdlib/test_lib.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:path/path.dart' as path_lib;
import 'package:test/test.dart';

void main() {
  test('environment rebinding does not mutate shared primitive cache', () {
    final interpreter = Interpreter();
    final nilValue = interpreter.constantPrimitiveValue(null);
    final env = Environment(interpreter: interpreter);

    env.declare('x', nilValue);
    env.define('x', Value(1));

    expect(nilValue.raw, isNull);
    expect(identical(interpreter.constantPrimitiveValue(null), nilValue), true);

    final stored = env.get('x');
    expect(stored, isA<Value>());
    expect((stored as Value).raw, 1);
    expect(identical(stored, nilValue), false);
  });

  test('numeric local reads reuse the runtime primitive cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final result =
        await lua.execute('''
          local x = 1
          local y = 1.5
          x = 42
          return x, x, y, y
        ''')
            as List<Object?>;
    final runtime = lua.vm;

    expect(identical(result[0], runtime.constantPrimitiveValue(42)), true);
    expect(identical(result[1], runtime.constantPrimitiveValue(42)), true);
    expect(identical(result[0], result[1]), true);
    expect(identical(result[2], runtime.constantPrimitiveValue(1.5)), true);
    expect(identical(result[3], runtime.constantPrimitiveValue(1.5)), true);
    expect(identical(result[2], result[3]), true);
  });

  test('numeric upvalue reads reuse the runtime primitive cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final result =
        await lua.execute('''
          local x = 1
          local function read()
            return x, x
          end
          x = 42
          return read()
        ''')
            as List<Object?>;
    final runtime = lua.vm;

    expect(identical(result[0], runtime.constantPrimitiveValue(42)), true);
    expect(identical(result[1], runtime.constantPrimitiveValue(42)), true);
    expect(identical(result[0], result[1]), true);
  });

  test('Dart primitive returns reuse the runtime primitive cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    lua.expose('answer', (List<Object?> _) => 42);

    final result =
        await lua.execute('return answer(), answer()') as List<Object?>;
    final runtime = lua.vm;

    expect(identical(result[0], runtime.constantPrimitiveValue(42)), true);
    expect(identical(result[1], runtime.constantPrimitiveValue(42)), true);
    expect(identical(result[0], result[1]), true);
  });

  test('Lua result expansion helpers reuse the runtime primitive cache', () {
    final interpreter = Interpreter();
    final expanded = <Object?>[];

    appendExpandedLuaResults(expanded, interpreter, [42, false]);
    appendFirstLuaResult(expanded, interpreter, [7, true]);
    final first = firstLuaResultValue(interpreter, [9, false]);

    expect(
      identical(expanded[0], interpreter.constantPrimitiveValue(42)),
      true,
    );
    expect(
      identical(expanded[1], interpreter.constantPrimitiveValue(false)),
      true,
    );
    expect(identical(expanded[2], interpreter.constantPrimitiveValue(7)), true);
    expect(identical(first, interpreter.constantPrimitiveValue(9)), true);
  });

  test('Lua result expansion helpers cache values from result carriers', () {
    final interpreter = Interpreter();
    final expanded = <Object?>[];

    appendExpandedLuaResults(
      expanded,
      interpreter,
      LuaResults(['slot', 42, false]),
    );
    appendFirstLuaResult(expanded, interpreter, LuaResults(['slot']));
    appendExpandedLuaResults(expanded, interpreter, Value.multi(['slot', 42]));

    final cachedString = interpreter.constantDartStringValue('slot');
    expect(identical(expanded[0], cachedString), true);
    expect(
      identical(expanded[1], interpreter.constantPrimitiveValue(42)),
      true,
    );
    expect(
      identical(expanded[2], interpreter.constantPrimitiveValue(false)),
      true,
    );
    expect(identical(expanded[3], cachedString), true);
    expect(identical(expanded[4], cachedString), true);
    expect(
      identical(expanded[5], interpreter.constantPrimitiveValue(42)),
      true,
    );
  });

  test('LuaResults public wrappers cache values when runtime is available', () {
    final interpreter = Interpreter();

    final wrapped = valueFromLuaSlot(
      interpreter,
      LuaResults(['slot', 42, false]),
    );
    final optional = valueFromOptionalLuaSlot(
      interpreter,
      LuaResults(['slot', 42]),
    );
    final direct = valueMultiFromLuaResults(['slot', 42], runtime: interpreter);

    final cachedString = interpreter.constantDartStringValue('slot');
    final cachedNumber = interpreter.constantPrimitiveValue(42);
    final cachedFalse = interpreter.constantPrimitiveValue(false);

    expect(identical(wrapped.multiResults![0], cachedString), true);
    expect(identical(wrapped.multiResults![1], cachedNumber), true);
    expect(identical(wrapped.multiResults![2], cachedFalse), true);
    expect(identical(optional.multiResults![0], cachedString), true);
    expect(identical(optional.multiResults![1], cachedNumber), true);
    expect(identical(direct.multiResults![0], cachedString), true);
    expect(identical(direct.multiResults![1], cachedNumber), true);
  });

  test('public global primitive writes reuse the runtime cache', () {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    lua.setGlobal('externalNumber', 42);

    final cached = runtime.constantPrimitiveValue(42);
    expect(identical(runtime.globals.get('externalNumber'), cached), true);

    final globalsTable = runtime.globals.get('_G') as Value;
    expect(
      identical((globalsTable.raw as Map)['externalNumber'], cached),
      true,
    );
  });

  test('raw global table sync wraps primitives with the runtime cache', () {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    runtime.globals.define('rawNumber', 7);

    final globalsTable = runtime.globals.get('_G') as Value;
    expect(
      identical(
        (globalsTable.raw as Map)['rawNumber'],
        runtime.constantPrimitiveValue(7),
      ),
      true,
    );
  });

  test('Lua global primitive assignments reuse the runtime cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    await lua.execute('globalNumber = 42; globalNumber = 43');

    expect(
      identical(
        runtime.globals.get('globalNumber'),
        runtime.constantPrimitiveValue(43),
      ),
      true,
    );
    expect(runtime.constantPrimitiveValue(42).raw, 42);
  });

  test('table constructor primitive entries reuse the runtime cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    final table =
        await lua.execute('return {42, false, named = 7, [4] = 42}') as Value;
    final storage = table.raw as TableStorage;

    expect(
      identical(storage.denseValueAt(1), runtime.constantPrimitiveValue(42)),
      true,
    );
    expect(
      identical(storage.denseValueAt(2), runtime.constantPrimitiveValue(false)),
      true,
    );
    expect(
      identical(storage['named'], runtime.constantPrimitiveValue(7)),
      true,
    );
    expect(
      identical(storage.denseValueAt(4), runtime.constantPrimitiveValue(42)),
      true,
    );
  });

  test('table assignment primitive writes reuse the runtime cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    await lua.execute('''
      assigned = {}
      assigned[1] = 42
      assigned.flag = false
    ''');
    final table = runtime.globals.get('assigned') as Value;
    final storage = table.raw as TableStorage;

    expect(
      identical(storage.denseValueAt(1), runtime.constantPrimitiveValue(42)),
      true,
    );
    expect(
      identical(storage['flag'], runtime.constantPrimitiveValue(false)),
      true,
    );
  });

  test('rawset primitive writes reuse the runtime cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    final table =
        await lua.execute('''
          local target = {}
          rawset(target, 1, 42)
          rawset(target, 'flag', false)
          return target
        ''')
            as Value;
    final storage = table.raw as TableStorage;

    expect(
      identical(storage.denseValueAt(1), runtime.constantPrimitiveValue(42)),
      true,
    );
    expect(
      identical(storage['flag'], runtime.constantPrimitiveValue(false)),
      true,
    );
  });

  test('ipairs primitive results reuse the runtime cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    final result =
        await lua.execute('''
          local iterator, table, index = ipairs({42, false})
          local i1, v1 = iterator(table, index)
          local i2, v2 = iterator(table, i1)
          return i1, v1, i2, v2
        ''')
            as List<Object?>;

    expect(identical(result[0], runtime.constantPrimitiveValue(1)), true);
    expect(identical(result[1], runtime.constantPrimitiveValue(42)), true);
    expect(identical(result[2], runtime.constantPrimitiveValue(2)), true);
    expect(identical(result[3], runtime.constantPrimitiveValue(false)), true);
  });

  test('next primitive results reuse the runtime cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    final result =
        await lua.execute('''
          local target = {}
          rawset(target, 1, 42)
          return next(target)
        ''')
            as List<Object?>;

    expect(identical(result[0], runtime.constantPrimitiveValue(1)), true);
    expect(identical(result[1], runtime.constantPrimitiveValue(42)), true);
  });

  test('next raw table results reuse canonical runtime wrappers', () {
    final interpreter = Interpreter();
    final nested = <Object?, Object?>{'value': 42};
    final storage = TableStorage()..['nested'] = nested;
    final table = Value(storage, interpreter: interpreter);
    final next = NextFunction(interpreter);

    final first = next.call([table]) as LuaResults;
    final second = next.call([table]) as LuaResults;
    final firstValue = first.values[1] as Value;
    final secondValue = second.values[1] as Value;

    expect(identical(firstValue, secondValue), true);
    expect(
      identical(firstValue, Value.lookupCanonicalTableWrapper(nested)),
      true,
    );
    expect(identical(firstValue.interpreter, interpreter), true);
  });

  test('packed vararg table writes reuse the runtime cache', () {
    final interpreter = Interpreter();
    final packedValue = packVarargsTable([1, 2], runtime: interpreter);
    final packed = packedValue.raw as PackedVarargTable;

    packed[1] = 42;
    packed['flag'] = false;

    expect(identical(packed[1], interpreter.constantPrimitiveValue(42)), true);
    expect(
      identical(packed['flag'], interpreter.constantPrimitiveValue(false)),
      true,
    );
  });

  test('AST named vararg tables use the runtime-aware packed table', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final table =
        await lua.execute('''
          local function capture(...t)
            t[1] = 42
            t.flag = false
            return t
          end
          return capture(1)
        ''')
            as Value;
    final runtime = lua.vm;
    final packed = table.raw as PackedVarargTable;

    expect(identical(table.interpreter, runtime), true);
    expect(identical(packed[1], runtime.constantPrimitiveValue(42)), true);
    expect(
      identical(packed['flag'], runtime.constantPrimitiveValue(false)),
      true,
    );
  });

  test('table.pack stores primitive entries with the runtime cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    final packed =
        await lua.execute('return table.pack(42, false, nil, 7)') as Value;
    final storage = packed.raw as TableStorage;

    expect(
      identical(storage.denseValueAt(1), runtime.constantPrimitiveValue(42)),
      true,
    );
    expect(
      identical(storage.denseValueAt(2), runtime.constantPrimitiveValue(false)),
      true,
    );
    expect(storage.denseValueAt(3), isNull);
    expect(
      identical(storage.denseValueAt(4), runtime.constantPrimitiveValue(7)),
      true,
    );
    expect(identical(storage['n'], runtime.constantPrimitiveValue(4)), true);
  });

  test(
    'table.move writes primitive entries through the runtime cache',
    () async {
      final lua = LuaLike(engineMode: EngineMode.ast);
      final runtime = lua.vm;

      final moved =
          await lua.execute('''
          local source = table.pack(42, false)
          local dest = {}
          table.move(source, 1, 2, 1, dest)
          return dest
        ''')
              as Value;
      final storage = moved.raw as TableStorage;

      expect(
        identical(storage.denseValueAt(1), runtime.constantPrimitiveValue(42)),
        true,
      );
      expect(
        identical(
          storage.denseValueAt(2),
          runtime.constantPrimitiveValue(false),
        ),
        true,
      );
    },
  );

  test(
    'coroutine yield primitives reuse the runtime cache internally',
    () async {
      final lua = LuaLike(engineMode: EngineMode.ast);
      final runtime = lua.vm;

      await lua.execute('''
      cachedCoroutine = coroutine.create(function()
        coroutine.yield(42, false)
        return 7
      end)
    ''');

      final coroutineValue = runtime.globals.get('cachedCoroutine') as Value;
      final coroutine = coroutineValue.raw as Coroutine;

      final first = luaResultValues(await coroutine.resume(const <Object?>[]))!;
      expect(identical(first[1], runtime.constantPrimitiveValue(42)), true);
      expect(identical(first[2], runtime.constantPrimitiveValue(false)), true);

      final second = luaResultValues(
        await coroutine.resume(const <Object?>[]),
      )!;
      expect(identical(second[1], runtime.constantPrimitiveValue(7)), true);
    },
  );

  test('missing table lookups reuse the owner runtime nil cache', () {
    final interpreter = Interpreter();
    final nilValue = interpreter.constantPrimitiveValue(null);
    final table = Value(<Object?, Object?>{}, interpreter: interpreter);

    final missing = table['missing'];

    expect(identical(missing, nilValue), true);
    expect((missing as Value).raw, isNull);
  });

  test('raw primitive table entries reuse the owner runtime cache', () async {
    final interpreter = Interpreter();
    final table = Value(<Object?, Object?>{
      'nil': null,
      'true': true,
      'int': 42,
      'float': 1.5,
      'bigint': BigInt.from(7),
    }, interpreter: interpreter);

    expect(
      identical(table['nil'], interpreter.constantPrimitiveValue(null)),
      true,
    );
    expect(
      identical(table['true'], interpreter.constantPrimitiveValue(true)),
      true,
    );
    expect(
      identical(table['int'], interpreter.constantPrimitiveValue(42)),
      true,
    );
    expect(
      identical(table['float'], interpreter.constantPrimitiveValue(1.5)),
      true,
    );
    expect(
      identical(
        table['bigint'],
        interpreter.constantPrimitiveValue(BigInt.from(7)),
      ),
      true,
    );

    expect(
      identical(
        await table.getValueAsync('int'),
        interpreter.constantPrimitiveValue(42),
      ),
      true,
    );
  });

  test('raw primitive dense entries reuse the owner runtime cache', () async {
    final interpreter = Interpreter();
    final storage = TableStorage()..setDense(1, 99);
    final table = Value(storage, interpreter: interpreter);

    expect(identical(table[1], interpreter.constantPrimitiveValue(99)), true);
    expect(
      identical(
        await table.getValueAsync(1),
        interpreter.constantPrimitiveValue(99),
      ),
      true,
    );
  });

  test('raw LuaString table entries reuse the owner runtime cache', () async {
    final interpreter = Interpreter();
    final raw = LuaString.fromDartString('cached');
    final table = Value(<Object?, Object?>{
      'field': raw,
    }, interpreter: interpreter);

    final cached = interpreter.constantStringValue(raw.bytes);
    expect(identical(table['field'], cached), true);
    expect(identical(await table.getValueAsync('field'), cached), true);
  });

  test('raw LuaString table writes store the owner runtime cache', () {
    final interpreter = Interpreter();
    final raw = LuaString.fromDartString('stored');
    final storage = TableStorage();
    final table = Value(storage, interpreter: interpreter);

    table['field'] = raw;

    expect(
      identical(storage['field'], interpreter.constantStringValue(raw.bytes)),
      true,
    );
  });

  test('raw Dart string table entries reuse the owner runtime cache', () async {
    final interpreter = Interpreter();
    final table = Value(<Object?, Object?>{
      'field': 'cached',
    }, interpreter: interpreter);

    final cached = interpreter.constantDartStringValue('cached');
    expect(identical(table['field'], cached), true);
    expect(identical(await table.getValueAsync('field'), cached), true);
  });

  test('raw Dart string table writes store the owner runtime cache', () {
    final interpreter = Interpreter();
    final storage = TableStorage();
    final table = Value(storage, interpreter: interpreter);

    table['field'] = 'stored';

    expect(
      identical(
        storage['field'],
        interpreter.constantDartStringValue('stored'),
      ),
      true,
    );
  });

  test('runtime LuaString wrapping reuses the runtime string cache', () {
    final interpreter = Interpreter();
    final raw = LuaString.fromDartString('slot');

    final wrapped = interpreter.wrapRuntimeValue(raw);
    final cached = interpreter.constantStringValue(raw.bytes);

    expect(identical(wrapped, cached), true);
    expect(identical(interpreter.wrapRuntimeValue(raw), cached), true);
  });

  test('lua_bytecode runtime Lua strings reuse the interpreter cache', () {
    final runtime = LuaBytecodeRuntime();
    final raw = LuaString.fromDartString('bytecode-slot');

    final wrapped = runtime.constantStringValue(raw.bytes);
    final cached = runtime.debugInterpreter.constantStringValue(raw.bytes);

    expect(identical(wrapped, cached), true);
    expect(identical(wrapped.interpreter, runtime), true);
  });

  test('lua_bytecode runtime raw strings reuse the byte-string cache', () {
    final runtime = LuaBytecodeRuntime();
    final raw = 'bytecode-\u00e9';

    final wrapped = runtime.constantRawStringValue(raw);
    final cached = runtime.debugInterpreter.constantStringValue(raw.codeUnits);

    expect(identical(wrapped, cached), true);
    expect(identical(wrapped.interpreter, runtime), true);
    expect((wrapped.raw as LuaString).bytes, orderedEquals(raw.codeUnits));
  });

  test('runtime Dart string values reuse the runtime string cache', () {
    final interpreter = Interpreter();

    final first = interpreter.constantDartStringValue('slot');
    final second = interpreter.constantDartStringValue('slot');
    final wrapped = interpreter.wrapRuntimeValue('slot');

    expect(identical(first, second), true);
    expect(identical(wrapped, first), true);
    expect(first.raw, isA<String>());
    expect(first.raw, 'slot');
  });

  test('script metadata globals reuse the runtime Dart string cache', () async {
    final interpreter = Interpreter();
    final scriptPath = path_lib.absolute('cache_script.lua');
    final normalizedPath = path_lib.url.joinAll(
      path_lib.split(path_lib.normalize(scriptPath)),
    );
    final normalizedDir = path_lib.url.joinAll(
      path_lib.split(path_lib.normalize(path_lib.dirname(scriptPath))),
    );

    await interpreter.evaluate('return _SCRIPT_PATH', scriptPath: scriptPath);

    expect(
      identical(
        interpreter.globals.get('_SCRIPT_PATH'),
        interpreter.constantDartStringValue(normalizedPath),
      ),
      true,
    );
    expect(
      identical(
        interpreter.globals.get('_SCRIPT_DIR'),
        interpreter.constantDartStringValue(normalizedDir),
      ),
      true,
    );
  });

  test('Lua slot helpers reuse the runtime Dart string cache', () {
    final interpreter = Interpreter();
    final cached = interpreter.constantDartStringValue('slot');
    final expanded = <Object?>[];

    appendExpandedLuaResults(expanded, interpreter, ['slot']);
    appendFirstLuaResult(expanded, interpreter, ['slot']);
    final first = firstLuaResultValue(interpreter, ['slot']);

    expect(identical(expanded[0], cached), true);
    expect(identical(expanded[1], cached), true);
    expect(identical(first, cached), true);
  });

  test(
    'Dart string stdlib results preserve raw type and reuse cache',
    () async {
      final lua = LuaLike(engineMode: EngineMode.ast);
      await lua.execute(r'''
      encoded = convert.asciiEncode("cached")
      first = convert.asciiDecode(encoded)
      second = convert.asciiDecode(encoded)
      bytes = dart.string.bytes.toBytes("cached")
      from_bytes = dart.string.bytes.fromBytes(bytes)
      dart_string_first = dart.string.replaceAll("uncached", "un", "")
      dart_string_second = dart.string.replaceAll("uncached", "un", "")
      tostring_first = tostring(123)
      tostring_second = tostring(123)
      string_lower = string.lower("CACHED")
      string_sub = string.sub("cached!", 1, 6)
      table_concat = table.concat({first})
      math_integer = math.type(3)
      math_float = math.type(3.5)
      collect_old_incremental = collectgarbage("generational")
      collect_old_generational = collectgarbage("incremental")
      os_locale = os.setlocale(nil)
      io_type = io.type(io.stdin)
      logging.enable("INFO")
      logging_level = logging.get_level()
      logging.disable()
      logging.reset_filters()
      crypto_hash_first = crypto.md5("cached")
      crypto_hash_second = crypto.md5("cached")
      local dump_target = function() return "cached" end
      string_dump_first = string.dump(dump_target)
      string_dump_second = string.dump(dump_target)
      local _, package_path_error = package.searchpath("cached", "?.lua")
      package_error = package_path_error
      debug_trace = debug.traceback("cached", 0)
      debug_what = debug.getinfo(function() end, "S").what
      _, xpcall_error = xpcall(
        function() error("cached", 0) end,
        function(message)
          xpcall_handler_message = message
          return message
        end
      )
    ''');

      final first = lua.getGlobal('first')!;
      final second = lua.getGlobal('second')!;
      final fromBytes = lua.getGlobal('from_bytes')!;
      final dartStringFirst = lua.getGlobal('dart_string_first')!;
      final dartStringSecond = lua.getGlobal('dart_string_second')!;
      final tostringFirst = lua.getGlobal('tostring_first')!;
      final tostringSecond = lua.getGlobal('tostring_second')!;
      final stringLower = lua.getGlobal('string_lower')!;
      final stringSub = lua.getGlobal('string_sub')!;
      final tableConcat = lua.getGlobal('table_concat')!;
      final mathInteger = lua.getGlobal('math_integer')!;
      final mathFloat = lua.getGlobal('math_float')!;
      final collectOldIncremental = lua.getGlobal('collect_old_incremental')!;
      final collectOldGenerational = lua.getGlobal('collect_old_generational')!;
      final osLocale = lua.getGlobal('os_locale')!;
      final ioType = lua.getGlobal('io_type')!;
      final loggingLevel = lua.getGlobal('logging_level')!;
      final cryptoHashFirst = lua.getGlobal('crypto_hash_first')!;
      final cryptoHashSecond = lua.getGlobal('crypto_hash_second')!;
      final stringDumpFirst = lua.getGlobal('string_dump_first')!;
      final stringDumpSecond = lua.getGlobal('string_dump_second')!;
      final packageError = lua.getGlobal('package_error')!;
      final debugTrace = lua.getGlobal('debug_trace')!;
      final debugWhat = lua.getGlobal('debug_what')!;
      final xpcallError = lua.getGlobal('xpcall_error')!;
      final xpcallHandlerMessage = lua.getGlobal('xpcall_handler_message')!;
      final runtime = lua.vm;

      expect(identical(first, second), true);
      expect(identical(first, fromBytes), true);
      expect(identical(first, dartStringFirst), true);
      expect(identical(first, dartStringSecond), true);
      expect(identical(first, stringLower), true);
      expect(identical(first, stringSub), true);
      expect(identical(first, tableConcat), true);
      expect(identical(tostringFirst, tostringSecond), true);
      expect(
        identical(mathInteger, runtime.constantDartStringValue('integer')),
        true,
      );
      expect(
        identical(mathFloat, runtime.constantDartStringValue('float')),
        true,
      );
      expect(
        identical(
          collectOldIncremental,
          runtime.constantDartStringValue('incremental'),
        ),
        true,
      );
      expect(
        identical(
          collectOldGenerational,
          runtime.constantDartStringValue('generational'),
        ),
        true,
      );
      expect(identical(cryptoHashFirst, cryptoHashSecond), true);
      expect(identical(stringDumpFirst, stringDumpSecond), true);
      expect(
        identical(
          stringDumpFirst,
          runtime.constantStringValue((stringDumpFirst.raw as LuaString).bytes),
        ),
        true,
      );
      expect(identical(osLocale, runtime.constantDartStringValue('C')), true);
      expect(identical(ioType, runtime.constantDartStringValue('file')), true);
      expect(
        identical(loggingLevel, runtime.constantDartStringValue('INFO')),
        true,
      );
      expect(
        identical(
          packageError,
          runtime.constantDartStringValue(packageError.raw as String),
        ),
        true,
      );
      expect(
        identical(
          debugTrace,
          runtime.constantDartStringValue(debugTrace.raw as String),
        ),
        true,
      );
      expect(
        identical(debugWhat, runtime.constantDartStringValue('Lua')),
        true,
      );
      expect(identical(xpcallError, first), true);
      expect(identical(xpcallHandlerMessage, first), true);
      expect(first.raw, isA<String>());
      expect(first.raw, 'cached');
      expect(tostringFirst.raw, isA<String>());
      expect(tostringFirst.raw, '123');
    },
  );

  test('stdlib object payload results attach the runtime', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    await lua.execute(r'''
      binary_from_base64 = convert.base64Decode("Y2FjaGVk")
      binary_from_ascii = convert.asciiEncode("cached")
      binary_from_latin1 = convert.latin1Encode("cached")
      binary_from_dart_string = dart.string.bytes.toBytes("cached")
      split_parts = dart.string.split("a,b", ",")
      date_parts = os.date("*t", 0)
      random_bytes = crypto.randomBytes(1)
    ''');
    final runtime = lua.vm;
    final binaryFromBase64 = lua.getGlobal('binary_from_base64')! as Value;
    final binaryFromAscii = lua.getGlobal('binary_from_ascii')! as Value;
    final binaryFromLatin1 = lua.getGlobal('binary_from_latin1')! as Value;
    final binaryFromDartString =
        lua.getGlobal('binary_from_dart_string')! as Value;
    final splitParts = lua.getGlobal('split_parts')! as Value;
    final dateParts = lua.getGlobal('date_parts')! as Value;
    final randomBytes = lua.getGlobal('random_bytes')! as Value;

    expect(binaryFromBase64.interpreter, same(runtime));
    expect(binaryFromAscii.interpreter, same(runtime));
    expect(binaryFromLatin1.interpreter, same(runtime));
    expect(binaryFromDartString.interpreter, same(runtime));
    expect(splitParts.interpreter, same(runtime));
    expect(dateParts.interpreter, same(runtime));
    expect(randomBytes.interpreter, same(runtime));
    expect(binaryFromDartString.raw, isA<Uint8List>());
    expect(splitParts.raw, isA<List>());
    expect(dateParts.raw, isA<Map>());
  });

  test('test library object results attach the runtime', () {
    final interpreter = Interpreter();
    final table = Value(<Object?, Object?>{}, interpreter: interpreter);

    final userdata = TestLib.newuserdata([1, 2], runtime: interpreter);
    final lightUserdata = TestLib.pushuserdata([3], runtime: interpreter);
    final tableInfo = TestLib.querytab([table], runtime: interpreter);
    final stringInfo = TestLib.querystr([
      interpreter.constantDartStringValue('abc'),
    ], runtime: interpreter);

    expect(userdata.interpreter, same(interpreter));
    expect(lightUserdata.interpreter, same(interpreter));
    expect(tableInfo.interpreter, same(interpreter));
    expect(stringInfo.interpreter, same(interpreter));
    expect(userdata.raw, isA<Map>());
    expect(lightUserdata.raw, isA<Map>());
    expect(tableInfo.raw, isA<Map>());
    expect(stringInfo.raw, isA<Map>());
  });

  test('stdlib registration wrappers attach the runtime', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    await lua.execute(r'''
      version_value = _VERSION
      utf8_iter = utf8.codes("a")
      utf8_table = utf8
      dart.string.split("a,b", ",")
      dart_string_table = dart.string
      dart_bytes_table = dart.string.bytes
      local s = "cached"
      string_method = s.sub
      gmatch_iter = string.gmatch("abc", "%a")
      utf8_gmatch_iter = string.gmatch("é", utf8.charpattern)
    ''');
    final runtime = lua.vm;
    final version = lua.getGlobal('version_value')!;
    final utf8Iterator = lua.getGlobal('utf8_iter')! as Value;
    final utf8Table = lua.getGlobal('utf8_table')! as Value;
    final dartStringTable = lua.getGlobal('dart_string_table')! as Value;
    final dartBytesTable = lua.getGlobal('dart_bytes_table')! as Value;
    final stringMethod = lua.getGlobal('string_method')! as Value;
    final gmatchIterator = lua.getGlobal('gmatch_iter')! as Value;
    final utf8GmatchIterator = lua.getGlobal('utf8_gmatch_iter')! as Value;

    expect(
      identical(version, runtime.constantDartStringValue('LuaLike 0.1')),
      true,
    );
    expect(utf8Iterator.interpreter, same(runtime));
    expect(utf8Table.interpreter, same(runtime));
    expect(dartStringTable.interpreter, same(runtime));
    expect(dartBytesTable.interpreter, same(runtime));
    expect(stringMethod.interpreter, same(runtime));
    expect(gmatchIterator.interpreter, same(runtime));
    expect(utf8GmatchIterator.interpreter, same(runtime));
  });

  test('debug active-line tables attach the runtime', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final info =
        await lua.execute(r'''
      local function subject()
        local x = 1
        return x
      end
      return debug.getinfo(subject, "L")
    ''')
            as Value;
    final runtime = lua.vm;
    final activeLines = (info.raw as Map)['activelines'] as Value;
    final lineMap = activeLines.raw as Map;

    expect(activeLines.interpreter, same(runtime));
    expect(lineMap, isNotEmpty);
    expect(
      lineMap.values.every(
        (entry) => identical(entry, runtime.constantPrimitiveValue(true)),
      ),
      true,
    );
  });

  test('debug.upvalueid reuses identity wrappers', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    await lua.execute(r'''
      local captured = 1
      local function subject()
        return captured
      end
      first_upvalue_id = debug.upvalueid(subject, 1)
      second_upvalue_id = debug.upvalueid(subject, 1)
    ''');
    final runtime = lua.vm;
    final first = lua.getGlobal('first_upvalue_id')! as Value;
    final second = lua.getGlobal('second_upvalue_id')! as Value;

    expect(identical(first, second), true);
    expect(first.interpreter, same(runtime));
  });

  test('AST string literals reuse the runtime string cache', () async {
    final runtime = Interpreter();

    final program = parse("local a = 'cached'; return a, 'cached'");
    final result = luaResultValues(await runtime.runAst(program.statements))!;
    final raw = LuaString.fromDartString('cached');
    final cached = runtime.constantStringValue(raw.bytes);

    expect(identical(result[0], cached), true);
    expect(identical(result[1], cached), true);
  });

  test('AST literal-only functions return the runtime string cache', () async {
    final runtime = Interpreter();
    final program = parse('''
          local function cached()
            return "literal-cache"
          end
          return cached(), cached()
        ''');
    final result = luaResultValues(await runtime.runAst(program.statements))!;
    final cached = runtime.constantStringValue(
      LuaString.fromDartString('literal-cache').bytes,
    );

    expect(identical(result[0], cached), true);
    expect(identical(result[1], cached), true);
    expect(identical(result[0], result[1]), true);
  });

  test('assert success strings reuse runtime string caches', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    await lua.execute('''
      lua_a = assert("cached")
      lua_b = "cached"
      dart_a = assert(tostring(123))
      dart_b = tostring(123)
    ''');
    final runtime = lua.vm;
    final rawLuaString = LuaString.fromDartString('cached');
    final luaA = lua.getGlobal('lua_a')!;
    final luaB = lua.getGlobal('lua_b')!;
    final dartA = lua.getGlobal('dart_a')!;
    final dartB = lua.getGlobal('dart_b')!;

    expect(
      identical(luaA, runtime.constantStringValue(rawLuaString.bytes)),
      true,
    );
    expect(identical(luaB, luaA), true);
    expect(identical(dartA, runtime.constantDartStringValue('123')), true);
    expect(identical(dartB, dartA), true);
  });

  test('load error strings reuse runtime Dart string cache', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    await lua.execute('''
      local _
      _, load_error = load("for")
    ''');
    final runtime = lua.vm;
    final loadError = lua.getGlobal('load_error') as Value;

    expect(
      identical(
        loadError,
        runtime.constantDartStringValue(loadError.raw as String),
      ),
      true,
    );
  });

  test(
    'require searcher string values reuse runtime Dart string cache',
    () async {
      final lua = LuaLike(engineMode: EngineMode.ast);
      final runtime = lua.vm;
      final packageValue = runtime.globals.get('package') as Value;
      final packageTable = packageValue.raw as Map;
      Object? searcherNameArg;
      Object? loaderNameArg;

      packageTable['searchers'] = Value([
        Value((List<Object?> args) {
          searcherNameArg = args[0];
          return [
            Value((List<Object?> loaderArgs) {
              loaderNameArg = loaderArgs[0];
              return loaderArgs[0];
            }, interpreter: runtime),
            runtime.constantDartStringValue('nested/../cache_mod.lua'),
          ];
        }, interpreter: runtime),
      ], interpreter: runtime);

      await lua.execute(
        'required_module, required_path = require("cache_mod")',
      );

      final moduleName = runtime.constantDartStringValue('cache_mod');
      final modulePath = runtime.constantDartStringValue('cache_mod.lua');
      expect(identical(searcherNameArg, moduleName), true);
      expect(identical(loaderNameArg, moduleName), true);
      expect(identical(lua.getGlobal('required_module'), moduleName), true);
      expect(identical(lua.getGlobal('required_path'), modulePath), true);
    },
  );

  test(
    'loaded top-level literal functions reuse runtime Lua string cache',
    () async {
      final lua = LuaLike(engineMode: EngineMode.ast);
      await lua.execute(r'''
      local chunk = assert(load('function cached_literal() return "literal-cache" end'))
      chunk()
      literal_a = cached_literal()
      literal_b = cached_literal()
    ''');
      final runtime = lua.vm;
      final cached = runtime.constantStringValue(
        LuaString.fromDartString('literal-cache').bytes,
      );

      expect(identical(lua.getGlobal('literal_a'), cached), true);
      expect(identical(lua.getGlobal('literal_b'), cached), true);
    },
  );

  test('string length metamethod reuses the runtime primitive cache', () {
    final interpreter = Interpreter();
    final raw = LuaString.fromDartString('cached');
    final value = interpreter.constantStringValue(raw.bytes);

    final result = value.callMetamethod('__len', [value]);

    expect(identical(result, interpreter.constantPrimitiveValue(6)), true);
  });

  test('table.sort fast path keeps shared primitive entries cached', () async {
    final lua = LuaLike(engineMode: EngineMode.ast);
    final runtime = lua.vm;

    final table =
        await lua.execute('''
          local t = {3, 1, 2}
          table.sort(t)
          return t
        ''')
            as Value;
    final storage = table.raw as TableStorage;

    expect(
      identical(storage.denseValueAt(1), runtime.constantPrimitiveValue(1)),
      true,
    );
    expect(
      identical(storage.denseValueAt(2), runtime.constantPrimitiveValue(2)),
      true,
    );
    expect(
      identical(storage.denseValueAt(3), runtime.constantPrimitiveValue(3)),
      true,
    );
  });

  test('__index primitive results reuse the owner runtime cache', () async {
    final interpreter = Interpreter();
    final table = Value(<Object?, Object?>{}, interpreter: interpreter);
    table.setMetatable({'__index': (List<Object?> args) => 123});

    expect(
      identical(table['missing'], interpreter.constantPrimitiveValue(123)),
      true,
    );
    expect(
      identical(
        await table.getValueAsync('missing'),
        interpreter.constantPrimitiveValue(123),
      ),
      true,
    );
  });

  test('raw primitive table writes store the owner runtime cache', () {
    final interpreter = Interpreter();
    final storage = TableStorage();
    final table = Value(storage, interpreter: interpreter);

    table['field'] = 17;
    table[1] = true;

    expect(
      identical(storage['field'], interpreter.constantPrimitiveValue(17)),
      true,
    );
    expect(
      identical(
        storage.denseValueAt(1),
        interpreter.constantPrimitiveValue(true),
      ),
      true,
    );
  });

  test('map-style primitive writes store the owner runtime cache', () {
    final interpreter = Interpreter();
    final storage = TableStorage();
    final table = Value(storage, interpreter: interpreter);

    table.addAll({'a': 1, 'b': false});
    final inserted = table.putIfAbsent('c', () => 2);
    final updated = table.update('c', (_) => 3);
    table.updateAll((key, value) => key == 'a' ? 4 : value);

    expect(
      identical(storage['a'], interpreter.constantPrimitiveValue(4)),
      true,
    );
    expect(
      identical(storage['b'], interpreter.constantPrimitiveValue(false)),
      true,
    );
    expect(identical(inserted, interpreter.constantPrimitiveValue(2)), true);
    expect(identical(updated, interpreter.constantPrimitiveValue(3)), true);
    expect(
      identical(storage['c'], interpreter.constantPrimitiveValue(3)),
      true,
    );
  });

  test('map-style primitive reads reuse the owner runtime cache', () {
    final interpreter = Interpreter();
    final storage = TableStorage()
      ..['a'] = 1
      ..['b'] = false
      ..['c'] = 3;
    final table = Value(storage, interpreter: interpreter);

    final entry = table.entries.firstWhere((entry) => entry.key == 'a');
    expect(identical(entry.value, interpreter.constantPrimitiveValue(1)), true);

    final mapped = table.map<String, Object?>((key, value) {
      if (key == 'b') {
        expect(
          identical(value, interpreter.constantPrimitiveValue(false)),
          true,
        );
      }
      return MapEntry(key, value);
    });
    expect(identical(mapped['c'], interpreter.constantPrimitiveValue(3)), true);

    final removed = table.remove('a');
    expect(identical(removed, interpreter.constantPrimitiveValue(1)), true);
  });

  test('map-style addEntries and removeWhere use primitive cache', () {
    final interpreter = Interpreter();
    final storage = TableStorage();
    final table = Value(storage, interpreter: interpreter);

    table.addEntries([const MapEntry('a', 1), const MapEntry('b', false)]);
    expect(
      identical(storage['a'], interpreter.constantPrimitiveValue(1)),
      true,
    );
    expect(
      identical(storage['b'], interpreter.constantPrimitiveValue(false)),
      true,
    );

    table.removeWhere((key, value) {
      if (key == 'a') {
        expect(identical(value, interpreter.constantPrimitiveValue(1)), true);
      }
      return key == 'a';
    });
    expect(storage.containsKey('a'), false);
  });

  test('metamethod primitive key arguments reuse runtime cache', () async {
    final interpreter = Interpreter();
    final indexKeys = <Value>[];
    final newindexKeys = <Value>[];
    final table = Value(<Object?, Object?>{}, interpreter: interpreter);
    table.setMetatable({
      '__index': (List<Object?> args) {
        indexKeys.add(args[1] as Value);
        return null;
      },
      '__newindex': (List<Object?> args) {
        newindexKeys.add(args[1] as Value);
        return null;
      },
    });

    table[7];
    await table.getValueAsync(8);
    table[9] = true;
    await table.setValueAsync(10, false);

    expect(
      identical(indexKeys[0], interpreter.constantPrimitiveValue(7)),
      true,
    );
    expect(
      identical(indexKeys[1], interpreter.constantPrimitiveValue(8)),
      true,
    );
    expect(
      identical(newindexKeys[0], interpreter.constantPrimitiveValue(9)),
      true,
    );
    expect(
      identical(newindexKeys[1], interpreter.constantPrimitiveValue(10)),
      true,
    );
  });

  test('map-style metamethod primitive keys reuse runtime cache', () {
    final interpreter = Interpreter();
    final newindexKeys = <Value>[];
    final table = Value(<Object?, Object?>{
      11: 'value',
    }, interpreter: interpreter);
    table.setMetatable({
      '__newindex': (List<Object?> args) {
        newindexKeys.add(args[1] as Value);
        return null;
      },
    });

    table.clear();
    table.remove(12);

    expect(
      identical(newindexKeys[0], interpreter.constantPrimitiveValue(11)),
      true,
    );
    expect(
      identical(newindexKeys[1], interpreter.constantPrimitiveValue(12)),
      true,
    );
  });

  test('Value arithmetic avoids wrapping raw primitive operands', () {
    final interpreter = Interpreter();
    final left = Value(10, interpreter: interpreter);
    final shift = Value(0x0F, interpreter: interpreter);

    final sum = left + 5;
    final difference = left - 3;
    final product = left * 4;
    final quotient = left / 2;
    final remainder = left % 4;
    final floored = left ~/ 3;
    final shifted = shift << 4;
    final sharedPrimitiveSum = interpreter.constantPrimitiveValue(10) + 5;

    expect(identical(sum, interpreter.constantPrimitiveValue(15)), true);
    expect(identical(difference, interpreter.constantPrimitiveValue(7)), true);
    expect(identical(product, interpreter.constantPrimitiveValue(40)), true);
    expect(identical(quotient, interpreter.constantPrimitiveValue(5.0)), true);
    expect(identical(remainder, interpreter.constantPrimitiveValue(2)), true);
    expect(identical(floored, interpreter.constantPrimitiveValue(3)), true);
    expect(identical(shifted, interpreter.constantPrimitiveValue(0xF0)), true);
    expect(sharedPrimitiveSum.raw, 15);
  });

  test('Value logical operators reuse runtime caches for raw operands', () {
    final interpreter = Interpreter();
    final truthy = Value(true, interpreter: interpreter);
    final falsey = Value(false, interpreter: interpreter);
    final existing = Value('existing');

    final andResult = truthy.and(42);
    final orResult = falsey.or('fallback');
    final existingResult = falsey.or(existing);

    expect(identical(andResult, interpreter.constantPrimitiveValue(42)), true);
    expect(
      identical(orResult, interpreter.constantDartStringValue('fallback')),
      true,
    );
    expect(identical(existingResult, existing), true);
    expect(identical(existing.interpreter, interpreter), true);
    expect(identical(truthy.or(0), truthy), true);
    expect(identical(falsey.and(0), falsey), true);
  });

  test(
    'number metatable operators reuse runtime caches for raw right operands',
    () {
      final interpreter = Interpreter();
      MetaTable.initialize(interpreter);
      final numberMetatable = MetaTable().getTypeMetatable('number')!;
      final add = numberMetatable.metamethods['__add'] as dynamic;
      final eq = numberMetatable.metamethods['__eq'] as dynamic;
      final left = Value(10, interpreter: interpreter);

      final valueLeftSum = add([left, 5]);
      final rawLeftSum = add([10, 5]);
      final equalResult = eq([10, 10]);

      expect(
        identical(valueLeftSum, interpreter.constantPrimitiveValue(15)),
        true,
      );
      expect((rawLeftSum as Value).raw, 15);
      expect(
        identical(equalResult, interpreter.constantPrimitiveValue(true)),
        true,
      );
    },
  );

  test('Value concat reuses the runtime string cache', () {
    final interpreter = Interpreter();
    final left = Value(
      LuaString.fromDartString('hello '),
      interpreter: interpreter,
    );

    final result = left.concat('world');
    final cached = interpreter.constantStringValue(
      LuaString.fromDartString('hello world').bytes,
    );

    expect(identical(result, cached), true);
    expect((result.raw as LuaString).toString(), 'hello world');
  });

  test('Value concat keeps long runtime strings fresh', () {
    final interpreter = Interpreter();
    const prefix = '0123456789';
    const suffix = '0123456789012345678901234567890123456789';
    const combined = '$prefix$suffix';
    final left = Value(
      LuaString.fromDartString(prefix),
      interpreter: interpreter,
    );

    final result = left.concat(suffix);
    final cachedLiteral = interpreter.constantStringValue(
      LuaString.fromDartString(combined).bytes,
    );

    expect((result.raw as LuaString).toString(), combined);
    expect(identical(result, cachedLiteral), false);
    expect(identical(result.raw, cachedLiteral.raw), false);
  });
}
