## Why

Once the emitter foundation exists, it still will not be useful until it
can compile everyday expressions. The next slice should add the expression
families that map cleanly onto the already-supported runtime subset.

## What Changes

- Extend the `lua_bytecode` emitter to compile literals, locals, globals,
  unary/binary expressions, concatenation, table access, method selection,
  and supported call expressions.
- Keep emitted register and open-result behavior aligned with real upstream
  chunk patterns for the supported subset.
- Add parser/disassembly/execution tests for emitted expression chunks.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: extend the foundation subset to cover the first
  practical expression families.

## Impact

- Affected code: emitter instruction selection, register allocation, chunk
  builder support, and emitter tests
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: emitted-chunk tests plus behavior comparisons against source
  and `luac55`
