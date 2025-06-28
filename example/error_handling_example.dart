import 'package:lualike/lualike.dart';

/// This example demonstrates error handling in LuaLike using pcall and xpcall.
void main() async {
  // Create a LuaLikeBridge instance
  final bridge = LuaLikeBridge();

  // Enable logging to see what's happening
  Logger.setEnabled(true);

  // Register a Dart function that might throw an error
  bridge.expose('dart_function', (List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("No arguments provided");
    }

    final value = (args[0] as Value).raw;
    if (value is! num) {
      throw Exception("Expected a number, got ${value.runtimeType}");
    }

    return Value(value * 2);
  });

  // Register an asynchronous Dart function
  bridge.expose('async_dart_function', (List<Object?> args) async {
    // Simulate an asynchronous operation
    await Future.delayed(Duration(milliseconds: 100));

    if (args.isEmpty) {
      throw Exception("No arguments provided");
    }

    final value = (args[0] as Value).raw;
    if (value is! num) {
      throw Exception("Expected a number, got ${value.runtimeType}");
    }

    return Value(value * 2);
  });

  print("=== Basic pcall Example ===");
  await bridge.runCode('''
    -- Successful call
    local status, result = pcall(function() return "success" end)
    print("Success status:", status, "Result:", result)

    -- Failed call
    local error_status, error_msg = pcall(function() error("test error") end)
    print("Error status:", error_status, "Error message:", error_msg)

    -- Call with arguments
    local arg_status, arg_result = pcall(function(x, y) return x + y end, 10, 20)
    print("With args status:", arg_status, "Result:", arg_result)
  ''');

  print("\n=== Basic xpcall Example ===");
  await bridge.runCode('''
    -- Successful call with xpcall
    local status, result = xpcall(
      function() return "success" end,
      function(err) return "Handler: " .. err end
    )
    print("Success status:", status, "Result:", result)

    -- Failed call with xpcall
    local error_status, error_msg = xpcall(
      function() error("test error") end,
      function(err) return "Handled: " .. err end
    )
    print("Error status:", error_status, "Error message:", error_msg)
  ''');

  print("\n=== Calling Dart Functions with Error Handling ===");
  await bridge.runCode('''
    -- Successful call to Dart function
    local status, result = pcall(function() return dart_function(10) end)
    print("Dart function success status:", status, "Result:", result)

    -- Failed call to Dart function
    local error_status, error_msg = pcall(function() return dart_function("not a number") end)
    print("Dart function error status:", error_status, "Error message:", error_msg)
  ''');

  print("\n=== Calling Asynchronous Dart Functions with Error Handling ===");
  await bridge.runCode('''
    -- Successful call to async Dart function
    local status, result = pcall(function() return async_dart_function(10) end)
    print("Async Dart function success status:", status, "Result:", result)

    -- Failed call to async Dart function
    local error_status, error_msg = pcall(function() return async_dart_function("not a number") end)
    print("Async Dart function error status:", error_status, "Error message:", error_msg)
  ''');

  print("\n=== Nested Protected Calls ===");
  await bridge.runCode('''
    local status, result = pcall(function()
      -- Outer protected call

      local inner_status, inner_result = pcall(function()
        -- Inner protected call that fails
        error("Inner error")
      end)

      if not inner_status then
        print("Caught inner error:", inner_result)
        -- Re-throw the error to the outer protected call
        error("Outer error: " .. inner_result)
      end

      return inner_result
    end)

    print("Outer status:", status, "Outer result:", result)
  ''');

  print("\n=== Error Handling in Loops ===");
  await bridge.runCode('''
    local data = {1, 2, "not a number", 4, "another string", 6}
    local results = {}

    -- Process each item with error handling
    for i = 1, #data do
      local value = data[i]
      local status, result = pcall(function()
        return value * 2
      end)

      if status then
        results[i] = result
      else
        results[i] = "Error: " .. result
      end
    end

    -- Continue processing with the results we have
    print("Results after error handling:")
    for i = 1, #results do
      print("  Result", i, ":", results[i])
    end
  ''');

  // Disable logging
  Logger.setEnabled(false);
}
