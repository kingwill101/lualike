## Context

The current architecture split is correct: AST/interpreter, `lualike_ir`,
and `lua_bytecode` are separate. What is still missing is a source backend
for `lua_bytecode`. The runtime can execute real chunks, but there is no
compiler that emits them from lualike source.

This change exists to build the foundation only. It is not the full source
emitter. It should create the compiler boundary, shared semantic analysis,
chunk/prototype builders, and a minimal end-to-end compile path for trivial
programs.

## Goals / Non-Goals

**Goals:**
- Define the direct AST -> shared analysis -> `lua_bytecode` lowering path.
- Create emitter and chunk-builder primitives suitable for later expression
  and control-flow coverage.
- Make the foundation testable with a minimal emitted subset.

**Non-Goals:**
- Reusing `lualike_ir` instructions or lowering through the IR VM.
- Implementing the full expression set.
- Implementing control flow, loops, or closures in this change.
- Making `lua_bytecode` the default source engine in this change.

## Decisions

### Decision: Lower source directly to `lua_bytecode`

Source compilation should lower from AST through shared semantic analysis
straight into `lua_bytecode`.

Why:
- Real Lua bytecode needs tighter control over registers, jumps, and chunk
  layout than the IR abstraction provides.
- Lowering from IR into bytecode would effectively duplicate compiler work.

### Decision: Share semantic analysis, not emitted instructions

The AST front-end should eventually produce reusable semantic facts such as
locals, upvalues, close slots, and vararg shape. The backend instruction
selection remains emitter-specific.

Why:
- The semantic facts are common.
- The emitted instruction streams are not.

### Decision: Prove the foundation with executable minimal chunks

The foundation should not stop at "we can build a proto in memory." It
should compile a minimal supported subset and run it through the existing
`lua_bytecode` runtime.

Why:
- That catches chunk-layout mistakes early.
- It gives later emitter changes a reliable base to extend.

## Risks / Trade-offs

- [Shared semantic analysis may grow too abstract too early] -> Mitigation:
  only model the facts needed by the first emitted subset.
- [A minimal emitter can tempt premature engine integration] -> Mitigation:
  keep source-engine integration out of this change.

## Handoff

When this change is complete, continue with
`add-lua-bytecode-emitter-expressions`.
