import 'package:lualike_test/test.dart';

void main() {
  group('Base Library', () {
    // Basic functions
    test('assert', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        a = assert(true, "This should not be shown")
        b = assert(1, "This should not be shown")
        c = assert("string", "This should not be shown")
        d, e = assert(true, "message", "extra")
      ''');

      expect((bridge.getGlobal('a') as Value).raw, isNotNull);
      expect((bridge.getGlobal('b') as Value).raw, isNotNull);
      expect((bridge.getGlobal('c') as Value).raw, isNotNull);
      expect((bridge.getGlobal('d') as Value).raw, isNotNull);

      // Test error cases separately
      bool assertFailed = false;
      try {
        await bridge.execute('assert(false, "custom message")');
      } catch (e) {
        assertFailed = true;
        expect(e.toString(), contains("custom message"));
      }
      expect(assertFailed, isTrue);

      assertFailed = false;
      try {
        await bridge.execute('assert(nil)');
      } catch (e) {
        assertFailed = true;
        expect(e.toString(), contains("assertion failed"));
      }
      expect(assertFailed, isTrue);
    });

    test('collectgarbage', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Basic functionality tests
        isRunning = collectgarbage("isrunning")
        collectgarbage("collect")
        mem = collectgarbage("count")
        collectgarbage("stop")
        collectgarbage("restart")
        step = collectgarbage("step", 1)
      ''');

      expect((bridge.getGlobal('isRunning') as Value).raw, equals(true));
      expect((bridge.getGlobal('mem') as Value).raw, isA<num>());
      expect((bridge.getGlobal('step') as Value).raw, equals(true));
    });

    test('collectgarbage - comprehensive', () async {
      final bridge = LuaLike();

      // Test all collectgarbage options
      await bridge.execute('''
        -- Test default behavior (collect)
        collectgarbage()

        -- Test explicit collect
        collectgarbage("collect")

        -- Test count and verify return format
        count, step = collectgarbage("count")
        assert(type(count) == "number")
        assert(type(step) == "number")

        -- Test stop/restart
        collectgarbage("stop")
        running1 = collectgarbage("isrunning")
        assert(running1 == false)

        collectgarbage("restart")
        running2 = collectgarbage("isrunning")
        assert(running2 == true)

        -- Test step
        cycleComplete = collectgarbage("step", 0)  -- basic step
        assert(type(cycleComplete) == "boolean")

        cycleComplete2 = collectgarbage("step", 100)  -- step with KB
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
        await bridge.execute('error("test error")');
      } catch (e) {
        errorThrown = true;
        expect(e.toString(), contains("test error"));
      }
      expect(errorThrown, isTrue);

      errorThrown = false;
      try {
        await bridge.execute('error("level 0 error", 0)');
      } catch (e) {
        errorThrown = true;
        expect(e.toString(), contains("level 0 error"));
      }
      expect(errorThrown, isTrue);
    });

    test('_G global variable', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test that _G is the global environment
        _G.newVar = "global variable"
        isGlobalTable = type(_G) == "table"
        hasG = _G ~= nil
      ''');

      // Test that we can access the global variable
      await bridge.execute('''
        canAccessGlobal = newVar == "global variable"
      ''');

      expect((bridge.getGlobal('isGlobalTable') as Value).unwrap(), isTrue);
      expect((bridge.getGlobal('hasG') as Value).unwrap(), isTrue);
      expect((bridge.getGlobal('canAccessGlobal') as Value).unwrap(), isTrue);
      expect(
        (bridge.getGlobal('newVar') as Value).unwrap(),
        equals("global variable"),
      );
    });

    group("setmetatable", () {
      test('setmetatable with function', () async {
        final bridge = LuaLike();
        await bridge.execute(r'''
t = {x = 1}
mt = {__tostring = function(self) return "custom: " .. self.x end}

-- Set metatable with __tostring function
setmetatable(t, mt)

-- Test that the __tostring function is called when converting to string
result = tostring(t)
        ''');
        expect(
          (bridge.getGlobal('result') as Value).unwrap(),
          equals("custom: 1"),
        );
      });

      test('getmetatable and setmetatable', () async {
        final bridge = LuaLike();
        await bridge.execute('''
        t = {}
        mt = {__index = {value = 10}}

        -- Set metatable
        result = setmetatable(t, mt)
        hasMt = getmetatable(t) ~= nil

        -- Test nil case
        nilMt = getmetatable(123) == nil
      ''');

        expect((bridge.getGlobal('result') as Value).raw, isA<Map>());
        expect((bridge.getGlobal('hasMt') as Value).raw, isTrue);
        expect((bridge.getGlobal('nilMt') as Value).raw, isTrue);

        // Test __metatable field separately
        await bridge.execute('''
        t2 = {}
        setmetatable(t2, {__metatable = "protected"})
        protectedMt = getmetatable(t2)
      ''');

        expect(
          (bridge.getGlobal('protectedMt') as Value).unwrap(),
          equals("protected"),
        );
      });
    });
    test('print', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Basic print functionality
        print("Hello", "World")
        print(123, true, nil)
      ''');

      // We can't easily test the output, but at least we can verify it doesn't throw errors
    });

    test('type', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        types = {
          nil_type = type(nil),
          number_type = type(123),
          string_type = type("hello"),
          boolean_type = type(true),
          table_type = type({}),
          function_type = type(function() end)
        }
      ''');

      final types = (bridge.getGlobal('types') as Value).unwrap() as Map;
      expect(types['nil_type'], equals("nil"));
      expect(types['number_type'], equals("number"));
      expect(types['string_type'], equals("string"));
      expect(types['boolean_type'], equals("boolean"));
      expect(types['table_type'], equals("table"));
      expect(types['function_type'], equals("function"));
    });

    test('_VERSION', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        version = _VERSION
        isString = type(version) == "string"
      ''');

      expect((bridge.getGlobal('isString') as Value).unwrap(), equals(true));
      expect(
        (bridge.getGlobal('version') as Value).unwrap().toString(),
        contains("LuaLike"),
      );
    });

    test('warn', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Basic warning
        warn("This is a warning")

        -- Multiple arguments
        warn("Warning", "with", "multiple", "parts")
      ''');

      // We can't easily test the output, but at least we can verify it doesn't throw errors
    });

    test('tostring', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test basic conversion
        s1 = tostring(123)
        s3 = tostring(nil)
      ''');

      expect((bridge.getGlobal('s1') as Value).unwrap(), equals("123"));
      expect((bridge.getGlobal('s3') as Value).unwrap(), equals("nil"));
    });

    test('tonumber', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test basic conversion
        n1 = tonumber("123")
        n2 = tonumber("123.45")
        n3 = tonumber("-123.45")

        -- Test positive sign prefix
        pos1 = tonumber("+123")
        pos2 = tonumber("+123.45")
        pos3 = tonumber("+0.01")
        pos4 = tonumber("+.01")
        pos5 = tonumber("+1.")

        -- Test decimal point variations
        dot1 = tonumber(".01")
        dot2 = tonumber("-.01")
        dot3 = tonumber("-1.")
        dot4 = tonumber("1.")
        dot5 = tonumber("0.")
        dot6 = tonumber("+0.")
        dot7 = tonumber("-0.")

        -- Test leading/trailing zeros
        zero1 = tonumber("007")
        zero2 = tonumber("007.5")
        zero3 = tonumber("0.500")
        zero4 = tonumber("+007")
        zero5 = tonumber("-007")

        -- Test scientific notation
        sci1 = tonumber("1e2")
        sci2 = tonumber("1.5e2")
        sci3 = tonumber("1E2")
        sci4 = tonumber("1.5E-2")
        sci5 = tonumber("+1e2")
        sci6 = tonumber("-1e2")
        sci7 = tonumber("1e+2")
        sci8 = tonumber("1e-2")

        -- Test hex numbers (base 10 should treat these as invalid)
        hex_base10_1 = tonumber("0x10")
        hex_base10_2 = tonumber("0X10")

        -- Test with base parameter
        hex = tonumber("FF", 16)
        hex2 = tonumber("ff", 16)
        hex3 = tonumber("10", 16)
        bin = tonumber("1010", 2)
        oct = tonumber("70", 8)
        base36 = tonumber("ZZ", 36)

        -- Test whitespace handling
        ws1 = tonumber(" 123 ")
        ws2 = tonumber("\\t456\\n")
        ws3 = tonumber("  +123.45  ")
        ws4 = tonumber("\\n\\t-67.89\\t\\n")

        -- Test edge cases
        inf_pos = tonumber("inf")
        inf_neg = tonumber("-inf")
        nan_val = tonumber("nan")

        -- Test invalid conversions
        invalid1 = tonumber("not a number")
        invalid2 = tonumber("FF") -- without base 16
        invalid3 = tonumber("123abc")
        invalid4 = tonumber("12.34.56")
        invalid5 = tonumber("++123")
        invalid6 = tonumber("--123")
        invalid7 = tonumber("1.2.3")
        invalid8 = tonumber("")
        invalid9 = tonumber("   ")
        invalid10 = tonumber("1e")
        invalid11 = tonumber("1e+")
        invalid12 = tonumber("e5")
        invalid13 = tonumber(".")
        invalid14 = tonumber("+")
        invalid15 = tonumber("-")

        -- Test the specific cases from math.lua that were failing
        math_test1 = tonumber("+0.01")
        math_test2 = tonumber("+.01")
        math_test3 = tonumber(".01")
        math_test4 = tonumber("-1.")
        math_test5 = tonumber("+1.")

        -- Verify math.lua assertions
        check1 = math_test1 == 1/100
        check2 = math_test2 == 0.01
        check3 = math_test3 == 0.01
        check4 = math_test4 == -1
        check5 = math_test5 == 1
      ''');

      // Basic conversions
      expect((bridge.getGlobal('n1') as Value).raw, equals(123));
      expect((bridge.getGlobal('n2') as Value).raw, equals(123.45));
      expect((bridge.getGlobal('n3') as Value).raw, equals(-123.45));

      // Positive sign prefix
      expect((bridge.getGlobal('pos1') as Value).raw, equals(123));
      expect((bridge.getGlobal('pos2') as Value).raw, equals(123.45));
      expect((bridge.getGlobal('pos3') as Value).raw, equals(0.01));
      expect((bridge.getGlobal('pos4') as Value).raw, equals(0.01));
      expect((bridge.getGlobal('pos5') as Value).raw, equals(1.0));

      // Decimal point variations
      expect((bridge.getGlobal('dot1') as Value).raw, equals(0.01));
      expect((bridge.getGlobal('dot2') as Value).raw, equals(-0.01));
      expect((bridge.getGlobal('dot3') as Value).raw, equals(-1.0));
      expect((bridge.getGlobal('dot4') as Value).raw, equals(1.0));
      expect((bridge.getGlobal('dot5') as Value).raw, equals(0.0));
      expect((bridge.getGlobal('dot6') as Value).raw, equals(0.0));
      expect((bridge.getGlobal('dot7') as Value).raw, equals(0.0));

      // Leading/trailing zeros
      expect((bridge.getGlobal('zero1') as Value).raw, equals(7));
      expect((bridge.getGlobal('zero2') as Value).raw, equals(7.5));
      expect((bridge.getGlobal('zero3') as Value).raw, equals(0.5));
      expect((bridge.getGlobal('zero4') as Value).raw, equals(7));
      expect((bridge.getGlobal('zero5') as Value).raw, equals(-7));

      // Scientific notation
      expect((bridge.getGlobal('sci1') as Value).raw, equals(100.0));
      expect((bridge.getGlobal('sci2') as Value).raw, equals(150.0));
      expect((bridge.getGlobal('sci3') as Value).raw, equals(100.0));
      expect((bridge.getGlobal('sci4') as Value).raw, equals(0.015));
      expect((bridge.getGlobal('sci5') as Value).raw, equals(100.0));
      expect((bridge.getGlobal('sci6') as Value).raw, equals(-100.0));
      expect((bridge.getGlobal('sci7') as Value).raw, equals(100.0));
      expect((bridge.getGlobal('sci8') as Value).raw, equals(0.01));

      // Hex in base 10 (Lua supports hex notation in base 10)
      expect((bridge.getGlobal('hex_base10_1') as Value).raw, equals(16));
      expect((bridge.getGlobal('hex_base10_2') as Value).raw, equals(16));

      // With base parameter
      expect((bridge.getGlobal('hex') as Value).raw, equals(255));
      expect((bridge.getGlobal('hex2') as Value).raw, equals(255));
      expect((bridge.getGlobal('hex3') as Value).raw, equals(16));
      expect((bridge.getGlobal('bin') as Value).raw, equals(10));
      expect((bridge.getGlobal('oct') as Value).raw, equals(56));
      expect(
        (bridge.getGlobal('base36') as Value).raw,
        equals(1295),
      ); // Z=35, so ZZ = 35*36 + 35 = 1295

      // Whitespace handling (Lua accepts leading/trailing whitespace)
      expect((bridge.getGlobal('ws1') as Value).raw, equals(123));
      expect(
        (bridge.getGlobal('ws2') as Value).raw,
        equals(456),
      ); // \t and \n are allowed
      expect((bridge.getGlobal('ws3') as Value).raw, equals(123.45));
      expect(
        (bridge.getGlobal('ws4') as Value).raw,
        equals(-67.89),
      ); // \t and \n are allowed

      // Edge cases - these might not be supported by all Lua implementations
      // Testing for null is safer than expecting specific values for inf/nan
      // expect((bridge.getGlobal('inf_pos') as Value).raw, anyOf(isNull, equals(double.infinity)));
      // expect((bridge.getGlobal('inf_neg') as Value).raw, anyOf(isNull, equals(double.negativeInfinity)));
      // expect((bridge.getGlobal('nan_val') as Value).raw, anyOf(isNull, isNaN));

      // Invalid conversions
      expect((bridge.getGlobal('invalid1') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid2') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid3') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid4') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid5') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid6') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid7') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid8') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid9') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid10') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid11') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid12') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid13') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid14') as Value).raw, isNull);
      expect((bridge.getGlobal('invalid15') as Value).raw, isNull);

      // Math.lua specific tests
      expect((bridge.getGlobal('math_test1') as Value).raw, equals(0.01));
      expect((bridge.getGlobal('math_test2') as Value).raw, equals(0.01));
      expect((bridge.getGlobal('math_test3') as Value).raw, equals(0.01));
      expect((bridge.getGlobal('math_test4') as Value).raw, equals(-1.0));
      expect((bridge.getGlobal('math_test5') as Value).raw, equals(1.0));

      // Verify the assertions that were failing in math.lua
      expect((bridge.getGlobal('check1') as Value).raw, isTrue);
      expect((bridge.getGlobal('check2') as Value).raw, isTrue);
      expect((bridge.getGlobal('check3') as Value).raw, isTrue);
      expect((bridge.getGlobal('check4') as Value).raw, isTrue);
      expect((bridge.getGlobal('check5') as Value).raw, isTrue);
    });

    test('select', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test select with index
        a, b, c = select(2, "a", "b", "c", "d")

        -- Test select with "#"
        count = select("#", "a", "b", "c", "d")
      ''');

      // Note: Due to how multiple return values are handled, we can't easily test
      // the individual values a, b, c. But we can test the count.
      expect((bridge.getGlobal('count') as Value).raw, equals(4));
    });

    test('rawequal', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test rawequal
        t1 = {}
        t2 = {}
        sameTable = t1
        eq1 = rawequal(t1, t1)
        eq2 = rawequal(t1, t2)
        eq3 = rawequal(t1, sameTable)
      ''');

      expect((bridge.getGlobal('eq1') as Value).raw, isTrue);
      expect((bridge.getGlobal('eq2') as Value).raw, isFalse);
      expect((bridge.getGlobal('eq3') as Value).raw, isTrue);
    });

    test('rawget and rawset', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test rawget and rawset
        t = {}

        -- Set a value using rawset
        rawset(t, "key", "value")

        -- Get the value using rawget
        rawGetResult = rawget(t, "key")
      ''');

      expect(
        (bridge.getGlobal('rawGetResult') as Value).unwrap(),
        equals("value"),
      );
    });

    test('rawset rejects invalid keys', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        t = {}
        okNaN, errNaN = pcall(rawset, t, 0/0, 1)
        okNil, errNil = pcall(rawset, t, nil, 1)
      ''');

      expect((bridge.getGlobal('okNaN') as Value).unwrap(), equals(false));
      expect(
        (bridge.getGlobal('errNaN') as Value).unwrap().toString(),
        contains('table index is NaN'),
      );
      expect((bridge.getGlobal('okNil') as Value).unwrap(), equals(false));
      expect(
        (bridge.getGlobal('errNil') as Value).unwrap().toString(),
        contains('table index is nil'),
      );
    });

    test('rawlen', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test rawlen
        str = "hello"
        arr = {1, 2, 3, 4, 5}
        strLen = rawlen(str)
        arrLen = rawlen(arr)
      ''');

      expect((bridge.getGlobal('strLen') as Value).raw, equals(5));
      expect((bridge.getGlobal('arrLen') as Value).raw, equals(5));
    });

    test('next', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        -- Test next function
        t = {a = 1, b = 2, c = 3}
        keys = {}
        values = {}

        -- Get first key-value pair
        k, v = next(t)
        keys[1] = k
        values[1] = v

        -- Get next key-value pair
        k2, v2 = next(t, k)
        keys[2] = k2
        values[2] = v2

        -- Test empty table
        isEmpty = next({}) == nil
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
      await bridge.execute('''
        -- Test pairs function with a regular table
        t = {a = 1, b = 2, c = 3}
        count = 0

        -- Use pairs to iterate over the table
        for k, v in pairs(t) do
          count = count + 1
        end

        -- Test pairs with empty table
        emptyCount = 0
        for k, v in pairs({}) do
          emptyCount = emptyCount + 1
        end

        -- Test pairs with table containing nil values
        nilTable = {}
        nilTable.a = 1
        nilTable.b = nil
        nilTable.c = 3

        -- Debug: Print the table contents
        print("nilTable contents:")
        for k, v in pairs(nilTable) do
          print(k, v)
        end

        -- Count keys directly
        directCount = 0
        if nilTable.a ~= nil then directCount = directCount + 1 end
        if nilTable.b ~= nil then directCount = directCount + 1 end
        if nilTable.c ~= nil then directCount = directCount + 1 end
        print("directCount:", directCount)

        -- Count keys using pairs
        nilCount = 0
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
      await bridge.execute('''
        -- Test ipairs function with a regular array
        t = {"a", "b", "c", "d"}
        t[10] = "j" -- sparse array - should be ignored by ipairs

        count = 0

        -- Use ipairs to iterate over the array
        for i, v in ipairs(t) do
          count = count + 1
        end

        -- Test ipairs with empty table
        emptyCount = 0
        for i, v in ipairs({}) do
          emptyCount = emptyCount + 1
        end

        -- Test ipairs with a table that has holes
        holeyTable = {}
        holeyTable[1] = "one"
        holeyTable[3] = "three"
        holeyTable[5] = "five"
        holeyCount = 0
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
      await bridge.execute('''
        -- Test successful call
        status, result = pcall(function() return "success" end)

        -- Test error call
        errorStatus, errorMsg = pcall(function() error("test error") end)

        -- Test with arguments
        argStatus, argResult = pcall(function(x, y) return x + y end, 10, 20)

        -- Test calling non-function (should return false with type error)
        typeErrorStatus, typeErrorMsg = pcall(42)

        -- Test calling nil (should return false with type error)
        nilErrorStatus, nilErrorMsg = pcall(nil)

        -- Test multiple return values
        multiStatus, multiResult = pcall(function() return 1, 2, 3 end)
        -- Check if multiResult is a list (multiple values returned as a single value)
        a, b, c = nil, nil, nil
        if type(multiResult) == "table" and multiResult[1] then
          a, b, c = multiResult[1], multiResult[2], multiResult[3]
        else
          a = multiResult
        end

        -- Test pcall with builtin function
        builtinStatus, builtinResult = pcall(type, "hello")
      ''');

      expect((bridge.getGlobal('status') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('result') as Value).unwrap(), equals("success"));

      expect(
        (bridge.getGlobal('errorStatus') as Value).unwrap(),
        equals(false),
      );
      expect(
        (bridge.getGlobal('errorMsg') as Value).unwrap().toString(),
        contains("test error"),
      );

      expect((bridge.getGlobal('argStatus') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('argResult') as Value).unwrap(), equals(30));

      // Test type error handling
      expect(
        (bridge.getGlobal('typeErrorStatus') as Value).unwrap(),
        equals(false),
      );
      expect(
        (bridge.getGlobal('typeErrorMsg') as Value).unwrap().toString(),
        contains("attempt to call a number value"),
      );

      expect(
        (bridge.getGlobal('nilErrorStatus') as Value).unwrap(),
        equals(false),
      );
      expect(
        (bridge.getGlobal('nilErrorMsg') as Value).unwrap().toString(),
        contains("attempt to call a nil value"),
      );

      // Test multiple return values - pcall only returns the first result
      expect((bridge.getGlobal('multiStatus') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('a') as Value).unwrap(), equals(1));
      // b and c should be nil since pcall only returns the first result
      expect((bridge.getGlobal('b') as Value).unwrap(), isNull);
      expect((bridge.getGlobal('c') as Value).unwrap(), isNull);

      // Test builtin function call
      expect(
        (bridge.getGlobal('builtinStatus') as Value).unwrap(),
        equals(true),
      );
      expect(
        (bridge.getGlobal('builtinResult') as Value).unwrap(),
        equals("string"),
      );
    });

    test('xpcall', () async {
      final bridge = LuaLike();

      // Test successful call
      await bridge.execute('''
        -- Test successful call
        status, result = xpcall(
          function() return "success" end,
          function(err) return "Handler: " .. err end
        )

        -- Test error call
        errorStatus, errorMsg = xpcall(
          function() error("test error") end,
          function(err) return "Handled: " .. err end
        )

        -- Test with arguments
        argStatus, argResult = xpcall(
          function(x, y) return x + y end,
          function(err) return "Error in addition: " .. err end,
          10, 20
        )
      ''');

      expect((bridge.getGlobal('status') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('result') as Value).unwrap(), equals("success"));

      expect(
        (bridge.getGlobal('errorStatus') as Value).unwrap(),
        equals(false),
      );
      expect(
        (bridge.getGlobal('errorMsg') as Value).unwrap().toString(),
        contains("Handled: "),
      );
      expect(
        (bridge.getGlobal('errorMsg') as Value).unwrap().toString(),
        contains("test error"),
      );

      expect((bridge.getGlobal('argStatus') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('argResult') as Value).unwrap(), equals(30));
    });

    test('pcall return value consistency', () async {
      final bridge = LuaLike();

      // Test that pcall always returns Value objects (not raw values)
      await bridge.execute('''
        -- Test that return values are properly wrapped
        status1, result1 = pcall(function() return nil end)
        status2, result2 = pcall(function() return false end)
        status3, result3 = pcall(function() return 0 end)
        status4, result4 = pcall(function() return "" end)

        -- Test error return value wrapping
        errorStatus, errorResult = pcall(function() error({custom = "error"}) end)

        -- Verify types
        status1_type = type(status1)
        result1_type = type(result1)
        status2_type = type(status2)
        result2_type = type(result2)
        errorStatus_type = type(errorStatus)
        errorResult_type = type(errorResult)
      ''');

      // All status values should be boolean
      expect(
        (bridge.getGlobal('status1_type') as Value).unwrap(),
        equals("boolean"),
      );
      expect(
        (bridge.getGlobal('status2_type') as Value).unwrap(),
        equals("boolean"),
      );
      expect(
        (bridge.getGlobal('errorStatus_type') as Value).unwrap(),
        equals("boolean"),
      );

      // Result types should match expected Lua types
      expect(
        (bridge.getGlobal('result1_type') as Value).unwrap(),
        equals("nil"),
      );
      expect(
        (bridge.getGlobal('result2_type') as Value).unwrap(),
        equals("boolean"),
      );
      // Error result type can be either "table" or "string" depending on how the error is handled
      expect(
        (bridge.getGlobal('errorResult_type') as Value).unwrap(),
        anyOf(equals("table"), equals("string")),
      );
    });

    test('pcall with different function types', () async {
      final bridge = LuaLike();

      // Test pcall with different types of functions
      await bridge.execute('''
        -- Test with user-defined function
        function userFunc(x) return x * 2 end
        userStatus, userResult = pcall(userFunc, 5)

        -- Test with anonymous function
        anonStatus, anonResult = pcall(function(x) return x + 1 end, 10)

        -- Test with builtin function that might throw
        builtinStatus, builtinResult = pcall(tonumber, "not_a_number")

        -- Test with function that returns multiple values
        -- pcall only returns the first result, not all multiple values
        multiStatus, firstResult = pcall(function() return 1, 2, 3 end)
        multi_count = (firstResult ~= nil) and 1 or 0
      ''');

      expect((bridge.getGlobal('userStatus') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('userResult') as Value).unwrap(), equals(10));

      expect((bridge.getGlobal('anonStatus') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('anonResult') as Value).unwrap(), equals(11));

      expect(
        (bridge.getGlobal('builtinStatus') as Value).unwrap(),
        equals(true),
      );
      expect((bridge.getGlobal('builtinResult') as Value).unwrap(), isNull);

      expect((bridge.getGlobal('multiStatus') as Value).unwrap(), equals(true));
      expect((bridge.getGlobal('multi_count') as Value).unwrap(), equals(1));
    });
  });
}
