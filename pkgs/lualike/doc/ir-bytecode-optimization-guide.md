# IR / Bytecode Optimization Guide

This guide is for future-me: keep the IR path as the optimization boundary,
keep bytecode lowering mechanical, and use the Lua 5.5 compiler as the
sanity check for whether we are overdoing work in our own compiler.

## Current status

As of 2026-07-13:
- `./test_runner --lua-bytecode` passes
- `./test_runner --ir` passes
- some `dart test` cases around IR / bytecode shape are still stale and may need
  to be updated or retired rather than fixed blindly

## Core rule

1. **IR/SSA decides shape.** If something changes runtime cost or instruction
   count, decide it before lowering.
2. **Lowering stays boring.** Bytecode lowering should serialize finalized IR,
   not discover new tricks.
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
- `tool/tmp_*.dart` scratch repros
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

Recommended pattern:

```sh
export LUAC55=~/Downloads/lua-5.5.0_Linux68_64_bin/luac55
"$LUAC55" -l -l /tmp/repro.lua
```

For our compiler, use either:
- `--dump-ir` when the question is about IR shape, or
- a scratch Dart script that compiles source and prints the bytecode
  disassembly.

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

### Debug correctness

Any change that touches locals, upvalues, `debug.getlocal`, or stack layout
needs a round-trip test.

## Validation checklist

Before landing a change:

- [ ] Repro script still behaves correctly
- [ ] `./test_runner --lua-bytecode` passes
- [ ] Affected focused tests pass (`locals.lua`, `db.lua`, `errors.lua`,
      `cstack.lua`, `closure.lua` are common sentinels)
- [ ] Disassembly is still sane versus `luac55`
- [ ] Any new policy is documented in `doc/decisions.md`
- [ ] If the change is user-visible, add a note to `CHANGELOG.md`

## Good temporary tooling habits

- Use `tool/tmp_*.dart` for experiments only.
- Delete or rename scratch scripts once the idea is proven.
- Move stable investigation helpers into `tool/` or a real test.
- Treat `.tmp/` as disposable cache space (for example,
  `.tmp/lualike_luac55_Cache`).

## Common failure modes

- SSA improves one path but breaks the IR path.
- Lowering hides a policy decision instead of preserving it.
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
