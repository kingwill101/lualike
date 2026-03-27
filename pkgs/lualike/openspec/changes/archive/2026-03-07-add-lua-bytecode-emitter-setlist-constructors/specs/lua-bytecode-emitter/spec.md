## MODIFIED Requirements

### Requirement: The Emitter Foundation Produces Real Executable Chunks
The system SHALL emit real `lua_bytecode` chunks for the supported
foundation subset.

#### Scenario: Minimal emitted programs execute through the runtime
- **WHEN** the emitter compiles a program in the supported foundation
  subset
- **THEN** the output is a real `lua_bytecode` chunk that can be parsed,
  disassembled, and executed by the `lua_bytecode` runtime
- **AND** the observed behavior matches the expected source semantics for
  that subset

#### Scenario: Core expression families compile to executable chunks
- **WHEN** the emitter compiles supported literal, local, global, unary,
  binary, concatenation, table-access, method-selection, and supported
  call expressions
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

#### Scenario: Structured control flow compiles to executable chunks
- **WHEN** the emitter compiles supported branches, loops, returns, and
  other structured control-flow forms
- **THEN** it emits real `lua_bytecode` chunks that execute through the
  runtime
- **AND** the observed behavior matches the source semantics for the
  supported subset

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

#### Scenario: Labels and goto compile to executable chunks
- **WHEN** the emitter compiles a supported source program containing
  labels and `goto`
- **THEN** it emits real `lua_bytecode` chunks that execute through the
  runtime
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Unsupported goto visibility stays explicitly diagnostic
- **WHEN** source compilation reaches a `goto` without a visible supported
  label target
- **THEN** compilation fails with an explicit `lua_bytecode` emitter
  diagnostic
- **AND** it does not silently reinterpret the source through AST or
  `lualike_ir`

#### Scenario: Unsupported control-flow families stay explicitly diagnostic
- **WHEN** source compilation reaches another control-flow family still
  outside the supported emitter subset
- **THEN** compilation fails with an explicit `lua_bytecode` emitter
  diagnostic
- **AND** it does not silently fall back to AST or `lualike_ir`

#### Scenario: Supported functions and closures compile with correct scope metadata
- **WHEN** the emitter compiles supported nested functions, closures, and
  upvalue-aware scopes
- **THEN** the emitted chunk preserves the scope, closure, and return
  semantics required by the supported subset
- **AND** the results match runtime execution of the same source behavior

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

#### Scenario: Supported trailing open-result constructor entries compile to executable chunks
- **WHEN** the emitter compiles a supported constructor whose final array
  entry is a call or method call such as `{f()}` or `{1, g()}`
- **THEN** it emits a real `lua_bytecode` chunk using the supported
  `SETLIST` / `EXTRAARG` constructor family
- **AND** the observed behavior matches Lua constructor expansion
  semantics for the supported subset

#### Scenario: Large contiguous constructors emit executable `SETLIST` chunks
- **WHEN** the emitter compiles a supported constructor whose contiguous
  array portion exceeds the inline constructor store shape
- **THEN** it emits a real `lua_bytecode` chunk using `SETLIST` and
  `EXTRAARG` as needed
- **AND** the observed behavior matches the source semantics for the
  supported subset

#### Scenario: Unsupported constructor or store forms fail explicitly
- **WHEN** source compilation reaches a constructor or assignment-target
  form still outside the supported emitter subset
- **THEN** compilation fails with an explicit `lua_bytecode` emitter
  diagnostic
- **AND** it does not silently reinterpret the source through AST or
  `lualike_ir`
