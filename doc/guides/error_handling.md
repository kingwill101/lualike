# Error Handling in Lualike

This guide explains how to handle errors gracefully in `lualike` using protected calls and custom error handling.

## Overview

In `lualike`, an error interrupts the normal flow of a program. To manage this, you can execute code in "protected mode". This allows you to catch errors and handle them without crashing the script.

The primary tools for this are the built-in functions `pcall` and `xpcall`.

## The `error` Function

The simplest way to signal an error is with the `error` function. It terminates the last protected function call and returns a message to it.

```lua
error("Something has gone wrong!")
```

If the error occurs outside of any protected call, the program will terminate.

## Protected Calls with `pcall`

The `pcall` (protected call) function calls another function in protected mode. If the called function runs without errors, `pcall` returns `true` along with any values returned by the function. If an error occurs, it returns `false` and the error object.

#### Syntax

```lua
local success, result_or_error = pcall(my_function, arg1, arg2, ...)
```

#### Examples

A successful call:
```lua
local function add(a, b)
  return a + b
end

local success, result = pcall(add, 10, 20)
-- success is true
-- result is 30
```

A call that results in an error:
```lua
local success, err = pcall(add, 10, "hello")
-- success is false
-- err is a string containing the error message "attempt to perform arithmetic on a string value"
```

## Advanced Protected Calls with `xpcall`

The `xpcall` (extended protected call) function is similar to `pcall`, but it allows you to provide a second argument: a **message handler** function.

If an error occurs, `xpcall` calls this message handler with the original error object, and the return value of the handler becomes the return value of `xpcall`. This is useful for adding more context to an error, such as a stack traceback.

#### Syntax

```lua
local success, result = xpcall(my_function, error_handler, arg1, arg2, ...)
```

#### Example

```lua
local function my_error_handler(err)
  -- You could add more logic here, like logging or a stack trace
  return "Error caught: " .. tostring(err)
end

local function cause_error()
  error("a problem occurred")
end

local success, result = xpcall(cause_error, my_error_handler)
-- success is false
-- result is "Error caught: a problem occurred"
```

## Common Error Handling Patterns

### Safely Accessing a Table Field

You can use `pcall` to safely access a table field that might be `nil`, preventing "attempt to index a nil value" errors.

```lua
local my_table = { config = { setting = "value" } }
-- local my_table = nil -- Uncomment to test the error case

local success, setting = pcall(function()
  return my_table.config.setting
end)

if success then
  print("Setting is: " .. setting)
else
  print("Could not get setting, using default.")
end
```

### Safe Type Conversion

When converting user input or external data, `pcall` can protect against errors from invalid formats.

```lua
local success, num = pcall(tonumber, "123x")

if success and num ~= nil then
  print("Converted number:", num)
else
  print("Invalid number format.")
end
```
