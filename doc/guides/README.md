# Guides

The guides in this directory explain how to use and extend LuaLike from Dart.

## Table of Contents

- [Using LuaLike as a Dart Library](./dart_library_usage.md)
  Start here for embedding scripts, choosing an engine, exposing Dart
  functions, and parsing source.
- [Writing Native Functions in Dart](./writing_builtin_functions.md)
  Explains the low-level extension surface for builtins and library functions.
- [Building a Lua-like Library with Builder Interface](./BUILDER_PATTERN.md)
  Shows how to expose builder-style objects and method chaining through
  metatables.
- [The Standard Library in LuaLike](./standard_library.md)
  Explains how the built-in libraries are organized and registered.
- [Value handling](./value_handling.md)
  Covers LuaLike value types and how they map back to Dart.
- [Error handling](./error_handling.md)
  Covers `error`, `pcall`, `xpcall`, and common patterns.
- [Metatables and metamethods](./metatables.md)
  Covers custom behavior for tables and values.
- [Number handling](./number_handling.md)
  Covers numeric semantics and `NumberUtils`.
- [String handling](./string_handling.md)
  Covers `LuaString`, byte semantics, and string interop.

## Suggested order

For new package users:

1. [Using LuaLike as a Dart Library](./dart_library_usage.md)
2. [Value handling](./value_handling.md)
3. [Error handling](./error_handling.md)

For runtime extenders:

1. [Writing Native Functions in Dart](./writing_builtin_functions.md)
2. [Building a Lua-like Library with Builder Interface](./BUILDER_PATTERN.md)
3. [The Standard Library in LuaLike](./standard_library.md)
