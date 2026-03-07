## MODIFIED Requirements

### Requirement: Runtime Services Are Exposed Through An Engine Boundary

#### Scenario: The engine boundary supports emitted source-bytecode execution
- **WHEN** a caller selects the source-backed `lua_bytecode` engine path
- **THEN** shared runtime services such as loading, execution, and supported
  dump/debug hooks operate through the engine boundary
- **AND** stdlib and higher-level tooling do not need direct knowledge of
  AST-specific or IR-specific implementation details for that path
