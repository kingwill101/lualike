## MODIFIED Requirements

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Labels and goto compile to executable chunks
- **WHEN** the emitter compiles a supported source program containing
  labels and `goto`
- **THEN** it emits real `lua_bytecode` chunks that execute through the
  runtime with the expected control-flow behavior
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Forward and backward goto fixups are resolved before emission completes
- **WHEN** the emitter compiles a supported source program containing
  forward or backward gotos
- **THEN** all supported goto targets are resolved to concrete jump
  destinations before compilation completes
- **AND** the emitted chunk does not leave unresolved placeholder jumps

#### Scenario: Unsupported or unresolved gotos fail explicitly
- **WHEN** source compilation reaches a goto that has no visible supported
  label target
- **THEN** compilation fails with an explicit `lua_bytecode` emitter
  diagnostic
- **AND** it does not silently reinterpret the source through AST or
  `lualike_ir`
