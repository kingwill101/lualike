## MODIFIED Requirements

### Requirement: Lua Binary Chunks Are Parsed And Executed According To Upstream Semantics

#### Scenario: Table access and store follow upstream chunk semantics
- **WHEN** a real upstream chunk performs table field, integer-key, or
  generic-key access and store operations
- **THEN** the `lua_bytecode` runtime follows the tracked upstream table
  semantics for the supported instruction set
- **AND** the behavior is validated with targeted upstream-generated
  fixtures

#### Scenario: Table construction honors `NEWTABLE` / `SETLIST` / `EXTRAARG`
- **WHEN** a real upstream chunk constructs tables using list-style writes
  or constructor patterns emitted by the tracked `luac`
- **THEN** the runtime honors the register, index, and `EXTRAARG`
  semantics required by those chunk patterns
- **AND** the resulting table contents match upstream execution

#### Scenario: `LEN` follows upstream semantics for supported table cases
- **WHEN** a real upstream chunk applies `LEN` to values covered by the
  current runtime subset
- **THEN** the runtime follows the tracked upstream semantics for strings,
  supported table cases, and supported `__len` behavior
- **AND** unsupported cases fail explicitly instead of silently returning a
  container-specific shortcut
