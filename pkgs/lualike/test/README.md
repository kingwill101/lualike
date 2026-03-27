# Test Organization

The test suite is split by artifact family first, then by functional area.
That split matters for the bytecode migration:

- `AST / interpreter semantics`: the interpreter directories under
  `test/interpreter/`, plus the broader semantic suites in `test/unit/`
  and `test/stdlib/`
- `lualike_ir`: the dedicated compiler/VM/runtime tests in `test/ir/`,
  the executor coverage in
  `test/interpreter/core/executor_ir_test.dart`, and the AST-vs-IR parity
  coverage in `test/unit/executor_ir_parity_test.dart`
- `Legacy AST chunk transport`: `test/stdlib/binary_chunk_test.dart`
  covers the old `string.dump` / `load` transport that wraps AST-backed
  functions in an internal binary-like format. These tests do not claim
  upstream Lua bytecode compatibility.
- `lua_bytecode`: real upstream-compatible chunk parsing, disassembly,
  runtime-routing, and execution tests under `test/lua_bytecode/`

## Directory Structure

- `test/ir/` - `lualike_ir` compiler, VM, runtime, and serialization tests
- `test/interpreter/` - AST interpreter behavior and interpreter-only fast paths
- `test/stdlib/` - stdlib behavior and legacy AST chunk transport coverage
- `test/interop/` - Dart/lualike interop behavior
- `test/unit/` - shared semantic and parity coverage
- `test/lua_bytecode/` - real upstream Lua chunk parser, disassembler,
  routing, and execution tests

## Artifact-Family Commands

```bash
# All lualike_ir tests
dart test test/ir test/interpreter/core/executor_ir_test.dart \
  test/unit/executor_ir_parity_test.dart

# Legacy AST chunk transport only
dart test test/stdlib/binary_chunk_test.dart

# Real upstream Lua bytecode tests
dart test test/lua_bytecode
```

## Tag-Based Commands

Artifact-family tags are declared in `dart_test.yaml`:

- `ir`
- `legacy_chunk`
- `lua_bytecode`
- `shared_semantics`

Examples:

```bash
# Run IR-only contract tests
dart test --tags ir

# Run the legacy AST chunk transport suite
dart test --tags legacy_chunk

# Run shared AST-vs-IR parity checks
dart test --tags shared_semantics
```

## Functional Area Commands

```bash
# Run all tests
dart test

# Run interpreter tests
dart test test/interpreter

# Run stdlib tests
dart test test/stdlib

# Run interop tests
dart test test/interop
```

```bash
# Run focused coroutine coverage
dart test test/stdlib/coroutine_library_test.dart
```

## Guidance

- Use `test/ir/` and the `ir` tag for internal opcode, compiler, VM, and IR
  runtime behavior.
- Use `test/stdlib/binary_chunk_test.dart` and the `legacy_chunk` tag for
  the pre-IR AST transport path.
- Do not treat passing IR tests or legacy chunk tests as evidence of real
  upstream Lua bytecode compatibility.
- Use `test/lua_bytecode/` only for real chunks produced by the tracked
  upstream Lua release line. When in doubt, generate fixtures with
  `luac55` or the matching `luac` on `PATH` and compare behavior against
  the vendored `third_party/lua` source line.
- Use `test/stdlib/coroutine_library_test.dart` for coroutine lifecycle
  coverage. GC regressions there should be expressed through weak tables
  plus `collectgarbage('collect')`, not by relying on internal runtime
  state.
- Keep the artifact families honest in docs and tests:
  `string.dump`/legacy AST transport is not `lualike_ir`, and neither of
  those is `lua_bytecode`.
