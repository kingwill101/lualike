## MODIFIED Requirements

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Supported table constructors compile to executable chunks
- **WHEN** the emitter compiles a supported table-constructor expression
- **THEN** it emits a real `lua_bytecode` chunk using the supported table
  opcode family
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Supported table field and index stores compile to executable chunks
- **WHEN** the emitter compiles a supported assignment target such as
  `t.x = v` or `t[i] = v`
- **THEN** it emits a real `lua_bytecode` chunk using the supported table
  store opcode family
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Unsupported constructor or store forms fail explicitly
- **WHEN** source compilation reaches a constructor or assignment-target
  form still outside the supported emitter subset
- **THEN** compilation fails with an explicit `lua_bytecode` emitter
  diagnostic
- **AND** it does not silently reinterpret the source through AST or
  `lualike_ir`
