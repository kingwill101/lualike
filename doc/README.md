# LuaLike Documentation

This directory contains the hand-written guides and reference material for the
LuaLike package and runtime.

## Table of Contents

- [Guides](./guides/README.md)
  Task-oriented documentation for embedding LuaLike, extending it from Dart,
  and understanding core runtime concepts.
- [Standard library reference](./stdlib/README.md)
  Per-library notes for the built-in `base`, `string`, `table`, `math`,
  `debug`, `io`, `os`, `utf8`, `package`, `convert`, `crypto`, `logging`,
  `coroutine`, and `dart.string` libraries.

## Recommended reading paths

If you are embedding LuaLike in an app:

1. Read [Using LuaLike as a Dart Library](./guides/dart_library_usage.md).
2. Read [Value handling](./guides/value_handling.md).
3. Read [Error handling](./guides/error_handling.md).

If you want to extend LuaLike from Dart:

1. Read [Writing Native Functions in Dart](./guides/writing_builtin_functions.md).
2. Read [Builder-style library pattern](./guides/BUILDER_PATTERN.md).
3. Read [Standard library architecture](./guides/standard_library.md).

If you want to understand the built-in libraries:

1. Start with [Standard library reference](./stdlib/README.md).
2. Open the specific library page you need.
3. Cross-check the implementation under `pkgs/lualike/lib/src/stdlib/` when
   you need the latest behavior.

## Notes

- The package README is the best overview for the public API surface.
- The docs in this folder focus on concepts, extension points, and runtime
  behavior rather than generated API listings.
- Generated API docs live under `pkgs/lualike/doc/api/` when you run
  `dart doc`.
