# `dart.string.bytes` Library

The `dart.string.bytes` sub-library exposes low-level UTF-8 conversion helpers
under `dart.string.bytes`.

## Table of Contents

- [Overview](#overview)
- [`dart.string.bytes.toBytes(str)`](#dartstringbytestobytesstr)
- [`dart.string.bytes.fromBytes(bytes)`](#dartstringbytesfrombytesbytes)
- [Notes](#notes)

## Overview

Use this library when you need to move explicitly between strings and byte
arrays from LuaLike code.

```lua
local bytes = dart.string.bytes.toBytes("hello")
local text = dart.string.bytes.fromBytes(bytes)
```

## `dart.string.bytes.toBytes(str)`

Encodes `str` as UTF-8 and returns a `Uint8List`.

This is a convenient bridge into other byte-oriented libraries such as
[`convert`](./convert.md) and [`crypto`](./crypto.md).

## `dart.string.bytes.fromBytes(bytes)`

Decodes bytes as UTF-8 and returns a Dart string.

Accepted inputs include:

- `Uint8List`
- a Lua array-style table of integers
- a Dart `List<int>` value exposed into the runtime

## Notes

- This library is UTF-8 oriented.
- If you need byte-preserving Latin-1 behavior, use `convert.latin1Encode()`
  and `convert.latin1Decode()` instead.
- The returned `Uint8List` can be passed directly into `crypto` and `convert`
  helpers.
