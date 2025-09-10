# Metatables and Metamethods in Lualike

This guide explains how to use metatables in `lualike` to change the behavior of tables, allowing for powerful features like operator overloading and object-oriented programming.

## Overview

In `lualike`, every table can have a **metatable**. A metatable is a regular table that contains special functions called **metamethods**. When you perform an operation on a table (like adding it to another value, calling it like a function, or accessing a field), `lualike` checks if the table has a metatable with a corresponding metamethod. If it does, that metamethod is called to perform the action.

The `getmetatable` and `setmetatable` functions are used to inspect and change the metatable of a table.

```lua
local my_table = {}
local my_metatable = {}
setmetatable(my_table, my_metatable)

assert(getmetatable(my_table) == my_metatable)
```

## Common Metamethods

Here are some of the most common metamethods and the operations they control:

*   `__add`: Addition (`+`)
*   `__sub`: Subtraction (`-`)
*   `__mul`: Multiplication (`*`)
*   `__div`: Division (`/`)
*   `__tostring`: The `tostring()` function
*   `__index`: Accessing a table field that doesn't exist (`table[key]`)
*   `__newindex`: Writing to a table field that doesn't exist (`table[key] = value`)
*   `__call`: Calling a table like a function (`table()`)

## Examples

### `__tostring`

The `__tostring` metamethod is called whenever `tostring()` is used on the table.

```lua
local my_table = setmetatable({}, {
  __tostring = function(t)
    return "This is my custom table representation!"
  end
})

print(my_table)
-- Prints: This is my custom table representation!
```

### `__add`: Operator Overloading

Metamethods allow you to define behavior for arithmetic operators.

```lua
local vector_metatable = {
  __add = function(v1, v2)
    return { x = v1.x + v2.x, y = v1.y + v2.y }
  end
}

local vec1 = { x = 1, y = 2 }
setmetatable(vec1, vector_metatable)

local vec2 = { x = 10, y = 20 }
setmetatable(vec2, vector_metatable)

local vec3 = vec1 + vec2
-- vec3 is now { x = 11, y = 22 }
```

### `__index`: Table Lookups

The `__index` metamethod is one of the most powerful. It is triggered when you try to access a key that does **not** exist in a table. The `__index` metamethod can be either a function or another table.

**Using a function for `__index`:**

```lua
local my_table = setmetatable({}, {
  __index = function(t, key)
    print("The key '" .. tostring(key) .. "' was not found in the table.")
    return "default value"
  end
})

local val = my_table.some_key
-- Prints: The key 'some_key' was not found in the table.
-- val is now "default value"
```

**Using a table for `__index`:**

If `__index` is a table, `lualike` will look for the missing key in that table instead. This is the foundation of object-oriented programming.

```lua
local defaults = {
  name = "Unknown",
  age = 0
}

local person = setmetatable({}, { __index = defaults })

print(person.name) -- Prints: Unknown
print(person.age)  -- Prints: 0
```

## Creating Classes with Metatables

By combining `__index` and functions, you can create "classes" and "objects".

```lua
-- Our "class" table, which will hold methods
local Car = {}
Car.speed = 0

function Car:accelerate(amount)
  self.speed = self.speed + amount
end

function Car:get_speed()
  return self.speed
end

-- A "constructor" function to create new car objects
function Car:new()
  local new_car = { speed = 0 }
  setmetatable(new_car, { __index = self })
  return new_car
end

-- Create two car objects
local my_car = Car:new()
local your_car = Car:new()

my_car:accelerate(50)

print(my_car:get_speed())   -- Prints: 50
print(your_car:get_speed()) -- Prints: 0
```

## `__newindex`: Writing to a Table

The `__newindex` metamethod is triggered when you try to assign a value to a key that does **not** exist in a table.

```lua
local my_table = setmetatable({}, {
  __newindex = function(t, key, value)
    print("Writing to a non-existent key!")
    -- To actually set the value, you must use rawset
    rawset(t, key, value)
  end
})

my_table.new_key = 123
-- Prints: Writing to a non-existent key!

print(my_table.new_key) -- Prints: 123
```

> **Note:** Inside a `__newindex` function, you must use `rawset(table, key, value)` to modify the table. A normal assignment (`table[key] = value`) would trigger the `__newindex` metamethod again, causing an infinite loop.

## Edge Case: Method Calls on Primitive Types

A subtle but important edge case arises when implementing object-oriented-style method calls on primitive types that have default metatables, such as `string`.

Consider a `lualike` call like `s:len()`, where `s` is a string. This involves two core mechanisms:

1.  **Interpreter**: When the interpreter encounters a method call with colon syntax (`:`), it automatically adds the receiver (`s` in this case) as the first argument to the function call. This is the standard behavior for providing `self` to a method.

2.  **String Metatable**: The default `__index` metamethod for strings is designed to allow calls like `string.len(s)`. To make the OO-style `s:len()` work, its `__index` looks up `len` in the standard `string` library and returns a *new function*. This new function is a closure that, when executed, prepends the original string `s` to the argument list and calls the real `string.len` function.

### The "Double Argument" Problem

When these two mechanisms combine, a problem occurs: `self` is passed twice.

1. The interpreter sees `s:len()` and prepares to call the function it gets from `__index` with `s` as the first argument.
2. The `__index` metamethod for `s` returns the wrapped function.
3. The interpreter calls the wrapped function with `[s]`.
4. The wrapped function then prepends `s` *again* to the argument list, resulting in a call to the real `string.len` with `[s, s]`.

This typically results in an error, as most functions are not expecting the duplicated `self` argument.

### The Solution

This is handled internally by `lualike`. The function returned by the metatable's `__index` is smart enough to check if the `self` argument is already present before adding it. This ensures that the `self` argument is only ever passed once, making both `string.len(s)` and `s:len()` work correctly without conflict.