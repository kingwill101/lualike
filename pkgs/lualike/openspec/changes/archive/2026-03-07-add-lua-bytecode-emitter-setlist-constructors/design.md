## Context

The runtime already executes `SETLIST` and `EXTRAARG`, and the direct
emitter already handles basic table constructors by lowering them through
`NEWTABLE` and the supported `SET*` store families. The remaining gap is
the constructor shapes that upstream lowers differently: larger contiguous
array batches and a final open-result call entry that expands into the
tail of the constructor.

This is still an emitter-side gap, not a new runtime abstraction. The
main risk is emitting table-constructor bytecode that looks executable but
does not match the runtime and oracle-backed subset.

## Goals / Non-Goals

**Goals:**
- Emit supported table constructors through real `SETLIST` / `EXTRAARG`
  sequences when the array portion needs them.
- Emit supported trailing open-result constructor entries directly to real
  `lua_bytecode`.
- Keep unsupported constructor shapes explicitly diagnostic.
- Reuse the direct AST -> `lua_bytecode` path without involving
  `lualike_ir`.

**Non-Goals:**
- Expand this change into general constructor parity for every exotic
  mixed table shape if it needs new runtime work.
- Broaden this slice into unrelated goto or closure visibility work.

## Decisions

### Decision: Buffer contiguous array entries before emitting stores

The emitter will collect contiguous array-style constructor entries and
flush them through `SETLIST` instead of lowering every array item as a
separate `SETI`.

Why:
- That matches the upstream structure for array-heavy constructors.
- It is the only way to support a trailing open-result call cleanly.

Alternative considered:
- Continue emitting only `SETI` for every array item.
  Rejected because it cannot express the trailing multi-result constructor
  shape without inventing a non-Lua helper path.

### Decision: Support only a final open-result constructor entry

The emitted subset will support a trailing call or method call entry in a
constructor, but not an open-result entry in the middle of the constructor.

Why:
- That matches the normal Lua source contract for constructor expansion.
- It keeps register and top-of-stack handling local to the constructor
  tail instead of opening up a much broader multi-result lowering problem.

Alternative considered:
- Attempt to normalize any open-result entry by forcing it to one result.
  Rejected because that changes Lua semantics.

### Decision: Keep keyed entries on the existing direct store path

Field and computed-key entries will keep using `SETFIELD` / `SETTABLE`
  / `SETI` directly, while the array portion uses buffered `SETLIST`
  flushing.

Why:
- It keeps the new logic focused on the array/open-result part of the
  constructor.
- It reuses the already tested store-target lowering from the previous
  constructor/store change.

## Risks / Trade-offs

- [Buffered constructor lowering drifts from stable `luac55` shape] ->
  Mitigation: compare relevant `NEWTABLE` / `SETLIST` / `EXTRAARG`
  families against `luac55` fixtures where ordering is meaningful.
- [Open-result constructor lowering corrupts register/top handling] ->
  Mitigation: add focused source-engine tests for `{f()}` and mixed
  prefixes like `{1, g()}`.
- [Emitter starts accepting constructor forms beyond the supported subset]
  -> Mitigation: keep mid-constructor open-result entries and other
  unsupported mixes explicitly diagnostic with tests.
