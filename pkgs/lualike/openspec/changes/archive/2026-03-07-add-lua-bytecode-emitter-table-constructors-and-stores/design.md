## Context

The direct `lua_bytecode` emitter already reads from tables and stores
simple identifiers, and the runtime already executes the relevant table
opcode families (`NEWTABLE`, `SETFIELD`, `SETTABLE`, `SETI`, `SETLIST`,
and `EXTRAARG`) for the supported subset. The next gap is source lowering:
table literals still fail during expression emission, and assignments still
reject anything other than identifiers.

This means the remaining work is mainly compiler/builder lowering and test
coverage, not a new runtime abstraction.

## Goals / Non-Goals

**Goals:**
- Emit supported table-constructor expressions directly to real
  `lua_bytecode`.
- Emit supported field/index assignment targets directly to real
  `lua_bytecode`.
- Reuse the existing AST -> `lua_bytecode` path without involving
  `lualike_ir`.
- Keep unsupported constructor/store forms explicitly diagnostic.

**Non-Goals:**
- Broaden this change into general table-metatable parity work; that stays
  in the runtime lane.
- Support every exotic constructor shape if it requires new runtime work
  outside the currently verified subset.

## Decisions

### Decision: Lower constructors through the real `NEWTABLE` / `SET*` families

The emitter will allocate a target register with `NEWTABLE`, then fill the
table with `SETFIELD`, `SETI`, `SETTABLE`, and `SETLIST` depending on the
constructor entry shape.

Why:
- That matches the runtime’s existing table opcode subset.
- It keeps emitted chunks close to upstream structure instead of inventing
  a custom constructor helper.

### Decision: Extend assignment-target lowering instead of adding a special store path

The emitter will generalize store-target resolution so assignment can emit
identifier, field, and index stores through one structured path.

Why:
- It keeps assignment lowering coherent.
- Function-definition and assignment stores can then share the same field
  and index machinery where appropriate.

### Decision: Start with the runtime-proven subset

The first slice should cover:
- contiguous array entries
- keyed field entries with identifier keys
- keyed index entries with supported expression keys
- ordinary `t.x = v` and `t[i] = v`

Why:
- Those are already exercised on the runtime side.
- They unlock the most ordinary source patterns without overreaching.

## Risks / Trade-offs

- [Constructor lowering drifts from stable luac shape] ->
  Mitigation: compare the stable `NEWTABLE` / `SET*` families against
  `luac55` fixtures where ordering is meaningful.
- [Generalized assignment-target lowering regresses identifier stores] ->
  Mitigation: keep identifier stores as the existing fast path and add
  focused regression tests.
- [Emitter accepts constructor forms outside the current runtime envelope] ->
  Mitigation: keep unsupported forms explicitly diagnostic with tests.
