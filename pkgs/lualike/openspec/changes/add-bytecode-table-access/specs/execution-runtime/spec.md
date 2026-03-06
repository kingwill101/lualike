## ADDED Requirements
### Requirement: Bytecode Table Access
The bytecode compiler and VM SHALL evaluate table reads (`t[k]`, `t.key`) using the appropriate Lua 5.4 opcodes with behaviour identical to the AST interpreter, including metamethod handling.

#### Scenario: Table Field Access
- **GIVEN** a script `return obj.value`
- **WHEN** it runs in bytecode mode
- **THEN** the compiler emits `GETFIELD`
- **AND** the VM retrieves the same result (including metamethod behaviour) as the AST interpreter.

#### Scenario: Table Index Access with Integer Literal
- **GIVEN** a script `return arr[1]`
- **WHEN** it executes in bytecode mode
- **THEN** the compiler emits `GETI`
- **AND** the VM returns the same value as the AST interpreter for array-style tables.

#### Scenario: Table Index Access with Dynamic Key
- **GIVEN** a script `return table[key]`
- **AND** `key` is computed at runtime
- **WHEN** the script runs in bytecode mode
- **THEN** the compiler emits `GETTABLE`
- **AND** the VM matches the AST interpreter, including `__index` metamethods.
