# IR/Bytecode Optimization Push — Technical Report

**Branch:** `wip/ssa-ir-optimization`
**Date:** 2026-07-14
**Scope:** Initial 24-commit optimization stack plus compatibility, comparison,
and disassembly hardening

---

## 1. What Was Accomplished

The initial 24 commits changed the IR compiler, SSA passes, bytecode lowering,
bytecode peephole, serializer, CLI, test infrastructure, and standard library.
Subsequent compatibility and tooling commits hardened that stack. The central
goal was making the IR layer the optimization boundary so the bytecode VM stays
a thin executor.

### 1.1 Instruction-Density Parity with luac55 (the core win)

The lowering now produces bytecode of equal or better density than the official Lua 5.5 compiler (`luac55`) across 22 comparison scripts covering arithmetic, tables, calls, varargs, closures, loops, boolean logic, strings, tail calls, coroutines, to-be-closed variables, upvalues, floating-point, bitwise operations, locals, globals, lexical scoping, `_ENV` manipulation, global declarations, and const locals.

15 comparable benchmarks — all at or below luac55:

| Benchmark | Ours | luac55 | Δ |
|-----------|------|--------|---|
| multiret | 13 | 21 | **-8** |
| bitwise | 9 | 17 | **-8** |
| coroutine | 38 | 43 | **-5** |
| tobeclosed | 6 | 9 | **-3** |
| tailcall | 7 | 9 | **-2** |
| arith | 16 | 17 | **-1** |
| boolean | 25 | 26 | **-1** |
| string | 14 | 15 | **-1** |
| vararg | 20 | 21 | **-1** |
| calls | 15 | 16 | **-1** |
| upvalues | 29 | 30 | **-1** |
| float | 27 | 27 | **0** |
| table | 16 | 16 | **0** |
| loops | 25 | 25 | **0** |
| closure | 13 | 13 | **0** |

### 1.2 Optimizations Applied

| # | Commit | Optimization | Impact |
|---|--------|-------------|--------|
| 1 | `5b8800df` | ADDI emission (luac55-style), signed C for sync ADDI, stacked-correct sync nested CALL | Starting point |
| 2 | `1fd15c47` | SSA escape/SROA hardening; SETLIST use-def so DCE cannot drop array fills; CALL/RETURN register-window escape detection; return packing for multi-value returns; VM one-pass param init; ADDI extracted to own case | Foundation |
| 3 | `18816224` | `--disassemble` CLI flag; `tool/compare_disasm.dart`; `tool/count_profile.dart`; register budget fix (maxRegisterCount) | Tooling |
| 4 | `30058055` | `subI` IR opcode with correct `__sub` metamethod event (was incorrectly using `__add`); peephole guards for strength-reduction (`MULK 2→ADD`, identity arith, `POW 0`) behind `k=false` | Correctness |
| 5 | `0c4ac951` | `--raw` flag; `enableBytecodePeephole` separated from `enablePeephole` | Debugging |
| 6 | `bd33379a` | Return-packing MOVEs skipped when results are already contiguous (saved 6 MOVEs per multi-return) | Density |
| 7 | `c998cd36` | `_emitAssignmentValues` passes target registers to expressions so LOADI et al. write directly into the named variable register | Density |
| 8 | `0165f8ce` | Single-expression return no longer forces `target: 0` | Density |
| 9 | `08749f84` | Identifier returns use local register directly (saved MOVEs in multi-return statements) | Density |
| 10 | `41631d11` | Binary expressions write directly to target register (removes `_isRegisterOccupiedByLocal` guard); loops numeric-for body now matches luac55 (2 instrs) | Density |
| 11 | `4f04f99e` | CALL ABI: passes target register as `baseRegister` to `_emitFunctionCall` when target registers are available | Density |
| 12 | `63756b4a` | SETFIELD inlines constant values as Kst instead of register (eliminates LOADI+SETFIELD → SETFIELD+Kst) | Density |
| 13 | `b359010d` | `~=`/`!=` uses inverted EQ (`k=false`) instead of EQ+NOT | Density |
| 14 | `b5606e88` | Bytecode peephole soundness fix: LOAD*+MOVE fold checks `_registerUsedLaterAsSource` to avoid leaving tmp undefined | Correctness |
| 15 | `b0ab62f5` | Right operand in register-register comparisons skips temp copy when it's an Identifier | Density |
| 16 | `97523898` | Trailing register extension (serialize debug registers) — **reverted** due to byte-alignment issues | — |
| 17 | `48c1a316` | Coalesce tracks `RETURN1`/`return0` as register reads; marks `RETURN1` as non-writing | Correctness |
| 18 | `b99d4fad` | `_emitEqualityWithLiteral` sets `k=true` for `==` and `k=false` for `~=` (was using k=true+NOT) | Correctness |
| 19 | `59aac26a` | `package.searchers` as `TableStorage` (was `Dart List`); coalesce tracks `TFORPREP`/`TFORCALL`/`TFORLOOP` register reads/writes | Correctness + SSA |
| 20 | `ea8455d6` | Property-based fuzz tests with `package:property_testing` (register budget stress) | Testing |

