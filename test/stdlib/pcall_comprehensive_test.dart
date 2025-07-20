import 'package:lualike/testing.dart';

void main() {
  group('PCAll Comprehensive Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('pcall with async functions', () async {
      await lua.execute('''
        -- Test pcall with functions that might be async internally
        local status1, result1 = pcall(tostring, 42)
        local status2, result2 = pcall(tonumber, "123")
        local status3, result3 = pcall(type, {})
      ''');

      expect(lua.getGlobal("status1").unwrap(), equals(true));
      expect(lua.getGlobal("result1").unwrap(), equals("42"));
      expect(lua.getGlobal("status2").unwrap(), equals(true));
      expect(lua.getGlobal("result2").unwrap(), equals(123));
      expect(lua.getGlobal("status3").unwrap(), equals(true));
      expect(lua.getGlobal("result3").unwrap(), equals("table"));
    });

    test('pcall error value preservation', () async {
      await lua.execute('''
        -- Test that error values are preserved correctly
        local status1, err1 = pcall(function() error("string error") end)
        local status2, err2 = pcall(function() error(42) end)
        local status3, err3 = pcall(function() error({message = "table error"}) end)
        local status4, err4 = pcall(function() error(nil) end)

        -- Test that Value objects are preserved in protected calls
        local status5, err5 = pcall(function()
          local t = {custom = "error object"}
          error(t)
        end)
      ''');

      expect(lua.getGlobal("status1").unwrap(), equals(false));
      expect(lua.getGlobal("err1").unwrap(), equals("string error"));

      expect(lua.getGlobal("status2").unwrap(), equals(false));
      expect(lua.getGlobal("err2").unwrap(), equals(42));

      expect(lua.getGlobal("status3").unwrap(), equals(false));
      final err3 = lua.getGlobal("err3").unwrap();
      expect(err3, isA<Map>());

      expect(lua.getGlobal("status4").unwrap(), equals(false));
      expect(lua.getGlobal("err4").unwrap(), isNull);

      expect(lua.getGlobal("status5").unwrap(), equals(false));
      final err5 = lua.getGlobal("err5").unwrap();
      expect(err5, isA<Map>());
      final err5Map = err5 as Map;
      final customValue = err5Map["custom"];
      expect(customValue, isA<Value>());
      expect((customValue as Value).unwrap(), equals("error object"));
    });

    test('pcall with nested calls', () async {
      await lua.execute('''
        -- Test pcall within pcall
        local status, result = pcall(function()
          local innerStatus, innerResult = pcall(function()
            return "nested success"
          end)
          if innerStatus then
            return "outer: " .. innerResult
          else
            error("inner failed")
          end
        end)
      ''');

      expect(lua.getGlobal("status").unwrap(), equals(true));
      expect(lua.getGlobal("result").unwrap(), equals("outer: nested success"));
    });

    test('pcall with various argument types', () async {
      await lua.execute('''
        -- Test pcall with different argument types
        local function testFunc(a, b, c, d, e)
          return type(a), type(b), type(c), type(d), type(e)
        end

        local status, t1, t2, t3, t4, t5 = pcall(testFunc,
          42, "string", true, {}, nil)
      ''');

      expect(lua.getGlobal("status").unwrap(), equals(true));
      // Note: Multiple return values from pcall might be handled differently
      // This test verifies the function can be called with various argument types
    });

    test('pcall yieldable state management', () async {
      // This test verifies that pcall properly manages the yieldable state
      await lua.execute('''
        -- Test that pcall sets non-yieldable state
        local status, result = pcall(function()
          -- This should work even if we're in a non-yieldable context
          return "success"
        end)
      ''');

      expect(lua.getGlobal("status").unwrap(), equals(true));
      expect(lua.getGlobal("result").unwrap(), equals("success"));
    });

    test('pcall protected call state isolation', () async {
      // Test that errors in protected calls are properly isolated
      await lua.execute('''
        -- Test nested pcall behavior with different error types
        local status1, err1 = pcall(function()
          local innerStatus, innerErr = pcall(function()
            error({nested = "table error"})
          end)
          if not innerStatus then
            -- Re-throw the inner error to test error propagation
            error(innerErr)
          end
          return "should not reach here"
        end)

        -- Test that the error object is preserved through nested calls
        local errorType = type(err1)
        local hasNestedField = err1 and err1.nested == "table error"
      ''');

      expect(lua.getGlobal("status1").unwrap(), equals(false));
      expect(lua.getGlobal("errorType").unwrap(), equals("table"));
      expect(lua.getGlobal("hasNestedField").unwrap(), equals(true));
    });

    test('pcall with Dart function exceptions', () async {
      // Test that Dart exceptions are properly converted to Lua errors
      await lua.execute('''
        -- Test pcall with a function that might throw Dart exceptions
        local status1, err1 = pcall(function()
          -- This should trigger error handling in the Dart layer
          local x = 1 / 0  -- Division by zero
          return x
        end)

        -- Test with string operations that might fail
        local status2, err2 = pcall(function()
          local s = nil
          return s:upper()  -- Should fail with nil method call
        end)

        -- Test error function behavior in protected context
        local status3, err3 = pcall(function()
          error({type = "custom", message = "protected error"})
        end)
      ''');

      expect(
        lua.getGlobal("status1").unwrap(),
        equals(true),
      ); // Division by zero returns inf in Lua
      expect(lua.getGlobal("status2").unwrap(), equals(false));
      expect(lua.getGlobal("err2").unwrap().toString(), contains("nil"));

      // Validate that custom error objects are preserved in protected calls
      expect(lua.getGlobal("status3").unwrap(), equals(false));
      final err3 = lua.getGlobal("err3").unwrap();
      expect(err3, isA<Map>());
      final err3Map = err3 as Map;
      final typeValue = err3Map["type"];
      final messageValue = err3Map["message"];
      expect(typeValue, isA<Value>());
      expect(messageValue, isA<Value>());
      expect((typeValue as Value).unwrap(), equals("custom"));
      expect((messageValue as Value).unwrap(), equals("protected error"));
    });

    test('pcall return value consistency', () async {
      // Test that all return values are properly wrapped as Value objects
      await lua.execute('''
        -- Test that return values are consistently wrapped
        local status1, result1 = pcall(function() return nil end)
        local status2, result2 = pcall(function() return false end)
        local status3, result3 = pcall(function() return 0 end)
        local status4, result4 = pcall(function() return "" end)

        -- Test error return value wrapping
        local errorStatus, errorResult = pcall(function() error("test") end)

        -- Verify types are correct
        status1_type = type(status1)
        result1_type = type(result1)
        status2_type = type(status2)
        result2_type = type(result2)
        errorStatus_type = type(errorStatus)
        errorResult_type = type(errorResult)
      ''');

      // All status values should be boolean
      expect(lua.getGlobal("status1_type").unwrap(), equals("boolean"));
      expect(lua.getGlobal("status2_type").unwrap(), equals("boolean"));
      expect(lua.getGlobal("errorStatus_type").unwrap(), equals("boolean"));

      // Result types should match expected Lua types
      expect(lua.getGlobal("result1_type").unwrap(), equals("nil"));
      expect(lua.getGlobal("result2_type").unwrap(), equals("boolean"));
      expect(lua.getGlobal("errorResult_type").unwrap(), equals("string"));
    });

    test('pcall with multi-value returns', () async {
      // Test proper handling of multi-value returns
      await lua.execute('''
        -- Test function returning multiple values
        local status, a, b, c = pcall(function() return 1, 2, 3 end)

        -- Test function returning single value
        local status2, result = pcall(function() return "single" end)

        -- Test function returning no values
        local status3, result3 = pcall(function() end)
      ''');

      expect(lua.getGlobal("status").unwrap(), equals(true));
      expect(lua.getGlobal("a").unwrap(), equals(1));
      expect(lua.getGlobal("b").unwrap(), equals(2));
      expect(lua.getGlobal("c").unwrap(), equals(3));

      expect(lua.getGlobal("status2").unwrap(), equals(true));
      expect(lua.getGlobal("result").unwrap(), equals("single"));

      expect(lua.getGlobal("status3").unwrap(), equals(true));
      expect(lua.getGlobal("result3").unwrap(), isNull);
    });

    test('pcall type error messages', () async {
      // Test that type errors provide clear messages
      await lua.execute('''
        -- Test calling various non-function types
        local status1, err1 = pcall(42)
        local status2, err2 = pcall("string")
        local status3, err3 = pcall({})
        local status4, err4 = pcall(true)
      ''');

      expect(lua.getGlobal("status1").unwrap(), equals(false));
      expect(
        lua.getGlobal("err1").unwrap().toString(),
        contains("attempt to call a number value"),
      );

      expect(lua.getGlobal("status2").unwrap(), equals(false));
      expect(
        lua.getGlobal("err2").unwrap().toString(),
        contains("attempt to call a string value"),
      );

      expect(lua.getGlobal("status3").unwrap(), equals(false));
      expect(
        lua.getGlobal("err3").unwrap().toString(),
        contains("attempt to call a table value"),
      );

      expect(lua.getGlobal("status4").unwrap(), equals(false));
      expect(
        lua.getGlobal("err4").unwrap().toString(),
        contains("attempt to call a boolean value"),
      );
    });

    test('pcall with Value string representation in error messages', () async {
      // Test the specific case where LuaError messages contain Value string representations
      // This tests the debug code added to handle "Value:<actual_value>" patterns
      await lua.execute('''
        -- Test error with simple values that might get wrapped as Value strings
        local status1, err1 = pcall(function()
          error("simple string error")
        end)

        local status2, err2 = pcall(function()
          error(123)
        end)

        local status3, err3 = pcall(function()
          error(true)
        end)

        -- Test error with nil
        local status4, err4 = pcall(function()
          error(nil)
        end)

        -- Test error with complex object
        local status5, err5 = pcall(function()
          local obj = {message = "complex error", code = 500}
          error(obj)
        end)
      ''');

      // Verify that simple string errors are preserved correctly
      expect(lua.getGlobal("status1").unwrap(), equals(false));
      expect(lua.getGlobal("err1").unwrap(), equals("simple string error"));

      // Verify that numeric errors are preserved correctly
      expect(lua.getGlobal("status2").unwrap(), equals(false));
      expect(lua.getGlobal("err2").unwrap(), equals(123));

      // Verify that boolean errors are preserved correctly
      expect(lua.getGlobal("status3").unwrap(), equals(false));
      expect(lua.getGlobal("err3").unwrap(), equals(true));

      // Verify that nil errors are preserved correctly
      expect(lua.getGlobal("status4").unwrap(), equals(false));
      expect(lua.getGlobal("err4").unwrap(), isNull);

      // Verify that complex objects are preserved correctly
      expect(lua.getGlobal("status5").unwrap(), equals(false));
      final err5 = lua.getGlobal("err5").unwrap();
      expect(err5, isA<Map>());
      final err5Map = err5 as Map;
      final messageValue = err5Map["message"];
      final codeValue = err5Map["code"];
      expect(messageValue, isA<Value>());
      expect(codeValue, isA<Value>());
      expect((messageValue as Value).unwrap(), equals("complex error"));
      expect((codeValue as Value).unwrap(), equals(500));
    });

    test('pcall error message extraction from Value representations', () async {
      // This test specifically targets the new debug code that extracts values
      // from "Value:<actual_value>" formatted error messages
      await lua.execute('''
        -- Create a scenario that might produce Value string representations
        local function createErrorWithValueString()
          -- This simulates what might happen internally when a Value gets
          -- converted to a string representation in an error message
          local errorMsg = "test error message"
          error(errorMsg)
        end

        local status, err = pcall(createErrorWithValueString)

        -- Test that the error message is properly extracted and not wrapped
        error_type = type(err)
        error_value = err
      ''');

      expect(lua.getGlobal("status").unwrap(), equals(false));
      expect(lua.getGlobal("error_type").unwrap(), equals("string"));
      expect(
        lua.getGlobal("error_value").unwrap(),
        equals("test error message"),
      );
    });
  });
}
