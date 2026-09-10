# love2d test instructions

These instructions apply to `pkgs/love2d/test`.

## Prefer direct LuaLike usage

- Create a `LuaLike` instance directly in the test.
- Use `final runtime = lualike.vm;` and pass that to `installLove2d(...)`.
- Prefer `lualike.execute('return ...')` for simple Lua expressions.
- Prefer `lualike.call('module.function', args)` for direct Dart-side function calls.
- If you already have a `Value`, call it directly or use `.unwrap()` for assertions.

## Avoid unnecessary wrappers

- Do not add file-local helper layers that only forward to shared helpers.
- Do not reintroduce custom `_call*`, `_resolve*`, or `_unwrap` shims unless the test truly needs a unique, file-specific behavior.
- Do not introduce new wrapper result types when plain Dart values, `List`s, or `Map`s will do.
- Treat `LuaResults` as internal-only; tests should prefer plain values and `.unwrap()`.

## Shared helper rule

- If a reusable helper is genuinely needed, add it to `test/test_support/lua_api_test_helpers.dart` instead of duplicating it in individual files.
- Keep helpers thin and predictable; prefer the shortest path from the test to the runtime.
