# Error Handling in LuaLike

This guide explains how error handling works in LuaLike, including the implementation of `pcall` and `xpcall` functions for protected calls.

## Overview

Error handling in Lua is primarily done through the use of protected calls. When an error occurs during normal execution, it interrupts the normal flow of the program. However, using protected calls allows you to catch these errors and handle them gracefully.

LuaLike implements this behavior through the `pcall` and `xpcall` functions, which provide mechanisms for executing code in a protected environment.

## Error Propagation

In LuaLike, errors are propagated through Dart exceptions. When an error occurs in Lua code, it's represented as a Dart exception that contains the error message. This exception is then caught by the interpreter and converted to a Lua error.

## Protected Calls

### pcall

The `pcall` function calls a given function in protected mode. If the function executes without errors, `pcall` returns `true` followed by any return values from the function. If an error occurs, `pcall` returns `false` followed by the error message.

#### Syntax

```lua
status, result = pcall(f, arg1, arg2, ...)
```

#### Parameters

- `f`: The function to call in protected mode
- `arg1, arg2, ...`: Arguments to pass to the function

#### Return Values

- `status`: A boolean indicating whether the call succeeded (`true`) or failed (`false`)
- `result`: If the call succeeded, the return value(s) of the function. If the call failed, the error message.

#### Example

```lua
-- Successful call
local status, result = pcall(function() return "success" end)
-- status = true, result = "success"

-- Failed call
local status, error_msg = pcall(function() error("something went wrong") end)
-- status = false, error_msg = "something went wrong"

-- Call with arguments
local status, sum = pcall(function(x, y) return x + y end, 10, 20)
-- status = true, sum = 30
```

### xpcall

The `xpcall` function is similar to `pcall`, but it allows you to specify a message handler function that is called when an error occurs. This handler can be used to gather more information about the error, such as a stack traceback.

#### Syntax

```lua
status, result = xpcall(f, msgh, arg1, arg2, ...)
```

#### Parameters

- `f`: The function to call in protected mode
- `msgh`: The message handler function to call if an error occurs
- `arg1, arg2, ...`: Arguments to pass to the function

#### Return Values

- `status`: A boolean indicating whether the call succeeded (`true`) or failed (`false`)
- `result`: If the call succeeded, the return value(s) of the function. If the call failed, the return value of the message handler.

#### Example

```lua
-- Successful call
local status, result = xpcall(
  function() return "success" end,
  function(err) return "Handler: " .. err end
)
-- status = true, result = "success"

-- Failed call
local status, error_msg = xpcall(
  function() error("something went wrong") end,
  function(err) return "Handled: " .. err end
)
-- status = false, error_msg = "Handled: something went wrong"

-- Call with arguments
local status, sum = xpcall(
  function(x, y) return x + y end,
  function(err) return "Error in addition: " .. err end,
  10, 20
)
-- status = true, sum = 30
```

## Implementation Details

In LuaLike, `pcall` and `xpcall` are implemented as built-in functions that handle both synchronous and asynchronous code execution. This is particularly important in Dart, where many operations are asynchronous.

### PCAllFunction

The `PCAllFunction` class implements the `pcall` function:

```dart
class PCAllFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) throw Exception("pcall requires a function");
    final func = args[0] as Value;
    final callArgs = args.sublist(1);

    if (func.raw is! Function) {
      throw Exception("pcall requires a function as its first argument");
    }

    try {
      final result = func.raw as Function;
      final callResult = result(callArgs);

      // Handle both synchronous and asynchronous results
      if (callResult is Future) {
        try {
          final awaitedResult = await callResult;
          // Return true (success) followed by the result
          if (awaitedResult is List && awaitedResult.isNotEmpty) {
            // If the function returned multiple values, spread them
            return [Value(true), ...awaitedResult];
          } else {
            return [Value(true), awaitedResult is Value ? awaitedResult : Value(awaitedResult)];
          }
        } catch (e) {
          // Return false (failure) followed by the error message
          return [Value(false), Value(e.toString())];
        }
      } else {
        // Handle synchronous result
        if (callResult is List && callResult.isNotEmpty) {
          // If the function returned multiple values, spread them
          return [Value(true), ...callResult];
        } else {
          return [Value(true), callResult is Value ? callResult : Value(callResult)];
        }
      }
    } catch (e) {
      // Return false (failure) followed by the error message
      return [Value(false), Value(e.toString())];
    }
  }
}
```

