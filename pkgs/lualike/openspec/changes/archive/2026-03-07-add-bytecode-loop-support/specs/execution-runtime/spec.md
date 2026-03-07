## ADDED Requirements
### Requirement: Bytecode `for` Loop Support
The bytecode compiler and VM SHALL execute both numeric and generic `for` loops using the Lua 5.4 loop opcodes (`FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, `TFORLOOP`) with behaviour matching the AST interpreter.

#### Scenario: Numeric Loop Increments
- **GIVEN** `sum = 0; for i = 1, 3 do sum = sum + i end`
- **WHEN** the script runs in bytecode mode
- **THEN** the compiler emits `FORPREP`/`FORLOOP` for the loop
- **AND** the VM produces `sum == 6`, identical to the AST interpreter.

#### Scenario: Numeric Loop With Negative Step
- **GIVEN** `count = 0; for i = 3, 1, -1 do count = count + 1 end`
- **WHEN** executed in bytecode mode
- **THEN** the loop iterates three times, matching interpreter semantics for descending steps.

#### Scenario: Generic Loop Uses Iterator Results
- **GIVEN** `sum = 0; for idx, value in iter, state, control do sum = sum + value end`
- **WHEN** the script runs in bytecode mode with `iter`, `state`, and `control` pre-bound globals
- **THEN** the compiler emits `TFORPREP`/`TFORCALL`/`TFORLOOP`
- **AND** the VM consumes iterator results to produce the same `sum` as the AST interpreter (including respecting iterator-provided values).
