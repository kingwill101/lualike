## Context

The direct `lua_bytecode` emitter already lowers simple top-level function
definitions by compiling a child prototype and storing the closure into a
simple identifier target. The next gap is `FunctionDef` names that include
table-path segments (`function t.add(...)`) or method syntax
(`function t:inc(...)`).

The runtime and AST interpreter already support the semantic pieces this
needs:
- table-path resolution through ordinary `GET*` / `SET*` behavior
- method bodies receiving an implicit `self`
- emitted closures and upvalues through the existing builder/runtime stack

So this change is a compiler lowering problem, not a new runtime opcode
problem.

## Goals / Non-Goals

**Goals:**
- Lower dotted function-name paths directly to real `lua_bytecode`.
- Lower method-style definitions with the correct implicit `self`
  parameter.
- Reuse the existing source -> `lua_bytecode` path without routing through
  `lualike_ir`.
- Keep unsupported function-definition forms explicitly diagnostic if they
  still fall outside the emitted subset.

**Non-Goals:**
- Introduce dynamic or computed function-name targets outside the parser’s
  `FunctionName` model.
- Expand the change into unrelated emitter gaps such as broader goto
  visibility or table-constructor coverage.

## Decisions

### Decision: Lower function-name paths as ordinary table traversal plus a final store

The emitter will compile the table path (`t`, `t.a`, `t.a.b`) into a
register using the existing identifier/table-field emission helpers, then
store the emitted closure into the final field with `SETFIELD`.

Why:
- That matches the already-supported table access/store subset.
- It avoids inventing a special function-definition runtime path.

### Decision: Preserve method semantics by synthesizing an implicit `self` parameter

For `function t:inc(...) end`, the child prototype will be emitted with
`self` prepended to its parameter list if it is not already the first
parameter.

Why:
- That matches the existing interpreter and IR semantics.
- It keeps method bodies compatible with the already-supported call and
  upvalue model.

### Decision: Keep simple-function lowering as the fast path

Plain `function name(...) end` definitions will continue using the current
simple identifier/upvalue/global store path.

Why:
- It is already correct and small.
- Complex-name support should extend the subset, not regress the simple
  case.

## Risks / Trade-offs

- [Method bodies receive the wrong parameter order] ->
  Mitigation: validate method definitions through source-engine tests and
  emitted child-prototype assertions.
- [Qualified path lowering diverges from Lua for stable opcode shape] ->
  Mitigation: add oracle-backed opcode checks only for the stable
  `GET*` / `SETFIELD` / `CLOSURE` families instead of brittle full-chunk
  equality.
- [Emitter broadens too far and silently accepts still-unsupported forms] ->
  Mitigation: keep unsupported function-definition families explicitly
  diagnostic in tests.