### XPCallFunction

The `XPCallFunction` class implements the `xpcall` function, adding support for a message handler:

```dart
class XPCallFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.length < 2) {
      throw Exception("xpcall requires at least two arguments");
    }
    final func = args[0] as Value;
    final msgh = args[1] as Value;
    final callArgs = args.sublist(2);

    if (func.raw is! Function) {
      throw Exception("xpcall requires a function as its first argument");
    }

    if (msgh.raw is! Function) {
      throw Exception("xpcall requires a function as its second argument");
    }

    try {
      final result = func.raw as Function;
      final callResult = result(callArgs);

      // Handle both synchronous and asynchronous results
      if (callResult is Future) {
        try {
          final awaitedResult = await callResult;
          // Return true (success) followed by the result
          if (awaitedResult is List && awaitedResult.isNotEmpty) {
            // If the function returned multiple values, spread them
            return [Value(true), ...awaitedResult];
          } else {
            return [Value(true), awaitedResult is Value ? awaitedResult : Value(awaitedResult)];
          }
        } catch (e) {
          // Call the message handler with the error
          try {
            final errorHandler = msgh.raw as Function;
            final handlerResult = errorHandler([Value(e.toString())]);

            if (handlerResult is Future) {
              try {
                final awaitedHandlerResult = await handlerResult;
                return [Value(false), awaitedHandlerResult is Value ? awaitedHandlerResult : Value(awaitedHandlerResult)];
              } catch (e2) {
                return [Value(false), Value("Error in error handler: $e2")];
              }
            } else {
              return [Value(false), handlerResult is Value ? handlerResult : Value(handlerResult)];
            }
          } catch (e2) {
            return [Value(false), Value("Error in error handler: $e2")];
          }
        }
      } else {
        // Handle synchronous result
        if (callResult is List && callResult.isNotEmpty) {
          // If the function returned multiple values, spread them
          return [Value(true), ...callResult];
        } else {
          return [Value(true), callResult is Value ? callResult : Value(callResult)];
        }
      }
    } catch (e) {
      // Call the message handler with the error
           try {
             final errorHandler = msgh.raw as Function;

             // If the error is a Value (like our table), pass it directly
             final errorValue = e is Value ? e : Value(e.toString());

             final handlerResult = errorHandler([errorValue]);

             if (handlerResult is Future) {
               try {
                 final awaitedHandlerResult = await handlerResult;
                 return [
                   Value(false),
                   awaitedHandlerResult is Value
                       ? awaitedHandlerResult
                       : Value(awaitedHandlerResult),
                 ];
               } catch (e2) {
                 return [Value(false), Value("Error in error handler: $e2")];
               }
             } else {
               return [
                 Value(false),
                 handlerResult is Value ? handlerResult : Value(handlerResult),
               ];
             }
           } catch (e2) {
             return [Value(false), Value("Error in error handler: $e2")];
           }
    }
  }
}
```

## Best Practices

When working with error handling in LuaLike, consider the following best practices:

1. **Always use protected calls for code that might fail**: Use `pcall` or `xpcall` when executing code that might throw errors, especially when loading files, parsing data, or calling user-defined functions.

2. **Provide meaningful error messages**: When using `error()`, provide clear and descriptive error messages that explain what went wrong and how to fix it.

3. **Use xpcall for debugging**: When debugging, use `xpcall` with a custom error handler that provides more information about the error, such as a stack traceback.

4. **Handle asynchronous errors properly**: In Dart, many operations are asynchronous. LuaLike's implementation of `pcall` and `xpcall` handles both synchronous and asynchronous code, but be aware that asynchronous errors might be reported differently.

5. **Check the status return value**: Always check the first return value of `pcall` and `xpcall` to determine if the call succeeded or failed before using the result.

## Asynchronous Error Handling

LuaLike's implementation of `pcall` and `xpcall` is designed to work with both synchronous and asynchronous code. This is particularly important in Dart, where many operations are asynchronous.

When a function called with `pcall` or `xpcall` returns a `Future`, the protected call will automatically await the result and handle any errors that occur during the asynchronous operation.

### Example with Asynchronous Code

