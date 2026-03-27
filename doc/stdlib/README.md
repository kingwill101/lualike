# Standard Library Reference

This directory contains hand-written reference notes for the libraries that
LuaLike registers by default.

## Table of Contents

- [base](./base.md)
  Global functions such as `assert`, `error`, `pcall`, `pairs`, and `type`.
- [package](./package.md)
  Module loading state, search paths, and searchers.
- [string](./string.md)
  String functions, formatting, packing, and method-style access.
- [table](./table.md)
  Table construction and mutation helpers.
- [math](./math.md)
  Numeric helpers and constants.
- [debug](./debug.md)
  Stack inspection, hooks, locals, upvalues, and tracebacks.
- [io](./io.md)
  File handles and default stream operations.
- [os](./os.md)
  Process, time, filesystem, and environment helpers.
- [utf8](./utf8.md)
  UTF-8 traversal and code point helpers.
- [convert](./convert.md)
  JSON, Base64, ASCII, and Latin-1 conversions.
- [crypto](./crypto.md)
  Hashing, HMAC, random bytes, and AES helpers.
- [logging](./logging_library.md)
  Structured logging support.
- [coroutine](./coroutine.md)
  Coroutine lifecycle helpers such as `create`, `resume`, `yield`, and
  `close`.
- [dart.string](./dart_string.md)
  Dart-backed string helpers that complement the Lua-style `string` library.
- [dart.string.bytes](./dart_string_bytes.md)
  Byte conversion helpers for `dart.string`.

## Notes

- These pages are descriptive reference material, not generated API docs.
- The source of truth for exact runtime behavior is the implementation under
  `pkgs/lualike/lib/src/stdlib/`.
- The standard-library registration flow is documented in
  [../guides/standard_library.md](../guides/standard_library.md).
