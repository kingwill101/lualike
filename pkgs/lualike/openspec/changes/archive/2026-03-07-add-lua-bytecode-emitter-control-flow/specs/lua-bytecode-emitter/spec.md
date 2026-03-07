## MODIFIED Requirements

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Structured control flow compiles to executable chunks
- **WHEN** the emitter compiles supported branches, loops, returns, and
  other structured control-flow forms
- **THEN** it emits real `lua_bytecode` chunks that execute through the
  runtime
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Supported functions and closures compile with correct scope metadata
- **WHEN** the emitter compiles supported nested functions, closures, and
  upvalue-aware scopes
- **THEN** the emitted chunk preserves the scope, closure, and return
  semantics required by the supported subset
- **AND** the results match runtime execution of the same source behavior
