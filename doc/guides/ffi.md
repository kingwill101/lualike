# Native FFI

Lualike can load ordinary C shared libraries and call exported functions whose
signatures are declared by the script. Native access is disabled by default and
must only be enabled for trusted scripts:

```sh
lualike --allow-ffi script.lua
```

## Binding a function

Load a library and bind symbols incrementally:

```lua
local ffi = require("ffi")
local libc = ffi.load("libc.so.6")
local abs = libc:func("abs", "i32", {"i32"})

print(abs(-42))
libc:close()
```

The definition-table form binds several functions together:

```lua
local ffi = require("ffi")
local libc = ffi.open("libc.so.6", {
  strlen = {
    arguments = {"string"},
    result = "u64",
  },
})

print(libc.functions.strlen("lualike"))
libc:close()
```

`ffi.suffix` contains the platform shared-library suffix, and `ffi.available`
reports whether the current runtime includes a supported native backend.

## Types

The initial ABI supports these declaration names:

- `void` for function results only
- `bool`
- `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, and `u64`
- `f32` and `f64`
- `pointer` for opaque addresses
- `string` for zero-terminated UTF-8 strings

Strings passed to native functions remain valid only for the duration of the
call. Strings returned by native functions are copied immediately. Lualike does
not take ownership of returned pointers.

## Lifetime and safety

Calling `lib:close()` invalidates every function bound from that library.
Library handles are also closed during garbage collection, but explicit close
is preferred when the lifetime is known.

An incorrect declaration can corrupt memory or terminate the process. FFI is
not a sandbox boundary and grants scripts the same native access as the host
process. Structs, callbacks, variadic functions, and arbitrary memory reads and
writes are intentionally outside the first implementation.

The current native bridge is available on Linux. Other platforms retain the
same API but report that the capability is unavailable.

## Lua C modules

This API calls ordinary exported C functions. It does not provide Lua's C API
or a compatible `lua_State`, so a stock module exporting `luaopen_example`
cannot be loaded directly. Such a library needs a plain-C adapter whose
functions use the supported declarations above. Supporting the Lua C module
ABI is separate future work and does not change `package.loadlib` today.
