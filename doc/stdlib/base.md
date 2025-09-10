# Base Library Implementation

This document details the Dart implementation of the `lualike` base library, found in `lib/src/stdlib/lib_base.dart`.

## Overview

The base library provides essential, globally-available functions for `lualike` scripts. These include functions for type checking, error handling, metatable manipulation, and iteration. Unlike other standard library modules, these functions are typically registered directly into the global environment.

Each function is implemented in Dart as a class that adheres to the `BuiltinFunction` interface.

## Function Implementations

### `assert`

**Lualike Usage:**
```lua
assert(1 + 1 == 2, "Math is broken") -- Does nothing
-- assert(false, "This will error")
```

**Implementation Details:**
The `assert` function checks if its first argument is "truthy". In `lualike`, only `false` and `nil` are considered falsy; all other values (including `0` and empty strings) are truthy. If the check fails, it throws an error using the second argument as the message. If the assertion passes, it returns all of its original arguments, allowing it to be used in expressions.

### `error`

**Lualike Usage:**
```lua
-- error("Something went wrong")
-- error("Something went wrong", 2) -- Level 2 indicates where to blame the error
```

**Implementation Details:**
Throws an error, which immediately terminates the script unless it is caught by a protected call (`pcall` or `xpcall`). The implementation includes a static flag to prevent recursive errors within the error handling mechanism itself. When an `Interpreter` instance is available, it provides a full stack trace with the error. The optional second argument, `level`, specifies where to report the error in the call stack.

### `getmetatable`

**Lualike Usage:**
```lua
local my_table = {}
setmetatable(my_table, { __index = function() return "default" end })
local mt = getmetatable(my_table)
-- print(mt.__index) --> function
```

**Implementation Details:**
Retrieves the metatable of a given value. If the metatable has a `__metatable` field, the value of that field will be returned instead. This allows metatables to be protected or hidden from direct inspection.

### `ipairs`

**Lualike Usage:**
```lua
local t = { "a", "b", "c" }
for i, v in ipairs(t) do
  print(i, v)
end
-- 1   a
-- 2   b
-- 3   c
```

**Implementation Details:**
Returns an iterator function designed for use in a `for` loop, specifically for iterating over the "array-like" part of a table (integer keys from 1 upwards). It returns three values: the iterator function, the table itself, and an initial index of `0`. The `for` loop repeatedly calls the iterator function, which increments the index and returns the next integer key and its corresponding value, stopping as soon as it encounters a `nil` value.

### `next`

**Lualike Usage:**
```lua
local t = { first = 1, second = 2 }
local k, v = next(t)
print(k, v) -- "first", 1 (or "second", 2; order is not guaranteed)
k, v = next(t, k)
print(k, v) -- The other pair
```

**Implementation Details:**
Provides a primitive mechanism for iterating through all keys in a table, regardless of type. Given a table and a key, it returns the "next" key-value pair in the table's internal sequence. If the given key is `nil`, it returns the very first pair. It returns `nil` when there are no more keys to iterate over. The `pairs` function is implemented using `next`.

### `pairs`

**Lualike Usage:**
```lua
local t = { first = 1, second = 2, [3] = "three" }
for k, v in pairs(t) do
  print(k, v)
end
-- (prints all three key-value pairs in an arbitrary order)
```

**Implementation Details:**
Returns an iterator function for a generic `for` loop to iterate over all key-value pairs in a table. It's a simple wrapper that returns the `next` function, the table itself, and `nil` as the initial state for the iterator.

### `pcall` and `xpcall`

**Lualike Usage:**
```lua
local ok, result = pcall(function() return 1 + 1 end)
print(ok, result) -- true, 2

local ok_err, err_msg = pcall(function() error("an error") end)
print(ok_err, err_msg) -- false, "an error"
```

**Implementation Details:**
These functions execute a given function in "protected mode," allowing for errors to be caught without halting the entire script. The implementation uses a Dart `try...catch` block. A key feature of the `lualike` implementation is its ability to handle both synchronous and asynchronous (returning a `Future`) functions seamlessly. `xpcall` is more advanced, as it also accepts a custom error handler function which is called inside the `catch` block if an error occurs.

### `print`

**Lualike Usage:**
```lua
print("Hello", "world", 123) -- "Hello   world   123"
```

**Implementation Details:**
Prints its arguments to the configured standard output (`stdout`). It iterates through all provided arguments, calls the equivalent of `tostring` on each one, concatenates the resulting strings with a tab character (`\t`) as a separator, and finally prints the full line.

### `rawequal`

**Lualike Usage:**
```lua
local t1 = {}
local t2 = {}
print(rawequal(t1, t1)) -- true
print(rawequal(t1, t2)) -- false
```
**Implementation Details:**
Compares two values for equality without invoking the `__eq` metamethod. The implementation performs a reference equality check for objects like tables, functions, and userdata. For primitive types like numbers, strings, booleans, and nil, it performs a direct value equality check.

### `rawget` and `rawset`

**Lualike Usage:**
```lua
local t = {}
setmetatable(t, { __index = function() return "default" end })
rawset(t, "key", "value")
print(t.key)       -- "value"
print(rawget(t, "key")) -- "value"
print(t.other_key) -- "default"
```

**Implementation Details:**
These functions allow getting or setting a value in a table while bypassing the `__index` and `__newindex` metamethods, respectively. They achieve this by directly accessing the underlying `Map` data structure of the `lualike` table object, ignoring any metatable logic.

### `select`

**Lualike Usage:**
```lua
local args = { "a", "b", "c" }
print(select("#", unpack(args))) -- 3
print(select(2, unpack(args)))  -- "b", "c"
```

**Implementation Details:**
A versatile function for working with a variable number of arguments.
- If the first argument is the string `"#"` it returns the total count of the remaining arguments.
- If the first argument is a number `n`, it returns all arguments from index `n` onwards.

### `tonumber`

**Lualike Usage:**
```lua
print(tonumber("123"))     -- 123
print(tonumber("ff", 16))   -- 255
print(tonumber("invalid")) -- nil
```

**Implementation Details:**
Converts a value to a number. If the value is already a number, it is returned directly. If it is a string, the implementation attempts to parse it. It can handle different number bases (from 2 to 36) if the optional `base` argument is provided. If the conversion is not possible, it returns `nil`.

### `tostring`

**Lualike Usage:**
```lua
print(tostring(123)) -- "123"
print(tostring({})) -- "table: 0x..."
```

**Implementation Details:**
Converts a given value to its string representation. The implementation first checks for a `__tostring` metamethod on the value. If one exists, it is called to produce the result. If not, it falls back to a default representation, such as the raw value for primitives or an identifier including the type and memory address for objects.

### `type`

**Lualike Usage:**
```lua
print(type(123))         -- "number"
print(type("hello"))       -- "string"
print(type({}))          -- "table"
print(type(print))       -- "function"
```

**Implementation Details:**
Returns the `lualike` type of a value as a string. The implementation uses a helper function that inspects the raw Dart type of the `Value` object's contents and returns the corresponding `lualike` type name (e.g., "string", "number", "table", "function").
