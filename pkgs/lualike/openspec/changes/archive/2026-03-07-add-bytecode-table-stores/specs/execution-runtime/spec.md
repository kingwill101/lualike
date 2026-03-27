## ADDED Requirements
### Requirement: Bytecode Table Write Support
The bytecode compiler and VM SHALL handle table assignments (`tbl.key = v`, `tbl[index] = v`) using the appropriate Lua 5.4 opcodes with behaviour identical to the AST interpreter, including metamethod handling.

#### Scenario: Table Field Assignment
- **GIVEN** a script `tbl.value = 5`
- **WHEN** it runs in bytecode mode
- **THEN** the compiler emits `SETFIELD`
- **AND** the VM updates the table exactly as the AST interpreter would.

#### Scenario: Table Index Assignment with Integer Literal
- **GIVEN** a script `arr[1] = 2`
- **WHEN** it executes in bytecode mode
- **THEN** the compiler emits `SETI`
- **AND** the VM stores the value in the same array slot as the AST interpreter.

#### Scenario: Table Index Assignment with Dynamic Key
- **GIVEN** a script `t[key] = value`
- **WHEN** `key` is computed at runtime
- **THEN** the compiler emits `SETTABLE`
- **AND** the VM honours `__newindex` metamethods, matching interpreter semantics.
