# The Standard Library in LuaLike

This guide explains how LuaLike organizes, registers, and exposes its built-in
libraries.

## Table of Contents

- [Overview](#overview)
- [How registration works](#how-registration-works)
- [Global versus namespaced libraries](#global-versus-namespaced-libraries)
- [Built-in libraries](#built-in-libraries)
- [String method access](#string-method-access)
- [Package loading and lazy initialization](#package-loading-and-lazy-initialization)
- [Extending the standard library](#extending-the-standard-library)
- [Where to look next](#where-to-look-next)

## Overview

LuaLike ships a built-in library set that is registered for every runtime.

The runtime owns a `LibraryRegistry`, and the standard initialization path
registers concrete `Library` implementations for modules such as:

- `base`
- `package`
- `string`
- `table`
- `math`
- `debug`
- `io`
- `os`
- `utf8`
- `convert`
- `crypto`
- `logging`
- `dart.string`
- `coroutine`

The registration code lives in `pkgs/lualike/lib/src/stdlib/init.dart`, and the
individual implementations live under `pkgs/lualike/lib/src/stdlib/`.

## How registration works

The runtime initializes the standard library in three steps:

1. Register each `Library` implementation with the runtime's
   `LibraryRegistry`.
2. Eagerly initialize global libraries such as the base library.
3. Install lazy stubs for namespaced libraries so they are initialized on first
   access.

That means namespaced libraries like `string` or `math` do not need to do all
their work up front. The stub table resolves the real library through the
registry when a script first touches it.

## Global versus namespaced libraries

LuaLike models built-ins in two ways:

- Global libraries
  These register functions directly into `_G`. The base library is the main
  example.
- Namespaced libraries
  These register a table under a library name such as `string`, `table`, or
  `math`.

This distinction is controlled by the `Library.name` getter:

- return an empty string for a global library
- return a non-empty name for a namespaced library

## Built-in libraries

The built-in library set currently includes:

### Global library

- [base](../stdlib/base.md)
  Global helpers such as `assert`, `error`, `pcall`, `pairs`, `rawequal`,
  `rawget`, `rawset`, `tonumber`, and `type`.

### Module-style libraries

- [package](../stdlib/package.md)
  Module loading state, search paths, and searchers.
- [string](../stdlib/string.md)
  String manipulation, formatting, and packing helpers.
- [table](../stdlib/table.md)
  Table mutation and traversal helpers.
- [math](../stdlib/math.md)
  Numeric functions and constants.
- [debug](../stdlib/debug.md)
  Stack inspection, hooks, locals, upvalues, and tracebacks.
- [io](../stdlib/io.md)
  File handles and default stream operations.
- [os](../stdlib/os.md)
  Process, time, filesystem, and environment helpers.
- [utf8](../stdlib/utf8.md)
  UTF-8 traversal and code point helpers.
- [convert](../stdlib/convert.md)
  JSON, Base64, ASCII, and Latin-1 conversions.
- [crypto](../stdlib/crypto.md)
  Hashing, HMAC, random bytes, and AES helpers.
- [logging](../stdlib/logging_library.md)
  Structured logging support.
- [dart.string](../stdlib/dart_string.md)
  Dart-backed string helpers that complement the Lua-style `string` library.
- [dart.string.bytes](../stdlib/dart_string_bytes.md)
  Byte conversion helpers for `dart.string`.
- [coroutine](../stdlib/coroutine.md)
  Coroutine creation, yielding, resuming, wrapping, and closing.

## String method access

The `string` library is special because scripts can use it in two styles:

```lua
string.len("hello")
"hello":len()
```

LuaLike supports the second form by wiring string values through a metatable
that resolves missing lookups against the `string` library table.

That same metatable-based approach is the pattern used by builder-style
extension APIs in Dart.

## Package loading and lazy initialization

LuaLike also wires library registration into `package.loaded` so `require()`
can observe which libraries and modules are already available.

The initialization path:

- creates or refreshes `_G`
- installs lazy library placeholders
- keeps `package.loaded` synchronized when a library resolves
- refreshes string metatable state when the `string` library is attached

This is why library registration belongs in the runtime, not in ad hoc
environment setup code.

## Extending the standard library

To add your own library:

1. Create a class that extends `Library`.
2. Implement `registerFunctions()` using `LibraryRegistrationContext`.
3. Register it through `runtime.libraryRegistry.register(...)`.
4. Initialize it with `initializeLibrary()` or `initializeLibraryByName()`.

For public extension code, import `package:lualike/library_builder.dart`.

See:

- [Writing Native Functions in Dart](./writing_builtin_functions.md)
- [Building a Lua-like Library with Builder Interface](./BUILDER_PATTERN.md)

## Where to look next

- [Standard library reference index](../stdlib/README.md)
- `pkgs/lualike/lib/src/stdlib/init.dart`
- `pkgs/lualike/lib/src/stdlib/library.dart`
