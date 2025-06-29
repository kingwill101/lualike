# String Library Implementation

This document details the Dart implementation of the `lualike` string library, found in `lib/src/stdlib/lib_string.dart`.

> **Note:** Functions that rely on pattern matching (`string.find`, `string.gmatch`, `string.gsub`, `string.match`) may not work as expected due to limitations in the current pattern matching implementation. For more reliable string manipulation, consider using the `dart.string` library.

## Overview

The string library provides functions for string manipulation, such as finding and extracting substrings, pattern matching, and formatting. In `lualike`, it is loaded as a module, and its functions are typically accessed either as a table (`string.len(s)`) or as methods on string values (`s:len()`). The method-style access is enabled by setting a metatable for all strings that points the `__index` field to the string library's table.

## Function Implementations

### `string.byte`

**Lualike Usage:**
```lua
print(string.byte("abc", 2)) -- 98
```
**Implementation Details:**
Returns the numerical byte code of characters in a string. It can take optional start and end indices to return multiple byte values. The implementation uses Dart's `String.codeUnitAt` method to get the byte value at each position.

### `string.char`

**Lualike Usage:**
```lua
print(string.char(97, 98, 99)) -- "abc"
```
**Implementation Details:**
Converts one or more integer byte codes into a string. It iterates through the arguments, converts each number to an integer, and uses Dart's `String.fromCharCode` to build the resulting string.

### `string.dump`

**Lualike Usage:**
```lua
local f = function() print("hello") end
local dumped = string.dump(f)
-- dumped is now a binary string
```
**Implementation Details:**
Takes a `lualike` function and returns a binary representation of its bytecode. This can be used for serialization. The implementation accesses the function's underlying `Prototype` and uses a `BytecodeSerializer` to convert it into a byte array, which is then returned as a string. An option to strip debug information is also provided.

### `string.find`

**Lualike Usage:**
```lua
local s = "hello world"
print(string.find(s, "world")) -- 7, 11
```
**Implementation Details:**
Searches for a pattern within a string. It can take an optional starting index and a flag to disable pattern matching (`plain` mode). The core logic is handled by a separate `Pattern` class. The implementation creates a `Pattern` instance and calls its `find` method, which returns the start and end indices of the match, or `nil` if not found.

### `string.format`

**Lualike Usage:**
```lua
print(string.format("result: %d", 123)) -- "result: 123"
```
**Implementation Details:**
Creates a formatted string based on a format specifier. It's a complex function that parses the format string for options like `%s`, `%d`, `%f`, etc., and applies them to the corresponding arguments. The `lualike` implementation uses a custom parser that iterates through the format string, and for each format specifier, it processes flags, width, and precision to correctly format the argument value.

### `string.gmatch`

**Lualike Usage:**
```lua
local s = "hello world from lua"
for word in string.gmatch(s, "%a+") do
   print(word)
end
-- "hello", "world", "from", "lua"
```
**Implementation Details:**
Returns an iterator function that, for each call, finds the next match of a pattern in a string. The implementation creates a `Pattern` object and returns a closure. This closure maintains the current search position in the string. Each time it's called, it searches from that position, updates the position for the next call, and returns the captures from the match.

### `string.gsub`

**Lualike Usage:**
```lua
local s = "hello world"
print(string.gsub(s, "world", "lualike")) -- "hello lualike", 1
```
**Implementation Details:**
Performs a global substitution of a pattern in a string. The replacement can be a string, a table, or a function.
- **String:** Replaces the matched pattern. It supports capture references like `%1`, `%2`.
- **Table:** The first capture of the match is used as a key to look up the replacement value in the table.
- **Function:** The capture values from the match are passed as arguments to the function, and its return value is used as the replacement.
The implementation repeatedly finds the pattern and builds the new string using a `StringBuffer`.

### `string.len`

**Lualike Usage:**
```lua
print(string.len("hello")) -- 5
print(#"hello")           -- 5 (equivalent)
```
**Implementation Details:**
Returns the length of a string. This is a simple implementation that gets the `.length` property from the raw Dart string object.

### `string.lower` and `string.upper`

**Lualike Usage:**
```lua
print(string.lower("HELLO")) -- "hello"
print(string.upper("hello")) -- "HELLO"
```
**Implementation Details:**
Converts a string to lowercase or uppercase. The implementation calls Dart's `toLowerCase()` or `toUpperCase()` methods on the string.

### `string.match`

**Lualike Usage:**
```lua
local s = "hello world"
print(string.match(s, "w...d")) -- "world"
```
**Implementation Details:**
Matches a pattern in a string and returns the captured substrings. If the pattern specifies no captures, it returns the entire matched string. The implementation uses the same `Pattern` class as `string.find`, but calls its `match` method which is designed to return the capture values instead of indices.

### `string.rep`

**Lualike Usage:**
```lua
print(string.rep("a", 5)) -- "aaaaa"
```
**Implementation Details:**
Returns a string that is a concatenation of a given string repeated `n` times. The implementation uses Dart's `*` operator on strings (`string * n`). It includes checks to prevent creating strings that are too large.

### `string.reverse`

**Lualike Usage:**
```lua
print(string.reverse("hello")) -- "olleh"
```
**Implementation Details:**
Reverses a string. The implementation splits the string into a list of characters, reverses the list, and then joins it back into a string.

### `string.sub`

**Lualike Usage:**
```lua
print(string.sub("hello", 2, 4)) -- "ell"
```
**Implementation Details:**
Extracts a substring from a string based on start and end indices. The implementation carefully handles both positive and negative indices (which count from the end of the string) to calculate the correct range before calling Dart's `String.substring` method.

### `string.pack`

**Lualike Usage:**
```lua
local binary_data = string.pack("i4", 1234)
```
**Implementation Details:**
Packs binary data into a string according to a format string (e.g., `i4`, `f`, `s2`). It uses a helper class and a `ByteData` buffer to write the binary representation of each argument into the buffer according to the format specifiers, including endianness.

### `string.packsize`

**Lualike Usage:**
```lua
-- Get the size of an integer (4 bytes) and a char (1 byte)
print(string.packsize("ic")) -- 5
```
**Implementation Details:**
Takes a format string and returns the length in bytes that the packed string would have, without actually packing any data. It parses the format string to calculate the total size.

### `string.unpack`

**Lualike Usage:**
```lua
local packed = string.pack("i2i2", 1, 2)
local a, b = string.unpack("i2i2", packed)
print(a, b) -- 1, 2
```
**Implementation Details:**
The reverse of `string.pack`. It reads from a binary string according to a format string and returns the extracted values. It uses a helper class to parse the format and read from a `ByteData` buffer.