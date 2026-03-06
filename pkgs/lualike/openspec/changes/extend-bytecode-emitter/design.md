# Design – Extend Bytecode Emitter and VM Baseline

This change widens the first bytecode slice so the compiler/VM can evaluate arithmetic expressions that depend on runtime values.

## Scope
- **Compiler**: Support `Identifier` and `BinaryExpression` nodes. Identifiers load globals from the active environment via `GETTABUP`; binary arithmetic lowers to register-based `ADD`/`SUB`/`MUL`/`DIV` opcodes. Register allocation favours reusing the left operand register for results.
- **VM**: Recognise the additional opcodes and perform numeric coercion consistent with current interpreter behaviour. The VM reuses existing helper logic from the loop VM for arithmetic and environment lookups.
- **Execution Path**: `executeCode` already accepts an engine mode; no behavioural change except that bytecode mode now covers more constructs.

## Non-goals
- Locals/upvalues, metamethod dispatch, comparisons, control flow, or table constructors.
- VM stack frame/call support beyond literal returns.

## Open Questions
- Future work must decide how to represent locals/register allocation for statements (e.g., assignments). This design keeps globals-only resolution for now.
