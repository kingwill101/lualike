## Overview
We will specialise numeric loop execution inside the AST interpreter to eliminate per-iteration environment churn. The design introduces a guarded fast path for simple numeric `for` loops (and array-style `for`-in loops) that keeps the loop environment stable and executes the body through a tight executor.

## Current Interpreter Overhead
- `visitForLoop` creates a fresh `Environment`, boxes the control variable, and on every iteration:
  - Calls `setCurrentEnv` / `resetLoopEnvironment`, which walks `loopEnv.values`, reconciles it with `baseBindings`, and closes any to-be-closed variables.
  - Re-enters `_executeStatements`, forcing the generic visitor (with logging, metamethod checks, multi-value collapse, etc.).
  - Boxes the loop counter each time, triggering GC tracking and version bumps even when the body is empty.
- `visitForInLoop` performs similar environment churn. For simple array iteration it still:
  - Allocates an `Environment` per loop, performs `resetLoopEnvironment` after each iteration, and re-boxes the loop vars.
  - Re-evaluates iterator triples even when they’re the canonical `ipairs` shape.
- Logging calls (`Logger.debug`/`Logger.info`) are evaluated unconditionally, meaning every iteration still formats debug strings even when logging is disabled.
- Micro benchmarks (`x = x + 1` for 100k iterations) now take ~150 s, showing that environment churn + logging dominates execution.

## Fast Path Eligibility
- Loop bounds (`start`, `end`, `step`) must evaluate to numeric scalars with no side effects.
- Loop body must not declare locals, create to-be-closed variables, or contain `goto`/`break`/`return` that escape the loop in non-standard ways.
- No uses of metamethod-sensitive operations (e.g., `__index`, reassignment of `_ENV`).
- If any guard fails at runtime (e.g., metamethod gets attached) we fall back to the generic interpreter path.

## Execution Strategy
- Reuse the existing boxed loop variable; increment it in place.
- Execute the statement list with a lightweight runner that avoids `resetLoopEnvironment` unless locals were observed.
- Maintain bail-out hooks so that `break`, `return`, or an unsupported operation switches back to the generic behaviour mid-loop.

### Specialisation Plan
- Evaluate the loop header once, storing numeric `start`, `end`, `step` as `num` (reuse existing parsing but memoise the results).
- Analyse the loop body AST:
  - Reject if it declares locals (including implicit locals from `for` syntax), manipulates `_ENV`, or contains nested loops with side-effectful headers.
  - Reject if it contains `goto`, labels, or any statement that requires re-entering the generic environment logic.
- For `for-in`, detect the canonical `ipairs`/array iteration shape: function is `ipairs`, state is a TableStorage-backed table, and the control variable count ≤2.
- Install a specialised executor that:
  - Keeps a single `Box` for the counter and writes raw numeric values.
  - Invokes a trimmed statement runner that bypasses logging and `resetLoopEnvironment` unless the body mutates the environment.
  - Checks a `bailout` flag whenever the body calls into functionality flagged as unsafe (metamethods, coroutine yields, debug hooks).
- On bailout the executor restores interpreter state and resumes via the original visitor so semantics stay intact.

## Fallback Mechanics
- Guard checks run once before entering the loop and optionally during execution if state changes.
- On bailout we restore the previous interpreter state and resume with the general loop logic to preserve semantics.

## Benchmark Plan
- Run `dart run tool/table_bench.dart 1000 1` (and larger variants) to measure sequential loop improvements.
- Execute `./test_runner --test=constructs.lua --skip-heavy -v` and `--test=sort.lua` to evaluate end-to-end gains.
- Record the delta relative to pre-fast-path results for documentation.

### Benchmark Snapshot (2025-11-01)
- `dart run tool/table_bench.dart 256 5`
  - `seq_assign`: 90.69 ms
  - `forward_read`: 72.70 ms
  - `backward_read`: 74.34 ms
  - `random_read`: 178.41 ms
  - `string_assign`: 115.74 ms
  - `string_lookup`: 99.88 ms
  - `sort_check`: 211.90 ms
- `./test_runner --test=constructs.lua --skip-heavy -v`: 330 255 ms (≈11 % faster than the previous 370 s run)
- `./test_runner --test=sort.lua --skip-heavy -v`: still times out (~207 585 ms) during `testing unpack`
