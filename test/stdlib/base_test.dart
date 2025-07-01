import 'package:lualike/testing.dart';

void main() {
  group('Base Library', () {
    // Basic functions
    test('assert', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = assert(true, "This should not be shown")
        local b = assert(1, "This should not be shown")
        local c = assert("string", "This should not be shown")
        local d, e = assert(true, "message", "extra")
      ''');

      expect((bridge.getGlobal('a') as Value).raw, isNotNull);
      expect((bridge.getGlobal('b') as Value).raw, isNotNull);
      expect((bridge.getGlobal('c') as Value).raw, isNotNull);
      expect((bridge.getGlobal('d') as Value).raw, isNotNull);

      // Test error cases separately
      bool assertFailed = false;
      try {
        await bridge.runCode('assert(false, "custom message")');
      } catch (e) {
        assertFailed = true;
        expect(e.toString(), contains("custom message"));
      }
      expect(assertFailed, isTrue);

      assertFailed = false;
      try {
        await bridge.runCode('assert(nil)');
      } catch (e) {
        assertFailed = true;
        expect(e.toString(), contains("assertion failed"));
      }
      expect(assertFailed, isTrue);
    });

    test('collectgarbage', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Basic functionality tests
        local isRunning = collectgarbage("isrunning")
        collectgarbage("collect")
        local mem = collectgarbage("count")
        collectgarbage("stop")
        collectgarbage("restart")
        local step = collectgarbage("step", 1)
      ''');

      expect((bridge.getGlobal('isRunning') as Value).raw, equals(true));
      expect((bridge.getGlobal('mem') as Value).raw, isA<num>());
      expect((bridge.getGlobal('step') as Value).raw, equals(true));
    });

    test('collectgarbage - comprehensive', () async {
      final bridge = LuaLike();

      // Test all collectgarbage options
      await bridge.runCode('''
        -- Test default behavior (collect)
        collectgarbage()

        -- Test explicit collect
        collectgarbage("collect")

        -- Test count and verify return format
        local count, step = collectgarbage("count")
        assert(type(count) == "number")
        assert(type(step) == "number")

        -- Test stop/restart
        collectgarbage("stop")
        local running1 = collectgarbage("isrunning")
        assert(running1 == false)

        collectgarbage("restart")
        local running2 = collectgarbage("isrunning")
        assert(running2 == true)

        -- Test step
        local cycleComplete = collectgarbage("step", 0)  -- basic step
        assert(type(cycleComplete) == "boolean")

        local cycleComplete2 = collectgarbage("step", 100)  -- step with KB
        assert(type(cycleComplete2) == "boolean")

        -- Test incremental mode
        collectgarbage("incremental", 100, 200, 50)  -- pause, stepmul, stepsize

        -- Test generational mode
        collectgarbage("generational", 50, 100)  -- minor mul, major mul
      ''');

      Logger.setEnabled(false);
    });

    test('error', () async {
      final bridge = LuaLike();

      // Test error cases separately
      bool errorThrown = false;
      try {
        await bridge.runCode('error("test error")');
      } catch (e) {
        errorThrown = true;
        expect(e.toString(), contains("test error"));
      }
      expect(errorThrown, isTrue);

      errorThrown = false;
      try {
        await bridge.runCode('error("level 0 error", 0)');
      } catch (e) {
        errorThrown = true;
        expect(e.toString(), contains("level 0 error"));
      }
      expect(errorThrown, isTrue);
    });

    test('_G global variable', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test that _G is the global environment
        _G.newVar = "global variable"
        local isGlobalTable = type(_G) == "table"
        local hasG = _G ~= nil
      ''');

      // Test that we can access the global variable
      await bridge.runCode('''
        local canAccessGlobal = newVar == "global variable"
      ''');

      expect((bridge.getGlobal('isGlobalTable') as Value).raw, isTrue);
      expect((bridge.getGlobal('hasG') as Value).raw, isTrue);
      expect((bridge.getGlobal('canAccessGlobal') as Value).raw, isTrue);
      expect(
        (bridge.getGlobal('newVar') as Value).raw,
        equals("global variable"),
      );
    });

    test('getmetatable and setmetatable', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local t = {}
        local mt = {__index = {value = 10}}

        -- Set metatable
        local result = setmetatable(t, mt)
        local hasMt = getmetatable(t) ~= nil

        -- Test nil case
        local nilMt = getmetatable(123) == nil
      ''');

      expect((bridge.getGlobal('result') as Value).raw, isA<Map>());
      expect((bridge.getGlobal('hasMt') as Value).raw, isTrue);
      expect((bridge.getGlobal('nilMt') as Value).raw, isFalse);

      // Test __metatable field separately
      await bridge.runCode('''
        local t2 = {}
        setmetatable(t2, {__metatable = "protected"})
        local protectedMt = getmetatable(t2)
      ''');

      expect(
        (bridge.getGlobal('protectedMt') as Value).raw,
        equals("protected"),
      );
    });

    test('print', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Basic print functionality
        print("Hello", "World")
        print(123, true, nil)
      ''');

      // We can't easily test the output, but at least we can verify it doesn't throw errors
    });

    test('type', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local types = {
          nil_type = type(nil),
          number_type = type(123),
          string_type = type("hello"),
          boolean_type = type(true),
          table_type = type({}),
          function_type = type(function() end)
        }
      ''');

      final types = (bridge.getGlobal('types') as Value).raw as Map;
      expect((types['nil_type'] as Value).raw, equals("nil"));
      expect((types['number_type'] as Value).raw, equals("number"));
      expect((types['string_type'] as Value).raw, equals("string"));
      expect((types['boolean_type'] as Value).raw, equals("boolean"));
      expect((types['table_type'] as Value).raw, equals("table"));
      expect((types['function_type'] as Value).raw, equals("function"));
    });

    test('_VERSION', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local version = _VERSION
        local isString = type(version) == "string"
      ''');

      expect((bridge.getGlobal('isString') as Value).raw, equals(true));
      expect(
        (bridge.getGlobal('version') as Value).raw.toString(),
        contains("LuaLike"),
      );
    });

    test('warn', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Basic warning
        warn("This is a warning")

        -- Multiple arguments
        warn("Warning", "with", "multiple", "parts")
      ''');

      // We can't easily test the output, but at least we can verify it doesn't throw errors
    });

    test('tostring', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test basic conversion
        local s1 = tostring(123)
        local s3 = tostring(nil)
      ''');

      expect((bridge.getGlobal('s1') as Value).raw, equals("123"));
      expect((bridge.getGlobal('s3') as Value).raw, equals("nil"));
    });

    test('tonumber', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test basic conversion
        local n1 = tonumber("123")
        local n2 = tonumber("123.45")
        local n3 = tonumber("-123.45")

        -- Test with base
        local hex = tonumber("FF", 16)
        local bin = tonumber("1010", 2)
        local oct = tonumber("70", 8)

        -- Test invalid conversions
        local invalid1 = tonumber("not a number")
        local invalid2 = tonumber("FF") -- without base 16
      ''');

      expect((bridge.getGlobal('n1') as Value).raw, equals(123));
      expect((bridge.getGlobal('n2') as Value).raw, equals(123.45));
      expect((bridge.getGlobal('n3') as Value).raw, equals(-123.45));
      expect((bridge.getGlobal('hex') as Value).raw, equals(255));
      expect((bridge.getGlobal('bin') as Value).raw, equals(10));
      expect((bridge.getGlobal('oct') as Value).raw, equals(56));
      expect((bridge.getGlobal('invalid1') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid2') as Value).raw, isNull);
    });

    test('select', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test select with index
        local a, b, c = select(2, "a", "b", "c", "d")

        -- Test select with "#"
        local count = select("#", "a", "b", "c", "d")
      ''');

      // Note: Due to how multiple return values are handled, we can't easily test
      // the individual values a, b, c. But we can test the count.
      expect((bridge.getGlobal('count') as Value).raw, equals(4));
    });

    test('rawequal', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test rawequal
        local t1 = {}
        local t2 = {}
        local sameTable = t1
        local eq1 = rawequal(t1, t1)
        local eq2 = rawequal(t1, t2)
        local eq3 = rawequal(t1, sameTable)
      ''');

      expect((bridge.getGlobal('eq1') as Value).raw, isTrue);
      expect((bridge.getGlobal('eq2') as Value).raw, isFalse);
      expect((bridge.getGlobal('eq3') as Value).raw, isTrue);
    });

    test('rawget and rawset', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test rawget and rawset
        local t = {}

        -- Set a value using rawset
        rawset(t, "key", "value")

        -- Get the value using rawget
        local rawGetResult = rawget(t, "key")
      ''');

      expect((bridge.getGlobal('rawGetResult') as Value).raw, equals("value"));
    });

    test('rawlen', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test rawlen
        local str = "hello"
        local arr = {1, 2, 3, 4, 5}
        local strLen = rawlen(str)
        local arrLen = rawlen(arr)
      ''');

      expect((bridge.getGlobal('strLen') as Value).raw, equals(5));
      expect((bridge.getGlobal('arrLen') as Value).raw, equals(5));
    });

    test('next', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test next function
        local t = {a = 1, b = 2, c = 3}
        local keys = {}
        local values = {}

        -- Get first key-value pair
        local k, v = next(t)
        keys[1] = k
        values[1] = v

        -- Get next key-value pair
        local k2, v2 = next(t, k)
        keys[2] = k2
        values[2] = v2

        -- Test empty table
        local isEmpty = next({}) == nil
      ''');

      // We can't predict the exact order of keys, but we can check that we got some values
      final keys = (bridge.getGlobal('keys') as Value).raw as Map;
      final values = (bridge.getGlobal('values') as Value).raw as Map;

      expect(keys.length, equals(2));
      expect(values.length, equals(2));
      expect((bridge.getGlobal('isEmpty') as Value).raw, isTrue);
    });

    test('pairs', () async {
      // Enable logging for debugging

      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test pairs function with a regular table
        local t = {a = 1, b = 2, c = 3}
        local count = 0

        -- Use pairs to iterate over the table
        for k, v in pairs(t) do
          count = count + 1
        end

        -- Test pairs with empty table
        local emptyCount = 0
        for k, v in pairs({}) do
          emptyCount = emptyCount + 1
        end

        -- Test pairs with table containing nil values
        local nilTable = {}
        nilTable.a = 1
        nilTable.b = nil
        nilTable.c = 3

        -- Debug: Print the table contents
        print("nilTable contents:")
        for k, v in pairs(nilTable) do
          print(k, v)
        end

        -- Count keys directly
        local directCount = 0
        if nilTable.a ~= nil then directCount = directCount + 1 end
        if nilTable.b ~= nil then directCount = directCount + 1 end
        if nilTable.c ~= nil then directCount = directCount + 1 end
        print("directCount:", directCount)

        -- Count keys using pairs
        local nilCount = 0
        for k, v in pairs(nilTable) do
          nilCount = nilCount + 1
        end
        print("nilCount:", nilCount)
      ''');

      // Disable logging after test
      Logger.setEnabled(false);

      // Verify the results
      expect((bridge.getGlobal('count') as Value).raw, equals(3));
      expect((bridge.getGlobal('emptyCount') as Value).raw, equals(0));
      expect(
        (bridge.getGlobal('directCount') as Value).raw,
        equals(2),
      ); // Only a and c, not b
      expect(
        (bridge.getGlobal('nilCount') as Value).raw,
        equals(2),
      ); // Should match directCount
    });

    test('ipairs', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        -- Test ipairs function with a regular array
        local t = {"a", "b", "c", "d"}
        t[10] = "j" -- sparse array - should be ignored by ipairs

        local count = 0

        -- Use ipairs to iterate over the array
        for i, v in ipairs(t) do
          count = count + 1
        end

        -- Test ipairs with empty table
        local emptyCount = 0
        for i, v in ipairs({}) do
          emptyCount = emptyCount + 1
        end

        -- Test ipairs with a table that has holes
        local holeyTable = {}
        holeyTable[1] = "one"
        holeyTable[3] = "three"
        holeyTable[5] = "five"
        local holeyCount = 0
        for i, v in ipairs(holeyTable) do
          holeyCount = holeyCount + 1
        end
      ''');

      // Verify the results
      expect((bridge.getGlobal('count') as Value).raw, equals(4));
      expect((bridge.getGlobal('emptyCount') as Value).raw, equals(0));
      expect(
        (bridge.getGlobal('holeyCount') as Value).raw,
        equals(1),
      ); // Only index 1, stops at first hole
    });

    test('pcall', () async {
      final bridge = LuaLike();

      // Test successful call
      await bridge.runCode('''
        -- Test successful call
        local status, result = pcall(function() return "success" end)

        -- Test error call
        local errorStatus, errorMsg = pcall(function() error("test error") end)

        -- Test with arguments
        local argStatus, argResult = pcall(function(x, y) return x + y end, 10, 20)
      ''');

      expect((bridge.getGlobal('status') as Value).raw, equals(true));
      expect((bridge.getGlobal('result') as Value).raw, equals("success"));

      expect((bridge.getGlobal('errorStatus') as Value).raw, equals(false));
      expect(
        (bridge.getGlobal('errorMsg') as Value).raw.toString(),
        contains("test error"),
      );

      expect((bridge.getGlobal('argStatus') as Value).raw, equals(true));
      expect((bridge.getGlobal('argResult') as Value).raw, equals(30));
    });

    test('xpcall', () async {
      final bridge = LuaLike();

      // Test successful call
      await bridge.runCode('''
        -- Test successful call
        local status, result = xpcall(
          function() return "success" end,
          function(err) return "Handler: " .. err end
        )

        -- Test error call
        local errorStatus, errorMsg = xpcall(
          function() error("test error") end,
          function(err) return "Handled: " .. err end
        )

        -- Test with arguments
        local argStatus, argResult = xpcall(
          function(x, y) return x + y end,
          function(err) return "Error in addition: " .. err end,
          10, 20
        )
      ''');

      expect((bridge.getGlobal('status') as Value).raw, equals(true));
      expect((bridge.getGlobal('result') as Value).raw, equals("success"));

      expect((bridge.getGlobal('errorStatus') as Value).raw, equals(false));
      expect(
        (bridge.getGlobal('errorMsg') as Value).raw.toString(),
        contains("Handled: "),
      );
      expect(
        (bridge.getGlobal('errorMsg') as Value).raw.toString(),
        contains("test error"),
      );

      expect((bridge.getGlobal('argStatus') as Value).raw, equals(true));
      expect((bridge.getGlobal('argResult') as Value).raw, equals(30));
    });
  });
}
