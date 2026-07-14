# IR Next-Phase Plan

## Context

We want the IR layer to be the optimization boundary and the bytecode VM to stay
thin. SSA and the fold pipeline exist; the remaining work is making the
IR→bytecode **contract** register-safe and debug-correct so `--lua-bytecode
--fold` / `--compile` can stay on the full pipeline by default.

Authoritative decisions: [`doc/decisions.md`](../../doc/decisions.md) (IR
contract, official bytecode locals, and SSA safety notes).

## Approach

1. IR/SSA own optimization and shape decisions.
2. Bytecode lowering only serializes finalized IR.
3. VM stays thin: dispatch, registers, explicit slow paths.
4. Debug metadata must survive serialize → parse → execute.

## Done (2026-07-12)

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

## Remaining work

### 1. Keep SSA safer under stress

- Fuzz / large prototypes that approach the 253-register budget.
- Loud failure is in place; ensure escape/inline never allocate past budget
  without skipping the transform (escape already skips when over budget).

### 2. Make lowering even more mechanical

- Audit remaining expansion sequences (tempBase helpers) for any policy.
- Prefer specialized opcodes decided in IR over VM inference.

### 3. Debug metadata edge cases

- Consider private trailing register extension on serialize if stack
  inference is insufficient for non-stack local layouts.
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
# Optional broader:
dart run bin/main.dart --lua-bytecode --fold -e 'local a=10; print(debug.getlocal(1,1))'
```
