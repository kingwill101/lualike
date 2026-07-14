# IR / Bytecode Optimization Guide

This guide is for future-me: keep the IR path as the optimization boundary,
keep bytecode lowering mechanical, and use the Lua 5.5 compiler as the
sanity check for whether we are overdoing work in our own compiler.

## Current status

As of 2026-07-14:
- `./test_runner --all-engines` passes 30/30 on AST, IR, and lua-bytecode
- `dart test` passes 1,869 tests with 3 expected skips
- the complete folding comparison corpus passes, including transitive bundles

## Core rule

1. **IR/SSA decides shape.** If something changes runtime cost or instruction
   count, decide it before lowering.
2. **Lowering stays boring.** Bytecode lowering should serialize finalized IR,
   not discover new tricks or synthesize missing closure/control-flow metadata.
3. **VM stays thin.** The bytecode VM should dispatch finalized instructions,
   not re-infer call shape, register shape, or debug layout.
4. **Debug data must survive.** Serialize → parse → execute should keep the
   locals/upvalues shape that tests expect.

If a change makes the VM simpler, great. If it makes the VM smarter, ask
whether it belongs upstream in IR/SSA instead.

## Standard optimization loop

### 1) Pick one target

Start from a single benchmark or failing case. Prefer a tiny Lua repro over a
large suite run.

Good sources:
- `luascripts/*.lua`
- `luascripts/compare/*.lua` for focused disassembly comparisons
- `luascripts/folding/*.lua` for fold and bundle coverage
- a focused test file in `test/`

### 2) Capture a baseline

Record:
- instruction count
- `maxstack` / slot count
- constants count
- wall-clock time for the target script
- any changed test behavior

Useful commands:

```sh
cd pkgs/lualike
./test_runner --lua-bytecode
./test_runner --ir
```

For a compiled baseline:

```sh
cd pkgs/lualike
dart compile exe bin/main.dart -o ./lualike
./lualike --lua-bytecode /tmp/bench_calls.lua
./lualike --lua-bytecode /tmp/bench_arith.lua
```

Run each timing a few times and compare averages, not a single sample.

### 3) Dump and compare disassembly

Compare our output against `luac55` output for the same source.

Point the comparison tool at the reference compiler when it is not installed at
the default development path:

```sh
export LUAC55=~/Downloads/lua-5.5.0_Linux68_64_bin/luac55
```

Use the consolidated comparison tool for both compilers:

```sh
cd pkgs/lualike
dart run tool/compare.dart disasm luascripts/compare/01_arith.lua
```

The command compiles lualike in-process from the current checkout, then invokes
`luac55`. It intentionally does not use `./lualike`, which may be stale after
source changes. Use `--dump-ir` or `tool/trace.dart` when the question is about
an intermediate IR pass rather than final bytecode.

Things to compare:
- extra `MOVE`, `LOADK`, `LOADNIL`
- `CALL` / `RETURN` width
- `ADDI` vs `ADDK`
- jump threading around `TEST` / comparisons
- `VARARG`, `SETLIST`, `TAILCALL`
- stack pressure and temp registers

If our bytecode is larger or noisier than `luac55`, ask whether the extra work
is real or just compiler noise.

### 4) Fix the right layer

Prefer this order:

1. **IR/SSA** — constant propagation, value numbering, DCE, inlining,
   escape analysis, coalescing, loop motion.
2. **Mechanical lowering** — encode the decided shape, preserve debug info,
   keep register math correct.
3. **Bytecode peephole** — only obvious cleanups that do not create new
   policy.
4. **VM** — only when the shape cannot reasonably be pushed upstream.

If a VM change is needed repeatedly, it is probably a missed IR decision.

### Disabled passes are not production features

Function inlining currently has a tested safe subset, but remains disabled in
the production configuration. It only accepts direct, fixed-arity,
straight-line closures when operand roles, register allocation, and caller
metadata can be preserved exactly. Constants that require pool merging,
captures, control flow, varargs, multiple results, close state, and observable
callee debug frames are rejected.

Do not enable it because one script emits fewer instructions. First complete
the missing semantic remapping, compare serialized size and register pressure,
benchmark call-heavy workloads, and rerun every verification command below.

Loop unrolling also remains disabled in production. Its tested subset requires
debug stripping, finite constant numeric bounds, at most 64 iterations, and a
body containing only whitelisted local computation. Non-local control flow,
closures, nested loops, attributed locals, and unsupported declarations reject
the transform. Each copied iteration reuses its local slots.

The loop fixture improved median execution from 511,639 us to 289,341 us, but
grew from 39 to 44 instructions and from 292 to 312 serialized bytes. That is
useful evidence for an opt-in pass, not sufficient evidence for enabling it by
default. A profitability policy must account for runtime, bytecode size, and
register pressure.

## What usually matters

### Instruction count

Fewer instructions is not always better, but instruction count is the first
signal that the IR shape is getting cleaner.

Watch for:
- redundant loads/stores
- temporary registers that only exist because lowering was too eager
- wide `CALL`/`RETURN` windows
- missed `LOADNIL` coalescing
- missed small-integer immediates (`ADDI`)

### Register pressure

If `maxstack` climbs, check whether:
- a lowering temp can be removed
- a value can be forwarded earlier in IR
- a multi-return pack is leaving holes
- debug-local inference is forcing extra slots

The compiler budget always leaves room for the worst-case two-register
mechanical expansion. Lowering separately records the exact number of scratch
slots used by each prototype so simple functions do not advertise unused
stack slots.

### Debug correctness

Any change that touches locals, upvalues, `debug.getlocal`, or stack layout
needs a round-trip test.

## Validation checklist

Before landing a change:

- [ ] Repro script still behaves correctly
- [ ] `dart test` passes
- [ ] `./test_runner --all-engines` passes
- [ ] Affected focused tests pass (`locals.lua`, `db.lua`, `errors.lua`,
      `cstack.lua`, `closure.lua` are common sentinels)
- [ ] Disassembly is still sane versus `luac55`
- [ ] `dart run tool/compare.dart folding --disassemble` passes when folding
      or lowering changed
- [ ] Any new policy is documented in [`doc/decisions.md`](../decisions.md)
- [ ] If the change is user-visible, add a note to `CHANGELOG.md`

## Good temporary tooling habits

- Add stable investigation behavior to `tool/compare.dart` or a focused test
  instead of creating shell wrappers.
- Keep temporary Dart experiments untracked and remove them once the idea is
  proven.
- Treat `.tmp/` as disposable cache space (for example,
  `.tmp/lualike_luac55_Cache`).

## Common failure modes

- SSA improves one path but breaks the IR path.
- Lowering hides a policy decision instead of preserving it.
- Lowering normalizes malformed finalized IR instead of rejecting it.
- A bytecode peephole fixes one case and regresses `debug.getlocal`.
- A VM micro-optimization helps one benchmark but makes the VM harder to
  reason about.
- We “optimize” into larger bytecode than `luac55` would emit.

## Current direction

The intended end state is:

**IR/SSA emits the best bytecode shape we can justify → lowering encodes it
mechanically → bytecode VM stays thin and fast.**

When in doubt, compare against `luac55`, keep the suite green, and prefer the
simpler compiler boundary.
