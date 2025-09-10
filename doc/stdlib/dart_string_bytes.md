# `dart.string.bytes` Library

The `dart.string.bytes` library provides functions for low-level byte manipulation, allowing for conversion between Lua strings and byte representations like `Uint8List`.

This library is available under the `dart.string` table.

## `dart.string.bytes.toBytes(str)`

Converts a string into a `Uint8List` of its UTF-8 encoded bytes.

### Parameters

-   `str` (string): The string to convert.

### Returns

-   (`Uint8List`): A `Uint8List` object representing the UTF-8 bytes of the input string.

### Example

```lua
local bytes = dart.string.bytes.toBytes("hello")
-- bytes is a Uint8List object
```

## `dart.string.bytes.fromBytes(bytes_data)`

Converts byte data into a string using UTF-8 decoding. The input can be a `Uint8List`, a Lua table of integers, or a `List<int>`.

### Parameters

-   `bytes_data` (`Uint8List` | `table` | `List<int>`): The byte data to convert into a string.

### Returns

-   (string): The decoded string.

### Example

```lua
-- From Uint8List
local bytes = dart.string.bytes.toBytes("hello")
local str = dart.string.bytes.fromBytes(bytes)
-- str is "hello"

-- From a table of integers
local byte_table = {104, 101, 108, 108, 111}
local str_from_table = dart.string.bytes.fromBytes(byte_table)
-- str_from_table is "hello"
```