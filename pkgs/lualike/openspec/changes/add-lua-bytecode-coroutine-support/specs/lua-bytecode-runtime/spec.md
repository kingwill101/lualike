## ADDED Requirements

### Requirement: Bytecode Coroutines Suspend And Resume Through The Runtime
The `lua_bytecode` runtime SHALL support coroutine suspension and resumption for the supported bytecode subset.

#### Scenario: A bytecode-backed coroutine can yield and resume
- **WHEN** a supported `lua_bytecode` closure running inside `coroutine.create(...)` calls `coroutine.yield(...)`
- **THEN** the runtime suspends the bytecode execution state instead of treating the yield as a terminal error
- **AND** a later `coroutine.resume(...)` continues from the saved bytecode state with the resume arguments delivered to the yield boundary

#### Scenario: Bytecode frame state survives yield boundaries
- **WHEN** a supported bytecode coroutine yields with nested bytecode frames, open upvalues, or closeable registers still active
- **THEN** the runtime preserves the program counters, registers, open upvalues, and supported close state needed to resume execution correctly
- **AND** the resumed execution produces the same observable results as the tracked upstream behavior for the supported subset

#### Scenario: Bytecode coroutine close paths preserve runtime consistency
- **WHEN** a supported bytecode coroutine is closed after yielding or while suspended
- **THEN** the runtime releases the saved bytecode continuation state and transitions the thread to `dead`
- **AND** it does not leave current-coroutine, current-environment, or closeable-resource bookkeeping in a corrupted state

### Requirement: Bytecode Coroutine Claims Are Backed By Real Chunk And Source Behavior
The `lua_bytecode` runtime SHALL only claim coroutine support for paths validated with real bytecode execution.

#### Scenario: Upstream-generated coroutine chunks are validated
- **WHEN** the runtime claims support for a coroutine-related bytecode path
- **THEN** that path is validated with targeted chunks produced by the tracked upstream `luac`
- **AND** the tests assert real execution results for create/resume/yield/wrap/close behavior in the supported subset

#### Scenario: Source-engine bytecode coroutines execute without fallback
- **WHEN** a caller selects the `lua_bytecode` source engine for a supported coroutine-using program
- **THEN** the program executes through emitted `lua_bytecode` plus the `lua_bytecode` runtime
- **AND** it does not silently reinterpret the coroutine path through AST or `lualike_ir`

#### Scenario: Unsupported bytecode coroutine paths fail explicitly
- **WHEN** a chunk or emitted program reaches a coroutine-related bytecode path still outside the supported subset
- **THEN** the runtime fails with an explicit `lua_bytecode` coroutine diagnostic
- **AND** it does not silently continue with partially-corrupted execution state