```lua
-- Define an asynchronous function that returns a Future
local async_function = function()
  -- This would be implemented in Dart to return a Future
  return dart.future_value("async result")
end

-- Call the asynchronous function with pcall
local status, result = pcall(async_function)
print("Status:", status, "Result:", result)

-- Call the asynchronous function with xpcall
local xstatus, xresult = xpcall(
  async_function,
  function(err) return "Async error: " .. err end
)
print("XPCall Status:", xstatus, "XPCall Result:", xresult)
```

In this example, `pcall` and `xpcall` will automatically await the `Future` returned by `async_function` and handle any errors that occur during the asynchronous operation.

## Advanced Examples

### Nested Protected Calls

You can nest protected calls to handle errors at different levels:

```lua
local status, result = pcall(function()
  -- Outer protected call

  local inner_status, inner_result = pcall(function()
    -- Inner protected call
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
```

### Custom Error Handler with Stack Traceback

You can use `xpcall` with a custom error handler that provides a stack traceback:

```lua
local function error_handler(err)
  -- In a real implementation, you would gather stack information here
  return {
    message = err,
    traceback = debug.traceback(err, 2)  -- Not implemented in LuaLike yet
  }
end

local status, result = xpcall(
  function() error("Custom error") end,
  error_handler
)

if not status then
  print("Error:", result.message)
  print("Traceback:", result.traceback)
end
```

### Error Handling in Loops

You can use protected calls in loops to continue processing even if some iterations fail:

```lua
local data = {1, 2, "not a number", 4, "another string", 6}
local results = {}

for i, value in ipairs(data) do
  local status, result = pcall(function()
    -- This will fail for non-number values
    return value * 2
  end)

  if status then
    results[i] = result
  else
    results[i] = "Error: " .. result
    print("Error processing item", i, ":", result)
  end
end

-- Continue processing with the results we have
for i, result in ipairs(results) do
  print("Result", i, ":", result)
end
```

### Handling Different Types of Errors

You can use pattern matching to handle different types of errors:

```lua
local function process_data(data)
  if type(data) ~= "table" then
    error("TypeError: Expected table, got " .. type(data))
  end

  if #data == 0 then
    error("ValueError: Empty data")
  end

  -- Process the data...
  return "Processed " .. #data .. " items"
end

local function handle_error(err)
  if string.match(err, "^TypeError:") then
    return {type = "type_error", message = err}
  elseif string.match(err, "^ValueError:") then
    return {type = "value_error", message = err}
  else
    return {type = "unknown_error", message = err}
  end
end

local test_cases = {
  {name = "Valid data", data = {1, 2, 3}},
  {name = "Invalid type", data = "not a table"},
  {name = "Empty data", data = {}}
}

for _, test in ipairs(test_cases) do
  local status, result = xpcall(
    function() return process_data(test.data) end,
    handle_error
  )

  print("Test:", test.name)
  if status then
    print("  Success:", result)
  else
    print("  Error type:", result.type)
    print("  Error message:", result.message)
  end
end
```

## Integration with Dart

When integrating LuaLike with Dart code, you can use the `LuaLikeBridge` class to handle errors between Dart and Lua:

```dart
import 'package:lualike/lualike.dart';

void main() async {
  final bridge = LuaLikeBridge();

  // Register a Dart function that might throw an error
  bridge.expose('dart_function', (List<Object?> args) {
    final value = (args[0] as Value).raw;
    if (value is! num) {
      throw Exception("Expected a number");
    }
    return Value(value * 2);
  });

  // Call the Dart function from Lua with error handling
  await bridge.runCode('''
    local status, result = pcall(dart_function, 10)
    print("Status:", status, "Result:", result)

    local error_status, error_msg = pcall(dart_function, "not a number")
    print("Error Status:", error_status, "Error Message:", error_msg)
  ''');
}
```

This example shows how to use `pcall` to handle errors that might occur when calling Dart functions from Lua code.

## Conclusion

Error handling is a critical aspect of any programming language, and LuaLike provides robust mechanisms for handling errors through `pcall` and `xpcall`. By using these functions, you can write code that gracefully handles errors and provides a better user experience.

For more information on error handling in Lua, see the [Lua 5.4 Reference Manual](https://www.lua.org/manual/5.4/manual.html#2.3).
