## ADDED Requirements
### Requirement: Bytecode Opcode Coverage Plan
The project MUST maintain a structured plan capturing every Lua 5.4 bytecode opcode, its emitter implementation tasks, VM execution tasks, and associated validation work so that bytecode execution can reach feature parity with the AST interpreter.

#### Scenario: Opcode Matrix Established
- **GIVEN** the Lua 5.4 opcode inventory
- **WHEN** contributors review the bytecode plan
- **THEN** they find each opcode listed with compiler and VM ownership, prerequisites, and open issues.

#### Scenario: Validation & Benchmark Tasks Defined
- **GIVEN** the bytecode coverage plan
- **WHEN** new opcode support is scheduled
- **THEN** the plan specifies the tests, parity checks, and benchmark updates required to confirm correct behaviour.
