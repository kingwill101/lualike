# `dart.string` Library

The `dart.string` helpers expose Dart-native string operations under the global
`dart` table.

Use this library when you want Dart indexing and trimming semantics rather than
Lua's byte-oriented `string` library behavior.

## Table of Contents

- [Namespace layout](#namespace-layout)
- [Indexing semantics](#indexing-semantics)
- [Available functions](#available-functions)
- [Bytes sub-library](#bytes-sub-library)
- [Example](#example)

## Namespace layout

The library is available as `dart.string`:

```lua
local parts = dart.string.split("a,b,c", ",")
```

The registered functions are:

- `split`
- `trim`
- `toUpperCase`
- `toLowerCase`
- `contains`
- `replaceAll`
- `substring`
- `trimLeft`
- `trimRight`
- `padLeft`
- `padRight`
- `startsWith`
- `endsWith`
- `indexOf`
- `lastIndexOf`
- `replaceFirst`
- `isEmpty`
- `fromCharCodes`

## Indexing semantics

This library delegates to Dart `String` methods, so indexes are:

- zero-based
- based on Dart string indexing rules
- not the same as Lua's usual 1-based byte positions

That difference is the main reason this library exists separately from the
standard `string` module.

## Available functions

### Whitespace and case helpers

- `dart.string.trim(s)`
- `dart.string.trimLeft(s)`
- `dart.string.trimRight(s)`
- `dart.string.toUpperCase(s)`
- `dart.string.toLowerCase(s)`

### Search helpers

- `dart.string.contains(s, other, [startIndex])`
- `dart.string.startsWith(s, pattern, [index])`
- `dart.string.endsWith(s, other)`
- `dart.string.indexOf(s, pattern, [start])`
- `dart.string.lastIndexOf(s, pattern, [start])`

### Transformation helpers

- `dart.string.split(s, separator)`
- `dart.string.replaceAll(s, from, to)`
- `dart.string.replaceFirst(s, from, to, [startIndex])`
- `dart.string.substring(s, startIndex, [endIndex])`
- `dart.string.padLeft(s, width, [padding])`
- `dart.string.padRight(s, width, [padding])`
- `dart.string.fromCharCodes(table)`

### Predicates

- `dart.string.isEmpty(s)`

## Bytes sub-library

`dart.string.bytes` exposes UTF-8 byte conversion helpers. See
[`dart.string.bytes`](./dart_string_bytes.md).

## Example

```lua
local raw = "  LuaLike  "
local trimmed = dart.string.trim(raw)

print(trimmed)
print(dart.string.startsWith(trimmed, "Lua"))
print(dart.string.substring(trimmed, 0, 3))
```
