# IR Hardening Backlog

## Context

The IR layer is now the optimization boundary and the bytecode VM remains a
thin executor. The IR-to-bytecode contract is register-safe and debug-correct
for the current compatibility and Dart test suites. The production
`--lua-bytecode` and `--compile` paths use the full optimized pipeline by
default.

This file tracks optional hardening and follow-up work. Its unchecked items are
not prerequisites for the current production pipeline.

Authoritative decisions: [`doc/decisions.md`](../../doc/decisions.md) (IR
contract, official bytecode locals, and SSA safety notes).

## Approach

1. IR/SSA own optimization and shape decisions.
2. Bytecode lowering only serializes finalized IR.
3. VM stays thin: dispatch, registers, explicit slow paths.
4. Debug metadata must survive serialize → parse → execute.

## Completed baseline (through 2026-07-14)

- [x] Document IR contract (optimize → lower mechanically → execute thinly).
- [x] Infer local registers after parse (`inferLocalRegisters`).
- [x] Force main `lineDefined = 0` in IR→bytecode lowering.
- [x] Coalesce: multi-reg CALL/RETURN reads + interference on MOVE.
- [x] GVN: invalidate value numbers when registers are redefined.
- [x] DCE: pin named debug-local registers.
- [x] SCCP: only rewrite foldable ops; kill constants on redef.
- [x] Regression tests: `test/lua_bytecode/local_register_inference_test.dart`.
- [x] Dartdoc / comments on the above so we do not re-break them.
- [x] Register budget validation before lower (`register_budget.dart`).
- [x] `--lua-bytecode` / `--compile` / `runAst` share
      `CompilePipelineConfig.luaBytecodeOptimized` (IR+SSA by default).
- [x] Upstream suite: `locals.lua` / `db.lua` pass under `--lua-bytecode`.
- [x] Jump compact after IR/bytecode deletes (`instruction_compact` +
      peephole keeps `JMP 0` after TEST/comparisons).
- [x] SSA/coalesce: TEST reads A; EQI/eqK/*I read B; no folded Map→LOADNIL.
- [x] Const-arg inlining snapshots fold results so function bodies stay
      unspecialized.
- [x] VM sync path uses `signedB` for EQI/LTI/… immediates.
- [x] Live global env for top-level pipeline chunks.
- [x] Full soft-mode suite green under default IR+SSA `--lua-bytecode`.
- [x] Precompiled binary: header sniff only (no extension); direct VM path
      in CLI; `--compile` requires `-o`.
- [x] Property-based fuzz coverage for deep expressions, large parameter lists,
      many locals, and register-budget validation (`test/fuzz_test.dart`).
- [x] Full compatibility gate: 30/30 on AST, IR, and lua-bytecode.
- [x] Audit every IR-to-bytecode expansion and metadata transformation.
- [x] Make root `_ENV` explicit in finalized IR instead of synthesizing it
      during lowering.
- [x] Reserve lowering scratch slots from actual expansions (0, 1, or 2), while
      retaining the conservative two-slot compiler budget.
- [x] Reject malformed table, concat, root-upvalue, and jump shapes rather than
      silently normalizing them.
- [x] Harden function inlining as a disabled, conservative subset with
      operand-role remapping, caller metadata relocation, fresh registers, and
      independent per-candidate register-budget checks.
- [x] Harden loop unrolling as a disabled, strip-debug-only subset with finite
      numeric bounds, a conservative body whitelist, and per-iteration slot
      reuse.
- [x] Make metatable folding an explicit analysis-only extension point; the
      opt-in flag cannot annotate `setmetatable` calls or change runtime
      semantics until identity and mutation are modeled.

## Optional hardening

### 1. Transform-specific register budgets

- Escape analysis and function inlining both skip individual transformations
  that cannot stay within the bytecode budget. New register-allocating passes
  must follow the same rule instead of relying on the final validator.

### 2. Function-inlining enablement

- Keep `enableFunctionInlining` false in production until constant-pool and
  capture remapping, control-flow-aware PC relocation, and complete debug-frame
  semantics are implemented.
- Benchmark representative call-heavy programs before enabling it. Removing a
  call is not sufficient if fresh slots and duplicated bodies increase runtime
  or serialized size.

### 3. Keep lowering mechanical

- The expansion and metadata audit is complete. New IR opcodes must document
  why an expansion is mechanically required and include boundary tests.
- Prefer specialized opcodes decided in IR over VM inference.

### 4. Loop-unrolling enablement

- Keep `enableLoopUnrolling` false in production. Debug-preserving builds and
  bodies containing non-local control flow, closures, nested loops, attributed
  locals, or declarations with identity stay on the normal loop path.
- Before considering default enablement, define a profitability policy that
  accounts for serialized size and instruction-cache cost, represent duplicated
  debug scopes exactly, and benchmark a broader loop corpus. The current
  fixture runs faster but emits more instructions and bytes.

### 5. Metatable-folding enablement

- Keep `enableMetatableFolding` behavior-neutral until analysis models lexical
  binding resolution, table/metatable aliases and identity, mutation epochs,
  and metamethod lookup at each operation.
- Require oracle coverage for shadowed `setmetatable`, protected metatables,
  all foldable metamethod families, weak/finalizer metatables, and mutation
  across calls before introducing even a narrow transform.

### 6. Debug metadata edge cases

- Add a private trailing-register extension only if a minimal non-stack local
  layout proves stack inference insufficient; there is no known failing case.
- Broader `getinfo` / upvalue-name oracle tests beyond suite pass.

## Key files

| Area | Path |
|------|------|
| Pipeline | `lib/src/compile/pipeline.dart`, `lib/src/executor.dart` |
| IR compiler / lower | `lib/src/ir/compiler.dart`, `lib/src/ir/bytecode_lowering.dart` |
| SSA | `lib/src/ir/ssa*.dart` |
| Parse / locals | `lib/src/lua_bytecode/parser.dart`, `debug_local_caches.dart` |
| Decisions | [`doc/decisions.md`](../../doc/decisions.md) |

## Verification

```sh
dart analyze
dart test test/lua_bytecode/local_register_inference_test.dart
dart test
./test_runner --all-engines
dart run tool/compare.dart folding --disassemble
```
