# `convert` Library

The `convert` library exposes encoding and decoding helpers backed by Dart's
`dart:convert` package.

## Table of Contents

- [Overview](#overview)
- [Accepted byte-oriented inputs](#accepted-byte-oriented-inputs)
- [JSON helpers](#json-helpers)
- [Base64 helpers](#base64-helpers)
- [ASCII and Latin-1 helpers](#ascii-and-latin-1-helpers)
- [Example](#example)

## Overview

LuaLike registers `convert` as a module-style table:

```lua
local json = convert.jsonEncode({ answer = 42 })
```

The library is useful when you need to move data between Lua tables, strings,
and byte-oriented Dart values such as `Uint8List`.

## Accepted byte-oriented inputs

The byte-oriented functions in this library accept:

- a `Uint8List`
- a Lua array-style table of integers
- in some cases a `LuaString`, where the raw byte payload matters

This is especially relevant when you combine `convert` with
[`dart.string.bytes`](./dart_string_bytes.md).

## JSON helpers

### `convert.jsonEncode(value)`

Encodes a LuaLike value into a JSON string.

- Tables become JSON arrays or objects depending on their shape.
- Numbers, booleans, strings, and `nil` map through the normal LuaLike to Dart
  conversion rules.
- If the value cannot be encoded, the function raises a `LuaError`.

### `convert.jsonDecode(string)`

Decodes a JSON string into LuaLike values.

- JSON objects become LuaLike tables with string keys.
- JSON arrays become sequence-style tables.
- Scalars map back to the obvious LuaLike values.

## Base64 helpers

### `convert.base64Encode(bytes)`

Encodes bytes into a Base64 string.

### `convert.base64Decode(string)`

Decodes a Base64 string into a `Uint8List`.

### `convert.base64UrlEncode(bytes)`

Encodes bytes using the URL-safe Base64 alphabet.

## ASCII and Latin-1 helpers

### `convert.asciiEncode(string)`

Encodes a string into ASCII bytes.

This raises an error if the string contains characters outside the ASCII
range.

### `convert.asciiDecode(bytes)`

Decodes ASCII bytes into a Dart string.

### `convert.latin1Encode(string)`

Encodes a string into Latin-1 bytes.

If the input is a `LuaString`, LuaLike preserves its raw bytes directly rather
than first converting through UTF-16.

### `convert.latin1Decode(bytes)`

Decodes Latin-1 bytes into a `LuaString`.

This is an intentional byte-preserving behavior. Unlike the ASCII helpers,
`latin1Decode()` does not normalize the result into a plain Dart string.

## Example

```lua
local payload = { name = "LuaLike", awesome = true }
local encoded = convert.jsonEncode(payload)
local decoded = convert.jsonDecode(encoded)

print(encoded)
print(decoded.name)

local bytes = dart.string.bytes.toBytes("hello")
local b64 = convert.base64Encode(bytes)
local roundtrip = convert.base64Decode(b64)

print(dart.string.bytes.fromBytes(roundtrip))
```