### 1.3 Tools Built

- **`--disassemble`** — CLI flag to print bytecode disassembly and exit
- **`--raw`** — disables bytecode peephole for debugging
- **`tool/trace.dart`** — pipeline tracer showing IR after each pass (ir → peephole → dce → gvn → sccp → licm → coalesce → escape → bc)
- **`tool/compare.dart disasm`** — compares lualike with luac55, including
  separate reference chunks against one optimized static bundle
- **`tool/compare.dart ir`** — compares unoptimized, optimized, and SSA IR
- **`tool/compare.dart folding`** — validates the complete folding fixture set
- **`tool/count_profile.dart`** — instruction/slot count summary across all compare scripts
- **`test/fuzz_test.dart`** — property-based fuzz tests (many locals, deep expressions, large parameters, random trees)
- **22 `luascripts/compare/*.lua` scripts** — targeted benchmarks for each language feature

---

## 2. Bugs Found and Fixed

### 2.1 Bytecode Peephole Soundness (commit b5606e88)

**Bug:** The bytecode peephole had two patterns that interacted badly:
- Pattern A: `LOADI tmp; MOVE dest,tmp` → `LOADI dest` (redirects load away from tmp)
- Pattern B: `ADDI tmp,src; MMBIN*; MOVE dest,tmp` → `ADDI dest,src` (reads src register)

When both patterns matched the same tmp register, pattern A redirected the load away from tmp, leaving tmp undefined. Then pattern B's ADDI read from the now-undefined tmp, producing a nil-register error.

**Fix:** Added `_registerUsedLaterAsSource()` check — the LOAD*+MOVE fold only fires when `tmp` is not used as a source register by any later instruction.

**Result:** `--raw` no longer needed for correctness; default mode produces correct output for all 15 benchmarks.

### 2.2 Metamethod Event Mismatch (commit 30058055)

**Bug:** When the IR compiler strength-reduced `x - 1` → `ADDI x, -1`, the lowering's `_binaryMetamethodEvent` mapped `addI`→`__add` (event 6). If `x` had a metatable, `__add` would fire instead of `__sub`. Same for `b * 2` → `b + b` using `__add` instead of `__mul`.

**Fix:** Added `subI` IR opcode that carries `__sub` event. The lowering maps `subI` to bytecode ADDI (with negated immediate) and `MMBINI(__sub)`. Peephole strength-reduction (MULK 2→ADD, identity arith, POW 0) gated behind `k=false`.

### 2.3 `~=`/`!=` Comparison Inversion (commit b99d4fad)

**Bug:** `local x = 27; print(x == 27)` returned false. The `_emitEqualityWithLiteral` function emitted `eqI` without setting the `k` flag (default = false). The lowering's `compareWord` was changed to pass `instruction.k` through (instead of hardcoding `k=true`). With `k=false`, the comparison skipped the JMP on equality, landing on the `LFALSESKIP` path and producing `false`.

**Fix:** Set `k=true` for `==` and `k=false` for `~=` in both `_emitEqualityWithLiteral` and the inline comparison paths.

### 2.4 SSA Coalesce Missing Register Tracking (commit 48c1a316)

**Bug:** The coalesce pass's `_reads` function didn't include `RETURN1` or `return0` as register reads. When a MOVE into the return register was eliminated, the return instruction was not renamed to read from the original source register, leaving it pointing at an undefined temp register and returning nil.

**Fix:** Added `RETURN1` and `return0` to both `_reads` (as register reads for the A operand) and `_writesReg` (as non-writing).

### 2.5 SSA Coalesce Missing TFORxx Tracking (commit 59aac26a)

**Bug:** The coalesce pass had no register tracking for `TFORPREP`, `TFORCALL`, or `TFORLOOP`. These instructions control generic for loops and read/write the for-loop state registers at R(A..A+3). Since the coalesce's `asbx` handler returned `{}` (no register reads), it would eliminate MOVEs that set up the for-loop state, leaving the TFORPREP with undefined register values.

