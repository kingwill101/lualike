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

## Optional hardening

### 1. Transform-specific register budgets

- Escape analysis already skips scalar replacement when it cannot stay within
  the budget. Before enabling IR function inlining in the production config,
  make that pass skip an individual inline candidate instead of relying on the
  final budget validator to reject the prototype.

### 2. Make lowering even more mechanical

- Audit remaining expansion sequences (tempBase helpers) for any policy.
- Prefer specialized opcodes decided in IR over VM inference.

### 3. Debug metadata edge cases

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
