# `utf8` Library

The `utf8` library provides UTF-8 aware traversal and code-point helpers.

## Table of Contents

- [Overview](#overview)
- [`utf8.char(...)`](#utf8char)
- [`utf8.codes(s, ...)`](#utf8codess-)
- [`utf8.codepoint(s, [i, [j]])`](#utf8codepoints-i-j)
- [`utf8.len(s, [i, [j]])`](#utf8lens-i-j)
- [`utf8.offset(s, n, [i])`](#utf8offsets-n-i)
- [`utf8.charpattern`](#utf8charpattern)
- [Notes](#notes)

## Overview

Use `utf8` when you want Unicode-aware traversal rather than raw byte slicing.

The library accepts both plain LuaLike strings and `LuaString` values, and it
preserves byte-oriented behavior where that matters for compatibility.

## `utf8.char(...)`

Converts one or more integer code points into a UTF-8 string value.

Passing no arguments returns an empty string, which matches Lua behavior.

## `utf8.codes(s, ...)`

Returns an iterator over UTF-8 characters in `s`.

LuaLike supports the common iterator shape and also supports the extended
arguments used by the test suite for start and end positions plus optional lax
parsing.

## `utf8.codepoint(s, [i, [j]])`

Returns one or more code points for the UTF-8 characters that begin in the
requested byte range.

Positions are byte positions, not Dart string indexes.

## `utf8.len(s, [i, [j]])`

Returns the number of UTF-8 characters in the requested byte range.

On invalid UTF-8, it follows Lua-style failure behavior rather than silently
normalizing the input.

## `utf8.offset(s, n, [i])`

Returns the byte position of the `n`th UTF-8 character relative to a starting
position.

## `utf8.charpattern`

A pattern value that matches exactly one UTF-8 byte sequence.

LuaLike stores this as a byte-preserving `LuaString`, which is important for
pattern compatibility.

## Notes

- The `utf8` library is byte-position based even though it is Unicode aware.
- If you need Dart-style string indexing, use [`dart.string`](./dart_string.md)
  instead.
- If you need raw byte conversion, use [`dart.string.bytes`](./dart_string_bytes.md).
