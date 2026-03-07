## MODIFIED Requirements

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Generic `for` loops compile to executable chunks
- **WHEN** the emitter compiles a supported generic `for` loop
- **THEN** it emits real `lua_bytecode` chunks that execute through the
  runtime using the supported `TFOR*` loop family
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: `repeat ... until` loops compile to executable chunks
- **WHEN** the emitter compiles a supported `repeat ... until` loop
- **THEN** it emits real `lua_bytecode` chunks that execute through the
  runtime with body-first and condition-later semantics
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Repeat-loop locals remain visible to the terminating condition
- **WHEN** the emitter compiles a `repeat ... until` loop where the
  terminating condition references a local declared in the body
- **THEN** the emitted chunk preserves that scope visibility
- **AND** it does not compile the condition as if it were outside the
  repeat-body scope

#### Scenario: Unsupported control-flow families stay explicitly diagnostic
- **WHEN** source compilation reaches labels, `goto`, or another
  control-flow family still outside the supported emitter subset
- **THEN** compilation fails with an explicit `lua_bytecode` emitter
  diagnostic
- **AND** it does not silently fall back to AST or `lualike_ir`
