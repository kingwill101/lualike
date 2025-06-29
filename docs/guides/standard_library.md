# The Standard Library in Lualike

This guide provides an overview of the standard library available in `lualike`, which includes a range of useful functions for common tasks like string manipulation, table operations, and mathematical calculations.

## Overview

The `lualike` standard library is designed to be highly compatible with the standard library found in Lua. It provides a powerful set of tools without needing to import external modules.

While the goal is to provide a familiar experience for Lua developers, `lualike` is not a 1:1 clone of Lua. Some functions may have different behavior, and some libraries (like the `coroutine` library) are not implemented. Always refer to the specific documentation for each module for details.

The standard library is organized into several modules, which are available as global variables.

## `string` - String Manipulation

The `string` library provides a comprehensive set of functions for working with strings.

### Common Functions

-   `string.len(s)`: Returns the length of a string.
-   `string.sub(s, i, [j])`: Returns a substring of `s` from index `i` to `j`.
-   `string.upper(s)`: Converts a string to uppercase.
-   `string.lower(s)`: Converts a string to lowercase.
-   `string.find(s, pattern)`: Finds the first occurrence of a pattern in a string.
-   `string.gsub(s, pattern, repl)`: Replaces all occurrences of a pattern with a replacement.

### Example

```lua
local my_string = "Hello, lualike!"

print(string.len(my_string))        -- Prints: 15
print(string.upper(my_string))      -- Prints: HELLO, LUALIKE!
print(string.sub(my_string, 8, 14)) -- Prints: lualike

-- You can also use the OO-style colon syntax
print(my_string:len())              -- Prints: 15
```

## `table` - Table Manipulation

The `table` library contains functions for manipulating tables.

### Common Functions

-   `table.insert(t, [pos,] value)`: Inserts an element into a table.
-   `table.remove(t, [pos])`: Removes an element from a table.
-   `table.concat(t, [sep])`: Concatenates the elements of a table into a string.
-   `table.sort(t, [comp])`: Sorts the elements of a table in-place.

### Example

```lua
local my_table = { "b", "c", "a" }

table.sort(my_table)
-- my_table is now { "a", "b", "c" }

print(table.concat(my_table, ", ")) -- Prints: a, b, c

table.insert(my_table, 1, "d")
-- my_table is now { "d", "a", "b", "c" }

table.remove(my_table, 2)
-- my_table is now { "d", "b", "c" }
```

## `math` - Mathematical Functions

The `math` library provides a standard set of mathematical functions.

### Common Functions and Constants

-   `math.pi`: The value of PI.
-   `math.random([m, [n]])`: A pseudo-random number generator.
-   `math.floor(x)`: Returns the largest integer smaller than or equal to `x`.
-   `math.ceil(x)`: Returns the smallest integer larger than or equal to `x`.
-   `math.sqrt(x)`: Returns the square root of `x`.
-   `math.max(x, ...)`: Returns the maximum value among its arguments.
-   `math.min(x, ...)`: Returns the minimum value among its arguments.

### Example

```lua
print(math.pi)         -- Prints: 3.14159...
print(math.sqrt(16))   -- Prints: 4
print(math.max(10, 20, 5)) -- Prints: 20
```

## `dart.string` - Dart-Powered String Manipulation

In addition to the standard `string` library, `lualike` provides a special `dart.string` library that exposes many of Dart's native string manipulation functions. This can be useful for situations where the standard Lua string patterns are insufficient or when you prefer Dart's string API.

### Common Functions

-   `dart.string.split(s, separator)`: Splits a string by a separator.
-   `dart.string.trim(s)`: Removes leading and trailing whitespace. See also `trimLeft` and `trimRight`.
-   `dart.string.contains(s, other)`: Checks if a string contains another.
-   `dart.string.replaceAll(s, from, to)`: Replaces all occurrences of a substring. See also `replaceFirst` and `replaceRange`.
-   `dart.string.padLeft(s, width)`: Pads the string on the left.
-   `dart.string.padRight(s, width)`: Pads the string on the right.
-   `dart.string.startsWith(s, pattern)`: Checks if the string starts with a pattern.
-   `dart.string.endsWith(s, pattern)`: Checks if the string ends with a pattern.

### Example

```lua
local my_string = "  hello, world!  "
local parts = dart.string.split(my_string, ", ") -- {"  hello", "world!  "}
local trimmed = dart.string.trim(my_string) -- "hello, world!"

print(dart.string.contains(trimmed, "world")) -- true
```

### `dart.string.bytes` - Low-Level Byte Manipulation

The `dart.string` library also includes a `bytes` sub-library for converting strings to and from their raw byte representations. This is useful for binary data manipulation and interoperability with I/O operations that expect byte streams.

See the [`dart.string.bytes` documentation](../stdlib/dart_string_bytes.md) for more details.

#### Example

```lua
-- Convert a string to a Uint8List
local bytes = dart.string.bytes.toBytes("hello")

-- Convert the bytes back to a string
local str = dart.string.bytes.fromBytes(bytes)
print(str) -- "hello"

-- Create a string from a table of byte values
local byte_table = { 72, 101, 108, 108, 111 } -- "Hello"
local str_from_table = dart.string.bytes.fromBytes(byte_table)
print(str_from_table) -- "Hello"
```

## `convert` - Data-Representation Conversion

The `convert` library exposes functionality from Dart's `dart:convert` library, providing a powerful set of tools for encoding and decoding various data formats such as JSON, Base64, and more.

See the [`convert` documentation](../stdlib/convert.md) for more details.

### Example

```lua
-- Encode a Lua table to a JSON string
local my_table = { name = "lualike", awesome = true }
local json_string = convert.jsonEncode(my_table)
print(json_string) -- {"name":"lualike","awesome":true}

-- Decode a JSON string back to a Lua table
local decoded_table = convert.jsonDecode(json_string)
print(decoded_table.name) -- lualike
```

## `crypto` - Cryptographic Hashing

The `crypto` library provides functions for creating cryptographic hashes and message authentication codes. It exposes common algorithms like `md5`, `sha256`, and `hmac`, as well as AES encryption.

See the [`crypto` documentation](../stdlib/crypto.md) for more details.

### Example
```lua
local my_data = "lualike is awesome"
local hash = crypto.sha256(my_data)
print("SHA256 Hash: " .. hash)
```

## Other Available Libraries

`lualike` also includes other standard libraries, providing a broad range of functionality.