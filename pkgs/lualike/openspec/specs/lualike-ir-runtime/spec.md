## Purpose

Define the contract for `lualike_ir` as lualike's internal compiled
execution and serialization format.

## Requirements

### Requirement: Lualike IR Is A Distinct Runtime Format
The system SHALL define `lualike_ir` as an internal execution and
serialization format that is distinct from upstream Lua bytecode and is
identified as such in code, tooling, and documentation.

#### Scenario: Internal runtime artifacts are classified correctly
- **WHEN** a program is compiled for the internal non-AST execution path
- **THEN** the resulting artifact is identified as `lualike_ir`
- **AND** it is not described or exposed as upstream Lua bytecode
  compatibility

### Requirement: Lualike IR Supports Cached Execution
The system SHALL support serializing and loading `lualike_ir` programs so
lualike programs can be executed without recompiling from source on every
run.

#### Scenario: Cached IR is executed without source recompilation
- **WHEN** a lualike program has already been compiled to `lualike_ir`
- **THEN** the runtime can load and execute the serialized IR artifact
  directly
- **AND** the execution path does not require reconstructing the program
  from AST transport data

### Requirement: Legacy Chunk Transport Is Not The IR Contract
The system SHALL treat the existing AST-oriented chunk transport as
legacy/internal compatibility behavior and SHALL NOT use it as the
defining serialization contract for `lualike_ir`.

#### Scenario: IR serialization uses its own contract
- **WHEN** the runtime serializes a program for `lualike_ir` caching or
  execution
- **THEN** it uses an IR-specific serialization path
- **AND** the path does not rely on fake Lua binary-chunk compatibility
  claims
