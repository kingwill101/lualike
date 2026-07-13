# IR Next-Phase Plan

## Context

We want the IR layer to be the optimization boundary and the bytecode VM to stay thin. The current codebase already has SSA scaffolding and several IR passes, but the contract is still fuzzy: some decisions happen in AST passes, some in the IR compiler, and some remain in bytecode lowering / VM helpers. That makes it hard to reason about performance and makes it easy for runtime work to leak back into the VM.

## Approach

1. Make the IR pipeline the single place where optimizations and shape decisions happen.
2. Treat bytecode lowering as mechanical serialization of already-decided IR.
3. Expand SSA coverage so the existing passes can actually remove redundant work before bytecode emission.
4. Keep the VM focused on fast dispatch, register access, and explicit slow paths only.

## Files to modify

- `pkgs/lualike/lib/src/compile/pipeline.dart`
- `pkgs/lualike/lib/src/ir/compiler.dart`
- `pkgs/lualike/lib/src/ir/bytecode_lowering.dart`
- `pkgs/lualike/lib/src/ir/opcode.dart`
- `pkgs/lualike/lib/src/ir/ssa.dart`
- `pkgs/lualike/lib/src/ir/ssa_dead_code_pass.dart`
- `pkgs/lualike/lib/src/ir/ssa_gvn_pass.dart`
- `pkgs/lualike/lib/src/ir/ssa_sccp_pass.dart`
- `pkgs/lualike/lib/src/ir/ssa_licm_pass.dart`
- `pkgs/lualike/lib/src/ir/ssa_coalesce_pass.dart`
- `pkgs/lualike/lib/src/ir/ssa_escape_pass.dart`
- `pkgs/lualike/lib/src/ir/inline_pass.dart`
- `pkgs/lualike/lib/src/ir/peephole_pass.dart`
- `pkgs/lualike/lib/src/lua_bytecode/vm.dart`
- `pkgs/lualike/lib/src/lua_bytecode/vm_call.dart`
- `pkgs/lualike/lib/src/lua_bytecode/vm_frame.dart`
- `pkgs/lualike/lib/src/lua_bytecode/vm_tables.dart`
- `pkgs/lualike/test/compiler_passes_test.dart`
- `pkgs/lualike/test/constant_folding_test.dart`
- `pkgs/lualike/test/ir/*`
- `pkgs/lualike/test/lua_bytecode/source_engine_test.dart`

## Reuse

- SSA builder/formatter: `lib/src/ir/ssa.dart`, `lib/ir.dart`
- Existing SSA passes: `ssa_dead_code_pass.dart`, `ssa_gvn_pass.dart`, `ssa_sccp_pass.dart`, `ssa_licm_pass.dart`, `ssa_coalesce_pass.dart`, `ssa_escape_pass.dart`
- Function inlining: `lib/src/ir/inline_pass.dart`
- Current mechanical lowering: `lib/src/ir/bytecode_lowering.dart`
- Current IR compiler emitters: `lib/src/ir/compiler.dart`
- Existing bytecode peephole: `lib/src/lua_bytecode/peephole_pass.dart`

## Steps

- [ ] Step 1: Define the IR contract
  - Decide and document what must be finalized before lowering: register assignment, call shape, closure capture, jump targets, and opcode specialization.
  - Keep this in docs/decisions or the IR README so the compiler and VM stay aligned.

- [ ] Step 2: Make SSA the optimization boundary
  - Ensure the existing SSA passes run in a consistent, intentional order on every prototype.
  - Make sure recursive prototypes are handled uniformly.
  - Verify trivial phi removal, DCE, GVN, SCCP, LICM, coalescing, escape analysis, and inlining all feed into the same lowered output.

- [ ] Step 3: Move any remaining shape decisions upstream
  - Audit `LualikeIrCompiler` for places where it still emits high-level behavior that should be resolved earlier.
  - Prefer specialized opcodes and explicit slow-path instructions over VM inference.
  - Keep `bytecode_lowering.dart` purely translational.

- [ ] Step 4: Thin the VM hot path
  - Remove or reduce helper-layer work in `vm.dart`, `vm_call.dart`, and `vm_frame.dart` where the IR can already provide the answer.
  - Focus on raw register access, explicit fast opcodes, and minimizing allocation/async work in dispatch.

- [ ] Step 5: Add contract tests
  - Add tests proving the IR output changes before lowering.
  - Add tests proving bytecode lowering preserves the IR’s decisions.
  - Add regression tests for closure/calls/sort/heavy workloads and for nested prototypes.

- [ ] Step 6: Benchmark and profile
  - Compare AST, IR, and bytecode modes on `closure.lua`, `calls.lua`, `sort.lua`, and `heavy.lua`.
  - Check both compiled and direct `.lub` execution.
  - Use profiling to confirm the hotspot moves from compiler/VM helpers into the expected thin dispatch loop.

## Verification

- `dart analyze`
- `dart test`
- `./lualike luascripts/test/closure.lua`
- `./lualike luascripts/test/calls.lua`
- `./lualike luascripts/test/sort.lua`
- `./lualike luascripts/test/heavy.lua`
- `./lualike --compile -o /tmp/out.lub luascripts/test/closure.lua`
- `./lualike /tmp/out.lub --lua-bytecode`
- Profile before/after with the existing DevTools workflow and compare hot spots in the bytecode VM versus IR compilation.

## Notes

This plan intentionally prioritizes the IR contract before any deeper VM rewrite. If the IR stays high-level, a thinner VM won’t help much. If the IR becomes sufficiently explicit, the VM can stay simple and fast.
