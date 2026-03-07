# Add Bytecode Support for Upvalue Writes and Method Definitions

## Why
- After landing closures/varargs, bytecode execution still falls back to the AST interpreter when closures assign to captured locals or when `function t:foo(...)` style method definitions appear. Those flows rely on `SETUPVAL`, `SETTABUP`, and implicit `self` handling that the compiler currently skips.
- Real Lua scripts routinely mutate upvalues (e.g. accumulators in closures) and define methods via table fields. Missing coverage makes bytecode mode unusable for idiomatic modules even though read-only captures now work.
- Implementing upvalue writes and method lowering is a prerequisite for broader opcode work (`SELF`, metamethod dispatch) and keeps bytecode parity improving in tangible user-facing scenarios.

## What Changes
- Detect assignments targeting captured locals or `_ENV`/table methods during bytecode lowering and emit the appropriate `SETUPVAL`, `SETTABUP`, or table store opcodes while preserving implicit `self` semantics.
- Extend the VM to support writing through captured upvalues and `_ENV`, ensuring mutations propagate across frames just like the interpreter.
- Backfill compiler/VM/executor tests covering mutated closures, method definitions, and `_ENV` updates in bytecode mode.

## Impact
- Bytecode mode will handle Lua libraries that rely on closures mutating state and on method declarations, reducing fallbacks to the AST interpreter.
- Lays groundwork for future opcode additions (e.g. `SELF`, `CLOSE`) by ensuring capture semantics are already correct.
- Adds higher confidence regression coverage around closure lifetimes and environment mutation.
