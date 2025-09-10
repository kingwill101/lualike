# `convert` - Data-Representation Conversion

The `convert` library exposes functionality from Dart's `dart:convert` library, providing a powerful set of tools for encoding and decoding various data formats such as JSON, Base64, ASCII, and Latin-1.

## API Overview

### `convert.jsonEncode(table)`
Encodes a Lua table into a JSON string.

### `convert.jsonDecode(string)`
Decodes a JSON string into a Lua table.

### `convert.base64Encode(bytes)`
Encodes a byte sequence (e.g., from `dart.string.bytes`) into a Base64 string.

### `convert.base64Decode(string)`
Decodes a Base64 string into a `Uint8List`.

### `convert.base64UrlEncode(bytes)`
Encodes a byte sequence into a URL-safe Base64 string.

### `convert.asciiEncode(string)`
Encodes a string into a sequence of ASCII bytes.

### `convert.asciiDecode(bytes)`
Decodes a sequence of ASCII bytes into a string.

### `convert.latin1Encode(string)`
Encodes a string into a sequence of Latin-1 bytes.

### `convert.latin1Decode(bytes)`
Decodes a sequence of Latin-1 bytes into a string.


## Example

```lua
-- Encode a Lua table to a JSON string
local my_table = { name = "lualike", awesome = true }
local json_string = convert.jsonEncode(my_table)
print(json_string) -- {"name":"lualike","awesome":true}

-- Decode a JSON string back to a Lua table
local decoded_table = convert.jsonDecode(json_string)
print(decoded_table.name) -- lualike
```