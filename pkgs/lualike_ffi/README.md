# lualike_ffi

[![Pub Version](https://img.shields.io/pub/v/lualike_ffi)](https://pub.dev/packages/lualike_ffi)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)


`lualike_ffi` is the native backend used by lualike's runtime-declared FFI.
It loads ordinary shared libraries, resolves exported C symbols, and calls
them through signatures supplied at runtime.

The package deliberately has no dependency on the lualike interpreter. It can
therefore own the native build hook and libffi bridge without creating a
dependency cycle with the scripting runtime.

## Current support

- Linux hosts
- `void`, `bool`, signed and unsigned integers, `f32`, `f64`, pointers, and
  UTF-8 strings
- Explicit library close and closed-handle validation
- Runtime symbol signatures backed by libffi

The host must provide the libffi development library when building this
prototype. Structs, callbacks, variadic calls, and direct memory access are not
yet supported.

The backend calls ordinary C exports. It does not emulate Lua's C API or supply
a `lua_State`, so stock libraries exporting `luaopen_*` need a plain-C adapter.

## Safety

Native FFI executes code in the host process. Incorrect signatures, invalid
pointers, or untrusted libraries can corrupt memory or terminate the process.
The lualike CLI therefore keeps FFI disabled unless `--allow-ffi` is present.
