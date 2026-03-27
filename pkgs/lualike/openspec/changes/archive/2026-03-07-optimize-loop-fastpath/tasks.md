## 1. Analysis & Design
- [x] 1.1 Survey current `ForLoop`/`ForInLoop` execution to document per-iteration costs and identify safe specialization criteria.
- [x] 1.2 Draft fast-path design outlining environment reuse, guard conditions, and bailout mechanisms.

## 2. Implementation
- [x] 2.1 Implement eligibility detection for numeric `for` loops (and `ipairs`-style loops) inside the interpreter.
- [x] 2.2 Add a specialized loop executor that reuses the loop environment and avoids per-iteration resets.
- [x] 2.3 Implement fallback triggers when the body performs unsupported operations (metamethods, locals, control flow).

## 3. Validation
- [x] 3.1 Extend unit tests covering fast path vs. fallback scenarios and control-flow edge cases (break/return/goto).
- [x] 3.2 Benchmark using `dart run tool/table_bench.dart` and relevant Lua scripts (`constructs.lua`, `sort.lua`) to record improvements.
- [x] 3.3 Document benchmark results and update any relevant performance guidance.

## 4. Documentation & Cleanup
- [x] 4.1 Update developer docs/specs to note the loop fast-path behaviour and guardrails.
- [x] 4.2 Ensure logging, profiling, and formatting remain clean; remove temporary instrumentation.
