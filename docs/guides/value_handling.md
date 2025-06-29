# Data Types in Lualike

This guide provides an overview of the fundamental data types available in the `lualike` language.

## Overview

`lualike` is a dynamically-typed language, which means that variables do not have types; only values do. All values carry their own type information.

There are six basic types in `lualike`: `nil`, `boolean`, `number`, `string`, `table`, and `function`.

The built-in `type()` function can be used to get the type of any value as a string.

```lua
print(type("Hello"))  -- Prints: string
print(type(123))      -- Prints: number
print(type(true))     -- Prints: boolean
print(type({}))       -- Prints: table
print(type(print))    -- Prints: function
print(type(nil))      -- Prints: nil
```

## `nil`

`nil` is the type of the value `nil`, whose main property is to be different from any other value. It usually represents the absence of a useful value. A variable is considered `nil` if it has not been assigned a value.

```lua
local a
print(a) -- Prints: nil

a = 10
print(a) -- Prints: 10

a = nil
print(a) -- Prints: nil
```

Assigning `nil` to a table field deletes it.

## `boolean`

The `boolean` type has two values: `true` and `false`.

Booleans are often the result of comparisons:
```lua
print(10 > 5)  -- Prints: true
print(10 == 20) -- Prints: false
```

In `lualike`, both `false` and `nil` are considered "falsy" in conditional expressions. Any other value is considered "truthy".

```lua
if 0 then
  print("0 is considered true") -- This will be printed
end

if "" then
  print("An empty string is considered true") -- This will be printed
end

if not nil then
  print("nil is false") -- This will be printed
end
```

## `number`

The `number` type represents real (double-precision floating-point) numbers.

```lua
local n1 = 10
local n2 = 3.14
local n3 = 1.2e3 -- Scientific notation for 1200
```

## `string`

The `string` type represents sequences of characters. You can create strings using single or double quotes.

```lua
local s1 = 'hello'
local s2 = "world"
```

Strings in `lualike` are immutable. Functions like `string.upper` do not change the original string; they return a new one.

The `..` operator is used for string concatenation.
```lua
local message = "hello" .. " " .. "world"
print(message) -- Prints: hello world
```

## `table`

The `table` type is the most powerful and versatile data structure in `lualike`. A table can be used as an array, a dictionary (or map), or a combination of both.

**As an array:**
```lua
local my_list = { "a", "b", "c" }
print(my_list[1]) -- Prints: a
```
> Note: By convention, arrays in `lualike` are 1-based.

**As a dictionary:**
```lua
local person = {
  name = "John Doe",
  age = 30
}
print(person.name) -- Prints: John Doe
```

## `function`

Functions are first-class citizens in `lualike`. This means they can be stored in variables, passed as arguments to other functions, and returned as results.

```lua
function add(a, b)
  return a + b
end

local my_add = add -- Assign a function to a variable
print(my_add(10, 20)) -- Prints: 30
```

## Type Coercion

`lualike` provides automatic conversion (coercion) between string and number values at run time. When a string is used in an arithmetic operation, it is converted to a number. When a number is used where a string is expected, it is converted to a string.

```lua
-- String to number coercion
local result = "10" + 5  -- result is the number 15
print(result)

-- Number to string coercion
local message = "The value is: " .. 100
print(message) -- Prints: The value is: 100
```

This only works for strings that look like numbers. The following would cause an error:
```lua
-- This will cause an error
-- local bad_result = "hello" + 5
```