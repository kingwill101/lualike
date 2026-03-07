# `lua_bytecode` Tests

This directory is for the real upstream-compatible chunk work.

Tests added here must target upstream-compatible artifacts only:

- exact chunk/header parsing
- packed instruction decoding
- disassembly of `luac` output
- direct AST -> `lua_bytecode` emitted chunks for the supported emitter
  subset
- execution of real upstream Lua chunks for the tracked vendored release line
- runtime-routing checks that prove upstream chunks do not fall through to
  `lualike_ir` or legacy AST transport

Do not place `lualike_ir` or legacy AST chunk transport tests in this
directory.

## Oracle Workflow

- Prefer fixtures compiled with the tracked upstream binary (`luac55` in
  `Downloads/` or `luac55` / `luac` on `PATH`).
- When behavior is unclear, compare both the chunk listing (`luac -l -l`)
  and execution result against upstream before changing tests.
- Keep fixtures small. Each test should isolate one VM contract such as
  compare+jump lowering, `CLOSURE`/upvalues, `FORPREP`/`FORLOOP`,
  `TFOR*`, `VARARG`, arithmetic/bitwise/concatenation behavior,
  `SELF`/method-call register layout, or `EXTRAARG` consumers.

## Current Runtime Envelope

The executable `lua_bytecode` VM currently has oracle-backed coverage for:

- globals, compare+jump control flow, closures, numeric `for`, generic `for`,
  vararg flow, open-result `CALL`/`RETURN`/`TAILCALL` behavior, and routing of
  real upstream chunks
- arithmetic, bitwise, unary, and concatenation opcode families emitted by
  `luac55`
- `MMBIN*` metamethod fallback for supported arithmetic families
- raw comparison semantics plus the supported `__eq`, `__lt`, and `__le`
  metamethod subset for direct and immediate order comparisons
- table access/store semantics including table/function `__index` and
  `__newindex`, `SELF`, and large `SETLIST` / `EXTRAARG` constructors
- supported table length behavior for contiguous and prefix-boundary tables,
  dictionary-style tables, and table `__len`
- supported `CLOSE` / `TBC` / to-be-closed execution paths, including generic
  `for` close slots and invalid close-value diagnostics
- coroutine create/resume/yield/status/wrap/close behavior for the current
  supported bytecode subset, including source-emitted and upstream chunk
  coverage

Still unsupported in the runtime subset:

- the remaining close-edge behavior beyond the current supported subset
- broader table edge cases and `NEWTABLE` hash-size-hint parity beyond the
  current oracle-backed subset
- broader exotic type-metatable comparison cases outside the current
  table-focused oracle fixtures
- broader unsupported opcode families outside the current oracle-backed VM
  envelope

The current source-emitter subset is intentionally smaller than the runtime
envelope. It currently covers:

- top-level `return` with literal, local, global, unary, binary,
  concatenation, table-access, method-call, and supported function-call
  expressions
- top-level `local` declarations initialized from supported expressions,
  including fixed-result assignment from a final call expression
- top-level call expression statements for supported call families
- open-result `return` lowering when the final returned expression is a
  supported call
- identifier assignment plus supported field/index stores and the current
  supported table-constructor subset, including `SETLIST`-backed array
  batches and trailing open-result constructor entries
- the first structured control-flow slice: `if`, `while`, numeric `for`,
  generic `for`, `repeat ... until`, and `break`, labels, and `goto`
- supported nested function literals, `local function`, and simple
  and qualified `function name(...)` lowering with captured local upvalues,
  including dotted and method-style function names
- an opt-in source-engine path through `EngineMode.luaBytecode` and
  `--lua-bytecode`, plus real `string.dump` / `load` round-tripping for
  emitted functions inside the supported subset

Still intentionally unsupported in the source-emitter subset:

- broader goto visibility edge cases outside the current structured subset

Unsupported source subsets must fail explicitly from the emitter/runtime
path. They should not silently fall back to AST or `lualike_ir` execution.

The emitter must stay direct AST -> `lua_bytecode`; do not route it through
`lualike_ir`.

When adding a new family, either land executable support with an upstream
fixture or keep it explicitly unsupported with a diagnostic test.
