# Lua Pattern Compiler Migration

This document tracks the remaining tasks required to fully switch the `lualike` string library over to the new PetitParser‑based pattern compiler.

## Current Status

The new compiler lives in `lib/src/lua_pattern_compiler.dart` and is used by `string.find`, `string.match`, `string.gmatch`, and `string.gsub` when available. It supports:

- Character classes like `%a`, `%d`, and `%w` including `%x` escape handling
- Bracket sets with ranges and class escapes
- Quantifiers (`*`, `+`, `?`, `-`) with greedy and non‑greedy behaviour
- Captures with automatic numbering and back references `%1` … `%9`
- Anchors (`^` and `$`)
- Balanced matches `%bxy`
- Frontier patterns `%f[set]`

A dedicated test suite (`test/lua_pattern_compiler_test.dart`) exercises these features alongside the existing PM tests.

## Work Remaining

- **Backtracking semantics** – Some complex patterns from the Lua test suite still fail because our parser does not implement full backtracking. The old implementation used manual backtracking; the PetitParser version must replicate Lua’s behaviour in these edge cases.
- **Error handling parity** – Ensure malformed patterns raise the same error messages as the Lua interpreter. Some messages currently differ or are missing context.
- **Locale awareness** – Lua’s pattern classes depend on locale for `%a`, `%l`, `%u`, and related sets. The compiler currently uses fixed ASCII ranges.
- **Zero‑length match rules** – `gmatch` and `gsub` should not accept a zero‑length match immediately after the previous one. Add tests covering this rule.
- **Integration cleanup** – Remove the old pattern helpers once the new compiler passes all PM tests and the standard library behaves like Lua.
- **Documentation** – Update user‑facing guides to describe the new compiler and differences from Lua where applicable.

## Next Steps

1. Expand the test suite with additional examples from the Lua reference tests, verifying results against the Lua interpreter.
2. Implement full backtracking to handle patterns that currently get stuck or stop early.
3. Review all string library functions to ensure they call the new compiler and return captures correctly.
4. After all tests pass, remove the legacy pattern code and enable the compiler by default.

