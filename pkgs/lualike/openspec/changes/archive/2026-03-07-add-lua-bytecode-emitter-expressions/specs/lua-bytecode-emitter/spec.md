## MODIFIED Requirements

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Core expression families compile to executable chunks
- **WHEN** the emitter compiles supported literal, local, global, unary,
  binary, concatenation, table-access, method-selection, and supported call
  expressions
- **THEN** it emits real `lua_bytecode` chunks that execute through the
  runtime
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Emitted expression chunks stay inside the supported runtime envelope
- **WHEN** the emitter compiles an expression family supported by the
  current emitter slice
- **THEN** the emitted instructions stay within the `lua_bytecode` runtime
  subset already backed by oracle tests
- **AND** unsupported expression families fail explicitly during
  compilation instead of emitting unverified bytecode