**Fix:** Added register tracking in `_reads` (TFORPREP reads A..A+2; TFORLOOP reads A+2; TFORCALL reads A..A+2), `_writesReg` (TFORPREP/TFORLOOP don't write; TFORCALL writes A+3+), and `_bIsRegister`/`_cIsRegister`.

### 2.6 `package.searchers` as TableStorage (commit 59aac26a)

**Bug:** `package.searchers` was stored as a Dart `List<Value>`. Lua operations like `pairs()`, `next()`, and `#` don't work on Dart Lists — they require `TableStorage`-backed values. This broke `require`'s Lua-side iteration of searchers and prevented modules from being found.

**Fix:** Changed `createFunctions()` to use `_createDefaultSearchersTable()` which stores searchers in a `TableStorage` (i.e., a proper Lua table). Updated `RequireFunction.__trySearchers` to accept both `List` and `Map` backed searchers.

### 2.7 EQ+NQ Fusion Not Applied in `_emitEqualityWithLiteral` (commit b99d4fad)

**Bug:** When the `isComparison` path `==`/`~=` used
`_emitEqualityWithLiteral`, the function emitted `eqI`/`eqK` without setting
`k`, then emitted a `notOp` for `~=`. The lowering now uses `instruction.k`
instead of hardcoding `k=true`, so the compound comparison materialization and
`NOT` produced the wrong boolean.

**Fix:** `_emitEqualityWithLiteral` now sets `k=!negate` directly on the compare
instruction, eliminating the follow-up `notOp`.

---

## 3. Compatibility Failures Resolved

The final investigation showed that the remaining failures were not caused by
invalid serialized Lua chunks. They exposed four semantic gaps at the IR/VM
boundary and one standard-library result-shape mismatch.

### 3.1 SROA must preserve aliases and closure captures

**Bug:** Escape analysis could scalar-replace a table even when its allocation
register was copied by `MOVE` or captured by a child prototype's in-stack
upvalue. The replacement only rewrote accesses through the original register,
so aliases and closures could observe a missing or incomplete table.

**Fix:** A moved table is now conservatively treated as escaping, and candidate
registers referenced by child upvalue descriptors are removed from the scalar
replacement set. Tables read by `CHECKGLOBAL` are also preserved because its
dynamic environment lookup cannot be rewritten into scalar fields. Alias-aware
scalar rewriting can replace the first two conservative rules later.

**Regression coverage:** `test/ir/ssa_escape_pass_test.dart` covers a returned
`MOVE` alias, a child closure capture, and a local `_ENV` table read by
`CHECKGLOBAL`.

### 3.2 Comparisons must preserve operands and polarity

**Bug:** Materializing a local right operand into the left operand's register
could overwrite the left value before `EQ`, `LT`, or `LE` read it. In addition,
materialized comparison instructions require `k=true` for normal equality and
ordering, while `~=` uses `k=false` for inverted polarity.

**Fix:** Local right operands are read directly from their binding registers;
non-local expressions still use a temporary. Register and inline-integer
comparisons now set the polarity flag explicitly.

**Regression coverage:** `test/ir/compiler_comparison_test.dart` verifies the
instruction shape and `test/ir/vm_comparison_test.dart` verifies both optimized
engine modes.

### 3.3 Late GC tracking must preserve allocation accounting

**Bug:** `ensureTracked()` applied a narrower exclusion rule than normal Value
registration. Transient scalar and internal values created without immediate
registration could therefore become chargeable later, inflating
`collectgarbage("count")` after the weak-table stress section of `gc.lua`.

**Fix:** Value exposes one GC-allocation classification used by both normal and
late registration. Excluded late-tracked objects are still assigned a GC space
for reachability, but are registered with memory credits as excluded.

**Regression coverage:** `test/gc/late_tracked_value_accounting_test.dart`.

### 3.4 A manual GC step is one bounded slice

**Bug:** `performManualStep()` retried incremental collection internally up to
eight times and accumulated work debt. A single small API call could complete a
whole cycle, erasing the size-dependent pacing required by
`collectgarbage("step", size)`.

**Fix:** Each call now performs exactly one bounded incremental slice. The size
argument scales that slice, and the return value reports whether that slice
completed the current cycle.

**Regression coverage:** `test/gc/manual_step_pacing_test.dart` verifies that a
small step requires more calls than a large step in both optimized engines.

### 3.5 `require` uses Lua multi-return semantics

**Bug:** Returning the successful searcher result as a raw Dart list made
single-value contexts observe the wrong shape. Returning only the module fixed
that case but broke Lua 5.4's second `require` result and discarded custom
searcher loader data.

**Fix:** Successful `require` calls return
`LuaResults([module, loaderData])`. Lua evaluation then selects one or both
results according to context, and string loader paths remain normalized.

### 3.6 Prototype reconstruction preserves named varargs

**Bug:** SSA passes rebuilt prototypes without copying the named-vararg
register. The ordinary vararg flag survived, so most vararg programs passed,
but source that referenced a named vararg lost its binding after optimization.

**Fix:** Every prototype-rebuilding pass now propagates the named-vararg
register together with parameter, upvalue, debug, and child-prototype metadata.

### 3.7 Loop register windows are modeled as loop-carried state

**Bug:** Numeric and generic loop instructions were analyzed as if they read or
wrote only their explicit `A` operand. Coalescing and debug-local expiry could
therefore clear iterator state that a later `FORLOOP`, `TFORCALL`, or
`TFORLOOP` consumed.

**Fix:** IR coalescing and bytecode instruction analysis now model each
opcode's complete state and result windows. Debug-local expiry also retains a
register when the current instruction reads it, even if source debug metadata
says the local lifetime has ended.

### 3.8 Peephole folds preserve live temporaries and branch targets

**Bug:** Destination folding could redirect arithmetic away from a temporary
that was still read later. It could also remove a `MOVE` reached by a jump or
loop edge, changing control-flow behavior despite a valid fallthrough pattern.

**Fix:** Load and arithmetic folds require both source-register deadness and no
incoming control-flow edge to the removed instruction. Jump offsets continue
to be remapped only after the retained instruction set is final.

### 3.9 LICM rejects reverse-layout loops

**Bug:** Numeric and generic loop bytecode can place the physical body before
the natural-loop header. LICM inserted hoisted instructions before that later
header, duplicating body instructions and invalidating backedges.

**Fix:** The current LICM pass transforms only forward-layout natural loops.
Reverse-layout loops remain unchanged until preheader construction and program
counter remapping are fully control-flow aware.

### 3.10 SCCP preserves boolean types

**Bug:** SCCP represented `false` and `true` as integer constants `0` and `1`,
then rewrote boolean loads and comparisons to `LOADI`. Lua truthiness hid the
problem in broad scripts, but returned values had the wrong type.

**Fix:** The SCCP lattice is integer-only. Boolean loads and boolean-producing
comparisons are excluded instead of approximated as integers.

### 3.11 Forward gotos close exited lexical scopes

**Bug:** Forward-goto resolution recomputed close requirements after exited
scopes had been popped from compiler state. It replaced a required provisional
`CLOSE` with a no-op, leaking `<close>` locals on the jump path.

**Fix:** Pending gotos snapshot closable registers by lexical scope and resolve
the exact lowest register belonging to scopes crossed by the final jump.

### 3.12 Error-close handlers observe reference call names

**Bug:** Call-name inference examined local lifetimes after `CALL`, so the
result local in `local ok = pcall(foo)` was reported as the callee. Tail-call
frame reuse could also discard the inferred name.

**Fix:** Names are inferred from the register state at the call instruction,
and fast tail calls carry that name into the reused frame. Failed bytecode
frames are removed before error-time close handlers execute.

### 3.13 Test expectations match bounded and diagnostic contracts

`collectgarbage("step", size)` tests now accept either boolean completion
state for one bounded slice. `--dump-ir` tests read stdout, which is the CLI's
documented output stream; stderr remains reserved for failures.

### 3.14 Bundled DCE resolves builders within lexical module blocks

**Bug:** Bundled modules conventionally declare their export table as
`local M = {}`. Dead-code elimination keyed those builder names globally, so a
later module's `M` replaced an earlier module's mapping. Reads from the earlier
module were then attributed to the wrong bundle variable and live exports could
be removed.

**Fix:** Builder discovery now runs independently for each bundler-generated
`do` block. The elimination pass receives only that block's builder-to-module
mapping, preserving same-named module locals without weakening export tree
shaking.

**Decision:** luac55 remains a structural reference, not a bundle reference:
it compiles an entrypoint and each required source as separate chunks. The
comparison tool therefore prints those chunks individually and compares their
combined instruction count with lualike's single optimized bundle. Runtime
equivalence is enforced separately by a regression test that executes the
serialized bundle, checks transitive imports, and verifies repeated `require`
identity.

### 3.15 Peephole ADDI rewrites respect the signed immediate range

**Bug:** The peephole pass rewrote `ADD` with a known `LOADI` operand to
`ADDI` for any integer. Values outside bytecode's signed C range encoded above
255 and failed during lowering. The complete folding corpus exposed this with
the reassociated color sum in `99_speed.lua`.

**Fix:** `LuaBytecodeInstructionLayout` now exposes the documented
`minSignedArgC`, `maxSignedArgC`, and `fitsSignedArgC` encoding contract. Both
the compiler and peephole pass use it, limiting immediate rewrites to
`-127..128`. Larger values remain in registers. A pipeline regression compiles
a folded table-field sum that previously produced the invalid immediate.

**Validation tooling:** `tool/compare.dart` uses Artisanal `CommandRunner`,
the runner-owned `Console`, and `Style.border`. Directory and folding commands
aggregate subprocess failures and exit nonzero if either compiler fails, so a
later fixture cannot hide an earlier failure.

### 3.16 Disassembly includes prototype metadata

**Gap:** lualike's instruction listing reported only aggregate prototype
counts. `luac55 -l -l` also prints each prototype's constants, debug locals,
and upvalue descriptors, making side-by-side analysis unnecessarily uneven.

**Fix:** The disassembler now renders luac-style `constants`, `locals`, and
`upvalues` tables after every prototype's instructions. Constant values retain
their type tags and escaped string representation, and vararg prototypes use
luac's `0+ params` notation.

Instruction comments remain derived data rather than serialized strings. The
serializer writes the raw instruction word and constant pool; the disassembler
now resolves K-operand values, `MMBIN*` event IDs such as `9` to `__mod`, and
return counts from those fields. For example, an encoded `MMBINK` referencing
constant `3` renders as `; __mod 3`, matching `luac55 -l -l`.

The comparison command compiles the lualike side in-process from the current
checkout. It does not invoke `./lualike`, because that executable can lag
behind source changes and produce a misleading side-by-side listing.

---

## 4. Initial Commit History (24 commits from 5b8800df)

```
59aac26a fix: package.searchers as TableStorage + coalesce TFORxx
614ac996 revert: trailing register extension (broke serialize/load)
48c1a316 fix: coalesce track RETURN1/return0 as register reads
b99d4fad fix: set k flag on eqI/eqK for correct ==/~=
97523898 feat: trailing register extension (reverted)
ea8455d6 test: property-based fuzz tests
4df95c97 fix: missing global declarations for luac55 compat
1ab4ac2b chore: comparison scripts (locals/globals/scoping/env/tbc/const)
b0ab62f5 perf: skip temp copy for right operand in comparisons
b5606e88 fix: bytecode peephole LOAD*+MOVE fold soundness
b359010d perf: fold ~=/!= EQ+NOT into inverted EQ (k=false)
238727d1 docs: update decisions with SETFIELD Kst inlining
63756b4a perf: inline constant values in SETFIELD as Kst
87b5c792 docs: document CALL ABI improvement
4f04f99e perf: pass target registers as base to function calls
41631d11 perf: allow binary expressions to write directly to target
08749f84 perf: use local registers directly for identifier returns
0165f8ce perf: remove target:0 hint from single-expression return
c998cd36 perf: pass target registers through _emitAssignmentValues
bd33379a perf: skip return-packing MOVEs when contiguous
0c4ac951 feat: --raw flag, enableBytecodePeephole config
30058055 perf: subI opcode, fix metamethod events
18816224 feat: CLI --disassemble, compare tooling, register budget fix
1fd15c47 perf: SSA escape/SROA hardening, return packing, frame init
5b8800df perf: ADDI emission (luac55) + sync nested CALL
```

---

## 5. Final Test Results

| Engine | Pass | Fail | Failures |
|--------|------|------|----------|
| AST | **30/30** | 0 | — |
| IR | **30/30** | 0 | — |
| lua-bytecode | **30/30** | 0 | — |

The final `./test_runner --all-engines` run on 2026-07-13 rebuilt the CLI and
passed all 90 engine/test combinations. `heavy.lua` remained excluded by the
runner's default `--skip-heavy` policy.

The post-hardening validation run also passed:

- `dart test`: 1,841 passed, 3 skipped, 0 failed before the disassembly-only
  metadata test was added; the focused disassembler suite passes 4/4.
- `dart analyze`: no errors or warnings; 5 pre-existing informational lints in
  fuzz and trace tooling.
- Affected-file regression set: 218 passed, including live `luac55` bytecode
  cross-compatibility.
- Fresh `./test_runner --all-engines`: AST 30/30, IR 30/30, and lua-bytecode
  30/30. This run rebuilt the executable from the modified sources first.
- `tool/compare.dart folding --disassemble`: all 22 top-level folding
  fixtures passed, including the three-source transitive bundle; stderr was
  empty.

**Total:** The initial 24 optimization commits plus compatibility,
serialization, comparison, and disassembly hardening; 0 known integration
regressions; and 15+ benchmarks at or below luac55 instruction-density parity.
