## ADDED Requirements

### Requirement: Numeric For Loop Fast Path
Numeric `for` loops that meet safe criteria MUST execute via a specialized path that reuses the loop environment and avoids per-iteration rebuilds while preserving Lua semantics.

#### Scenario: simple numeric loop optimization
- **GIVEN** a `for i = 1, 1000 do ... end` loop with straight-line statements (no locals/metamethods)
- **THEN** the interpreter MUST reuse the existing environment and loop counter without invoking the generic environment reset on each iteration.
- **AND** benchmarking with `dart run tool/table_bench.dart 1000 1` MUST show an improvement over the baseline table-only optimization.

#### Scenario: guard fallback for complex loops
- **GIVEN** a numeric `for` loop whose body introduces locals, metamethods, or control flow (`break`, `goto`)
- **THEN** the interpreter MUST fall back to the existing loop execution path so behaviour matches stock Lua.

### Requirement: Loop Fast Path Validation
Regression tests MUST cover fast path execution, bailout conditions, and numeric loop correctness.

#### Scenario: loop fast path test coverage
- **GIVEN** new unit/integration tests targeting the specialized executor
- **THEN** they MUST assert both the optimized execution path and fallback semantics (including `break`/`return` handling).

### Requirement: `ipairs` Loop Fast Path
`for`-in loops written as `for i, v in ipairs(t)` MUST short-circuit through the fast executor when the table uses `TableStorage` and the body is eligible, while preserving Lua semantics.

#### Scenario: simple `ipairs` iteration
- **GIVEN** a loop `for i, v in ipairs({1,2,3}) do sum = sum + v end`
- **THEN** the interpreter MUST reuse the loop environment, advancing the counter via the specialized executor without invoking the generic iterator each iteration.

#### Scenario: `ipairs` fallback when locals declared
- **GIVEN** a loop `for i, v in ipairs(t) do local shadow = v; ... end`
- **THEN** the guards MUST fall back to the generic iterator path so that scoped locals are cleared between iterations.
