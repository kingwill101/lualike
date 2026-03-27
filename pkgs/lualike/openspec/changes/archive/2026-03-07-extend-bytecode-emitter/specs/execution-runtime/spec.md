## ADDED Requirements
### Requirement: Bytecode Arithmetic Expression Support
The bytecode compiler and VM MUST evaluate arithmetic expressions involving literals and global identifiers so scripts using `+`, `-`, `*`, or `/` run identically under bytecode and AST execution.

#### Scenario: Bytecode Handles Literal Arithmetic
- **GIVEN** a script `return 1 + 2 * 3`
- **WHEN** it is executed with the bytecode engine
- **THEN** the compiler emits arithmetic opcodes consumed by the VM
- **AND** the program returns `7`.

#### Scenario: Bytecode Reads Globals in Arithmetic Expressions
- **GIVEN** a script `return x * 2`
- **AND** the global environment contains `x = 4`
- **WHEN** it executes via the bytecode engine
- **THEN** the VM resolves `x` from the environment using the emitted `GETTABUP`
- **AND** the program returns `8`.
