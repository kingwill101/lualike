## ADDED Requirements
### Requirement: Bytecode Closures Support Upvalue Mutation
Bytecode-compiled closures MUST emit and execute `SETUPVAL` so assignments to captured locals behave identically to the AST interpreter.

#### Scenario: Inner Closure Increments Captured Counter
- **GIVEN** `local count = 0; local function bump() count = count + 1 return count end`
- **WHEN** the script runs in bytecode mode
- **THEN** the compiler emits `SETUPVAL` for the assignment to `count`
- **AND** each call to `bump()` returns incrementing integers, matching AST execution.

### Requirement: Bytecode Handles Method Definitions and `_ENV` Assignments
Bytecode compilation MUST lower method declarations and `_ENV` updates into `SETTABUP` / `SETTABLE` so the VM mutates the correct table while preserving implicit `self` semantics.

#### Scenario: Table Method Defined Via `function t:foo()`
- **GIVEN** `local t = {}; function t:foo(v) self.value = v end; t:foo(42); return t.value`
- **WHEN** executed in bytecode mode
- **THEN** the compiler emits a `CLOSURE` followed by the appropriate table store (`SETTABUP`/`SETTABLE`)
- **AND** the VM installs the method such that the subsequent call sets `t.value` to `42`, matching AST behavior.

#### Scenario: `_ENV` Assignment Uses Table Store
- **GIVEN** `_ENV.result = 11; return result`
- **WHEN** executed in bytecode mode
- **THEN** the bytecode writes through `_ENV` using `SETTABUP`
- **AND** the VM returns `11`, matching AST execution.
