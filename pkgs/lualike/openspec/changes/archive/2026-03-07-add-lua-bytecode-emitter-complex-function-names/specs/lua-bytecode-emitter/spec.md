## MODIFIED Requirements

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Dotted function-name definitions compile to executable chunks
- **WHEN** the emitter compiles a supported function definition with a
  dotted table path such as `function t.add(...) end`
- **THEN** it emits a real `lua_bytecode` chunk that installs the emitted
  closure onto the resolved table path
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Method-style function definitions compile with implicit self
- **WHEN** the emitter compiles a supported method-style definition such as
  `function t:inc(...) end`
- **THEN** it emits a real `lua_bytecode` chunk whose child prototype
  expects an implicit leading `self`
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Complex function-name paths stay inside the supported runtime envelope
- **WHEN** the emitter compiles a supported dotted or method-style
  function-name definition
- **THEN** the emitted instructions stay within the `lua_bytecode` runtime
  subset already backed by oracle tests
- **AND** unsupported function-definition families fail explicitly during
  compilation instead of emitting unverified bytecode
