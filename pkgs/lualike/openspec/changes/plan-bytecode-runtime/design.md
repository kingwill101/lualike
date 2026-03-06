# Bytecode Runtime Integration Design

## Summary
This document captures the planned architecture for introducing a bytecode execution pipeline into lualike without rewriting the existing stdlib or runtime helpers. We will surface a shared runtime abstraction, lower AST programs into bytecode chunks via an emitter, and implement a VM that reuses current runtime services.

## 1. Inventory & Constraints
- AST interpreter lives in `lib/src/interpreter/` with mixins per feature (assignment, control flow, literals, tables).
- Shared components (e.g. `LibraryRegistry`, `Value`, `Environment`, GC managers) keep direct `Interpreter` references.
- Entry flow: `executeCode` → `Interpreter.run` parses AST and executes synchronously.
- Lua requirements retained: coroutines, metamethods, tail calls, varargs, metamethod dispatch, error formatting.
- txtlang reference shows: stack-oriented compiler → register bytecode (`RegInstr`) → VM with shared `Value` types.

## 2. Target Runtime Interface
We plan a `LuaRuntime` interface (exact name TBD) exposing:
- Environment access: `globals`, current environment switching, environment cloning used by stdlib and file manager.
- Call stack introspection: needed for error traces (`lua_stack_trace.dart`) and coroutine status outputs.
- Coroutine management: create/ resume/ yield operations reused by coroutine stdlib modules.
- GC hooks: registering tables/upvalues with `GenerationalGCManager` and exposing GC access as in `gc_access.dart`.
- Value services: literal interning, number coercions, metamethod invocation helpers.
- Logging/error reporting: wrapper around `Logger` usage inside interpreter.
All existing consumers must depend on this interface, enabling the bytecode VM to supply equivalent behaviour.

### Interpreter Surface in Use
- **Environment & Globals**: `globals`, `getCurrentEnv()`, `setCurrentEnv()`, and `libraryRegistry` are relied on by stdlib initialization (`lib/src/stdlib/init.dart`, `library.dart`), base/packaging libraries, coroutine helpers, and module loaders to wire `_G`, swap environments for `load`/`require`, and register lazy namespaces.
- **Execution APIs**: `run()`, `callFunction()`, and `evaluate()` back `executeCode`, stdlib loaders (`load`, `dofile`, `require`), metamethod dispatch in `Value`, and Dart interop (`lib/src/interop.dart`).
- **Call Stack & Debugging**: consumers access `callStack` (`current`, `frames`, `top`, `depth`, `getFrameAtLevel`, `scriptPath`, `setScriptPath`) plus `currentScriptPath` and `evalStack` for debug library introspection, stack traces, coroutine bookkeeping, and GC root enumeration.
- **Coroutine Management**: `registerCoroutine()`, `unregisterCoroutine()`, `getCurrentCoroutine()`, `setCurrentCoroutine()`, and `getMainThread()` are exercised by `lib/src/stdlib/lib_coroutine.dart` and `lib/src/coroutine.dart` to manage lifecycle and status reporting.
- **Protected Calls & Yieldability**: `enterProtectedCall()`, `exitProtectedCall()`, `isInProtectedCall`, and `isYieldable` enforce `pcall`/`xpcall` semantics and coroutine resume guards in `lib_base.dart`.
- **Garbage Collection**: `gc` (ensureTracked, stepping/tuning, major/minor collections) together with `getRoots()` feed collectgarbage implementations, `GCAccess`, `Environment`, `Upvalue`, and `GenerationalGCManager.buildRootSet`.
- **File & Module Resolution**: `fileManager` (load/resolve) and `currentScriptPath` are touched by `loadfile`, `dofile`, `require`, the package library, and the `FileManager` itself when adjusting search paths.
- **Error Reporting**: `reportError()` is invoked by `executeCode` and stdlib helpers to surface Lua-style diagnostics.
- **Interop Surface**: `globals`, `fileManager.addSearchPath`, `currentScriptPath`, and the execution APIs support the Dart bridge in `lib/src/interop.dart`.

### Proposed `LuaRuntime` Interface
We will introduce an abstract interface (likely `abstract interface class LuaRuntime`) that clusters the surfaces above into cohesive capability groups while hiding Interpreter-only internals:
- **Environment/Globals**
  - `Environment get globals`
  - `Environment getCurrentEnv()`, `void setCurrentEnv(Environment env)`
  - `Environment cloneEnvironment(Environment env, {bool isClosure, bool isLoadIsolated})` (helper wrapping `Environment.clone`)
- **Execution & Invocation**
  - `Future<Object?> runAst(List<AstNode> program)` (current interpreter implementation delegates to `run`)
  - `Future<Object?> callFunction(Value function, List<Object?> args)`
  - `Future<Object?> evaluateAst(AstNode node)` for loaders/metamethods that execute AST fragments
- **Call Stack & Debugging**
  - `CallStackView get callStack` (lightweight view exposing read-only frame data, `setScriptPath`, `push`, `pop`)
  - `Stack get evalStack` (or a wrapper exposing iteration for GC)
  - `String? get currentScriptPath`, `set currentScriptPath(String? value)`
- **Coroutine Lifecycle**
  - `Coroutine? getCurrentCoroutine()`, `void setCurrentCoroutine(Coroutine? coroutine)`
  - `Coroutine getMainThread()`
  - `void registerCoroutine(Coroutine coroutine)`, `void unregisterCoroutine(Coroutine coroutine)`
- **Protected Call Semantics**
  - `void enterProtectedCall()`, `void exitProtectedCall()`
  - `bool get isInProtectedCall`
  - `bool get isYieldable`, `set isYieldable(bool value)`
- **Garbage Collection**
  - `GenerationalGCManager get gc`
  - `List<Object?> getRoots()` (or a view) for collectors/tests
- **Modules & IO**
  - `FileManager get fileManager`
  - `LibraryRegistry get libraryRegistry`
- **Diagnostics**
  - `void reportError(String message, {StackTrace? trace, Object? error})`
  - `Logger get logger` (or statics left unchanged)

The existing `Interpreter` supplies all of the above today; we will implement the interface as a thin wrapper delegating to the current methods/fields. Sealed subclasses (AST interpreter, bytecode VM) can inherit shared mixins for optional behaviour (e.g., `LuaRuntimeWithAst` providing `runAst` defaulting to call `run`).

### Components to Rewire to `LuaRuntime`
- **Stdlib & Library System** – `Library`, `LibraryRegistry`, `initializeStandardLibrary`, and every `Library` subclass currently store a concrete `Interpreter`. They will accept a `LuaRuntime` instead, holding the runtime for callbacks (`lib/src/stdlib/library.dart`, `lib/src/stdlib/lib_*`).
- **Values & Builtins** – `Value.interpreter`, `_resolveInterpreter`, and `BuiltinFunction.interpreter` will store a `LuaRuntime` reference so metamethod invocation and builtin calls work under either engine (`lib/src/value.dart`, `lib/src/builtin_function.dart`).
- **Environment & Coroutines** – `Environment.interpreter`, `Environment.clone`, `Coroutine.closureEnvironment.interpreter`, and `Upvalue` constructors capture the runtime via the interface (`lib/src/environment.dart`, `lib/src/coroutine.dart`, `lib/src/upvalue.dart`).
- **GC Utilities** – `GCAccess` and `GenerationalGCManager` depend on `Interpreter` for GC roots; they will reference `LuaRuntime.gc`/`getRoots()` instead (`lib/src/gc/gc_access.dart`, `lib/src/gc/generational_gc.dart`).
- **File/Module Handling** – `FileManager` setup and package/loader code read `interpreter.fileManager` and `currentScriptPath`; update to use the runtime interface (`lib/src/file_manager.dart`, `lib/src/stdlib/lib_base.dart`, `lib/src/stdlib/lib_package.dart`).
- **Interop Bridge** – `lib/src/interop.dart` will accept a `LuaRuntime` so embedding code can pick the engine at construction time.
- **Execution Entry Points** – `executeCode`, tests, and tooling will accept a `LuaRuntime` or engine selector instead of assuming `Interpreter`.

### Current AST Execution Flow
1. **Entry (`executeCode`)** – `lib/src/executor.dart:18` parses source with `parse()`, runs the const checker, constructs (or reuses) an `Interpreter`, allows optional setup, then invokes `Interpreter.run`.
2. **Interpreter bootstrap** – `Interpreter.run` (`lib/src/interpreter/interpreter.dart:637`) normalises script metadata (sets `currentScriptPath`, primes `callStack`), clears `evalStack`, and creates a per-script `Environment` layered over globals.
3. **Statement loop** – `_executeStatements` (`lib/src/interpreter/interpreter.dart:749`) constructs a label map, iterates AST nodes, and dispatches each via visitor methods, handling `goto`, `return`, and tail-call exceptions.
4. **Mixins per concern** – Visitor methods in `assignment.dart`, `control_flow.dart`, `expression.dart`, etc., execute directly against interpreter state (env stack, eval stack, GC hooks, coroutine APIs).
5. **Result propagation** – Upon completion `run` restores the previous environment/script path, pops the frame, and returns the top of `evalStack`, while exceptions bubble to callers (`executeCode`, stdlib loaders, interop bridge).

**Seams for Bytecode Integration**
- **Execution selection**: `executeCode` is the choke point to swap `Interpreter.run` for a bytecode pipeline once a mode flag is introduced.
- **Program representation**: After parsing, the AST is immediately executed; inserting a compiler step (AST → bytecode chunk) here requires minimal disruption.
- **Runtime services**: All visitor logic reaches shared state through the surfaces enumerated above; once those surfaces live on a runtime interface, a bytecode VM can bind to the same services without touching callers.

## 3. Bytecode Chunk Layout
- **Header (Lua-compatible)**: Emit the standard 32-byte Lua header (`\x1B Lua`, version `0x54`, format `0`, signature `0x19 93 0D 0A 1A 0A`, instruction size 4, integer/float size 8, LUAC_INT `0x5678`, LUAC_NUM `370.5`) so chunks pass Lua’s loader. Add a single feature-flag byte immediately afterward (bitmask for debug info, constant hashes, etc.); zero keeps vanilla compatibility.
- **Prototype Records**: Mirror Lua’s `Proto` layout for each function:
  - Scalars: `registerCount`, `paramCount`, `isVararg`, `upvalueCount`, `lineDefined`, `lastLineDefined`.
  - Instruction stream: 32-bit words encoded with official opcode layouts (iABC, iABx, iAsBx, etc.). We preserve opcode ordering and operand semantics from `lopcodes.h`.
  - Constants: length-prefixed table of typed constants (`nil`, `boolean`, `integer`, `number`, `short string`, `long string`). When loading, reuse existing `Value` wrappers to avoid double boxing.
  - Nested prototypes: count + child proto blobs for closures.
  - Upvalue descriptors: `{inStack, index, kind}` triples exactly like Lua 5.4.
- **Debug Tables (flagged)**: When debug flag set, append run-length encoded line info, local variable ranges, upvalue names, and canonical source path (UTF-8). When flag cleared, omit entirely for compact release builds.
- **Trailer Extensions (optional)**: Allow optional blocks (e.g., constant hash table, checksum) referenced by flag bits; parsers skip unknown blocks via length prefixes to maintain forward compatibility.

Existing `ChunkSerializer` already understands Lua headers for `string.dump`; we will extend it to read/write the richer prototype structure and honour the flag byte.

## 4. Compilation Pipeline Design
- AST Passes: reuse current parser + upvalue analysis (`upvalue_analyzer.dart`, `upvalue_assignment.dart`) to annotate closures.
- CodeEmitter abstraction: mirror txtlang `CodeEmitter`—stack-based interface with operations (`emitPushConstant`, `emitBinaryOp`, `emitJump`, etc.). AST walker drives this emitter; current mixins become lowering passes able to target both AST eval and bytecode emission.
- Intermediate Representation: choose register-based bytecode for predictable performance; instruction inventory SHALL mirror Lua 5.4 opcodes (`lopcodes.h`), preserving operand layouts (iABC, iAsBx, etc.), k-flags, and extra-argument handling. Document any deviations explicitly.
- Tooling: serialization helpers (mirroring `chunk_serializer.dart`), debug dump for development.
- Implementation style: model bytecode IR and related events as Dart `sealed` class hierarchies and leverage Dart 3 pattern matching (exhaustive switch over AST nodes/opcodes, destructuring records) to keep lowering logic and VM dispatch legible while aligning with modern language idioms.

### CodeEmitter & IR Strategy
- **Emitter Contract**: Define an abstract/sealed `BytecodeEmitter` exposing high-level operations aligned with Lua opcodes (e.g., `emitLoadK`, `emitLoadBool`, `emitGetUpval`, `emitSetTable`, arithmetic `emitAdd`, `emitAddK`, bitwise ops, `emitJmp`, `emitTestSet`, `emitForPrep`, `emitCall`, `emitReturn`, `emitClosure`, `emitVarArg`, `emitSetList`). Methods accept typed operands (register indices, constant refs, signed offsets, k-flags) so emitters can validate constraints.
- **Op Modeling**: Represent each opcode as an immutable sealed class (`Move`, `LoadK`, `Add`, `AddK`, `ForLoop`, etc.) carrying explicit fields; this improves readability and allows analysis/optimisation passes before packing.
- **Packing Phase**: After AST lowering, convert `BytecodeOp` instances into 32-bit instruction words using `lopcodes.h` bit layouts. Common helpers encode operand modes and k-flags, ensuring parity with Lua semantics.
- **AST Lowering Mixins**: Refactor interpreter mixins (expression, control flow, functions) to share logic between immediate execution and code emission. When in “emit” mode, they call the emitter instead of mutating interpreter state.
- **Metadata Generation**: Collect constant pool entries, upvalue descriptors, and debug info during emission; assemble prototypes and hand off to the chunk writer.
- **Validation & Debugging**: Provide optional emitter tracing (`--debug` flag) that dumps the `BytecodeOp` list alongside packed instructions, aiding comparison with Lua’s own compiler.

### Opcode Coverage & Planned Deviations
- **Move & Loads**
  - `OP_MOVE`, `LOADI`, `LOADF`, `LOADK`, `LOADKX`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`, `LOADNIL`: stack/register moves and literals implemented exactly; `LFALSESKIP` performs boolean conversion and skips the following instruction when required.
- **Upvalues & Environments**
  - `GETUPVAL`, `SETUPVAL`, `GETTABUP`, `SETTABUP` follow Lua semantics with short-string fast paths and fallback metamethods.
- **Table Accessors**
  - `GETTABLE`, `SETTABLE`, `GETI`, `SETI`, `GETFIELD`, `SETFIELD`, `SELF` reuse fast get/set helpers and `luaV_finishget/set`; they respect metamethod chaining limits (`MAXTAGLOOP`).
- **Table Construction**
  - `NEWTABLE`, `SETLIST` honour array/hash sizing, EXTRAARG extension, and sequential inserts identical to Lua 5.4.
- **Arithmetic**
  - Register variants `ADD`…`IDIV`, immediate (`*_I`, `*_K`), and metamethod dispatch (`MMBIN`, `MMBINI`, `MMBINK`) all map 1:1; numeric conversions use `luaV_tonumber`, `luaV_tointeger` helpers. Division/mod instructions guard against zero and follow Lua rounding.
- **Bitwise**
  - `BAND`, `BOR`, `BXOR`, `SHL`, `SHR`, plus immediates `BANDK`, `BORK`, `BXORK`, `SHLI`, `SHRI`—implemented via integer conversion helpers and `luaV_shiftl`.
- **Unary Ops**
  - `UNM`, `BNOT`, `NOT`, `LEN` match interpreter semantics, including metamethod fallback for `__unm`, `__bnot`, `__len`.
- **Concatenation**
  - `CONCAT` mirrors `luaV_concat` (buffer allocate, metamethod fallback).
- **Comparison & Tests**
  - `EQ`, `LT`, `LE`, `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI`, `TEST`, `TESTSET` follow number/string fast paths with metamethod fallbacks (`TM_EQ`, `TM_LT`, `TM_LE`) and k-flag semantics identical to Lua.
- **Control Flow**
  - `JMP`, conditional skip macros (`docondjump`) operate via signed sJ offsets.
- **Loops**
  - `FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, `TFORLOOP` use the same integer/float loop handling (`forprep`, `forlimit`, `floatforloop`) as Lua, including to-be-closed variable support.
- **Function Calls**
  - `CALL`, `TAILCALL`, `RETURN`, `RETURN0`, `RETURN1` reuse existing call stack logic, including vararg adjustments (`nextraargs`, `VARARGPREP`) and upvalue closure on return (`closeupvalue` semantics via `TESTARG_k`).
- **Vararg & Closure**
  - `VARARG`, `VARARGPREP`, `GETVARG`, `CLOSURE` map to vararg tuple extraction and closure creation; upvalues follow `instack` descriptors.
- **Coroutine/TBC**
  - `TBC`, `CLOSE` align with Lua 5.4 to-be-closed semantics; `TBC` creates tbc upvalues when value ≠ nil.
- **Meta/Extra**
  - `EXTRAARG` functions as the high bits extension for preceding instruction (no standalone behaviour). All metamethod opcodes handled; no new opcodes introduced.
- **Planned Deviations**
  - None currently. Any future deviations (e.g., custom `OP_GETVARG` semantics) will be documented explicitly before implementation.
  
By preserving opcode meanings, operand modes, and flag handling, bytecode emitted in lualike can be reasoned about with Lua 5.4 documentation and facilitates cross-comparison against Lua’s VM.

## 5. Bytecode VM Execution Model
- **Frame Model** – Each `CallFrame` owns a register array sized to the callee prototype’s `registerCount`. We maintain `pc`, `base` (register 0 offset), and a pointer to the prototype. The VM loop mirrors `luaV_execute`: fetch instruction, decode operands (RA/RB/RC macros), execute, and update `pc`. We will expose a hook-friendly `trap` flag to integrate logging/debug hooks (later work).
- **Operand Helpers** – Provide helpers equivalent to Lua’s macros (`RA`, `RB`, `RC`, `KB`, `RKC`) so instruction handlers can load registers/constant operands efficiently. For readability we implement them as inline Dart functions with pattern matching.
- **Metamethod Fast Paths** – Implement `fastGet`, `fastSet`, `fastGetI`, `fastSetI` mirroring `luaV_fastget*`/`luaV_fastset*`: attempt direct table access, fall back to `finishGet/finishSet` when metamethods (`__index`, `__newindex`) apply, respecting the MAXTAGLOOP limit to detect cycles.
- **Numeric Conversions** – Adopt helpers from `lvm.h`: `tonumber`, `tointeger`, rounding modes (`F2Imod`), and string-to-number conversions. These ensure arithmetic instructions match Lua coercion semantics (including `cvt2str/cvt2num` guards).
- **Arithmetic & Bitwise Ops** – Provide integer and float variants (`intOp`, `floatOp`) following Lua’s macros (`op_arith`, `op_arithK`, `op_bitwise`). Immediate (`I`) and constant (`K`) opcodes reuse shared helpers that honour overflow, division-by-zero, and conversion fallbacks.
- **Comparison/Test Ops** – Implement number-only fast paths (`LTnum`, `LEnum`, `luaV_equalobj`) and fallback metamethod dispatch via `TM_LT`, `TM_LE`, `TM_EQ`. Respect immediate variants (`OP_LTI`, etc.) with signed immediates and `C` flag (float literal) handling.
- **Loop Instructions** – Port `forprep`, `forloop`, `floatforloop` semantics so integer/float numeric for loops behave like Lua (limit rounding, step zero detection, skip loop optimization). Likewise implement `TFORPREP`/`TFORCALL`/`TFORLOOP` with to-be-closed variable semantics.
- **Table Constructors** – Implement `OP_NEWTABLE` and `OP_SETLIST` exactly as Lua: decode array/hash sizes (including EXTRAARG), allocate/reserve storage, and populate sequential entries.
- **Vararg & Closure Handling** – Support `VARARG`, `VARARGPREP`, `GETVARG`, and `CLOSURE`, reusing existing `LuaClosure`/`Upvalue` classes. Upvalues follow `instack` semantics from `Proto.upvalues`, capturing via `findOrCreateUpvalue`.
- **Function Calls/Returns** – `OP_CALL`, `OP_TAILCALL`, and `OP_RETURN*` reuse existing call stack (`CallStack`) structures. For Lua functions we create new frames; for builtins (`Value` containing Dart functions) we route through existing builtin invocation logic. Tail calls reuse frames by adjusting base/registers as Lua does (`luaD_pretailcall` equivalent).
- **Concatenation & Length** – Implement `luaV_concat` style concatenation with metamethod fallback and string buffer optimization. The `OP_LEN` handler respects table `__len` metamethods and string length semantics.
- **Coroutine Yield/Resume** – VM loop must yield cleanly: when an instruction invokes a Dart async operation (e.g., metamethod or builtin returning Future), we suspend execution and resume later via continuation state (saving `pc`/`base`, similar to `luaV_finishOp`). When resuming, we re-dispatch the partially completed opcode to finish (mirroring Lua’s `luaV_finishOp` cases).
- **Hooks & GC Safe Points** – Integrate periodic calls to `gc.runPendingAutoTrigger()` (after instructions that may allocate) and maintain `LuaRuntime` hook entry points for debug/profiler integration (future extension).
- **Error Propagation** – On runtime errors, wrap them into `LuaError` via `reportError()` and unwind frames using existing interpreter mechanisms so stack traces remain consistent.

## 6. Compatibility, Validation, and Rollout Strategy

### 6.1 Runtime Compatibility Plan
- **API invariants** – the `LuaRuntime` contract defines the full surface area shared by stdlib, GC, interop, and debugging. Both the AST interpreter and the bytecode VM MUST implement every method with identical observable behaviour (side effects, error types, coroutine semantics). We will keep the interface frozen while the engines coexist so third-party code can continue to depend on `_G`, `libraryRegistry`, coroutine helpers, and `collectgarbage` without re-compilation.
- **Feature coverage checklist** – maintain a parity checklist grouped by capability (environment switching, module loading, coroutine lifecycle, metamethod dispatch, arithmetic accuracy, GC hooks, debug stack inspection). Each item links to regression tests and will be ticked only when both engines pass. The checklist will live alongside the engine selection toggle (e.g., `lib/src/runtime/engine_capabilities.dart`) and is reviewed during code review.
- **Stdlib neutrality** – refactor every library (`lib/src/stdlib/lib_*.dart`) to receive a `LuaRuntime`. Libraries may call helper mixins but MUST NOT downcast to concrete interpreter types. Shared helpers (`LibraryRegistry`, `Value`, `Environment`, `Coroutine`, `FileManager`) will be migrated first so downstream modules inherit the abstraction automatically.
- **Metamethod and coroutine parity** – the VM will reuse existing `Value` implementations for metamethod lookups and `Coroutine` for scheduling. We document any diverging edge cases (e.g., interaction between `pcall` and yielded coroutines) in the parity checklist and block rollout until parity is proven.
- **Error reporting** – both engines route through `LuaRuntime.reportError`, preserving message format and stack traces generated by `CallStack`. Tests in `test/interpreter/core/vm_test.dart` will be duplicated for bytecode mode to ensure identical error strings.
- **Interop boundaries** – `lib/src/interop.dart` and embedding APIs will accept a runtime factory and assert that the selected engine implements the full contract. Host applications will continue to pass scripts/modules without behavioural changes.

### 6.2 Regression & Performance Validation
- **Dual-mode automated tests** – extend the test harness to execute targeted suites in both modes. Unit and integration tests that rely on the interpreter will iterate over `EngineMode.values` (AST, BYTECODE) via a new helper in `test/support/engine_runner.dart`, and the CI configuration will run `dart test --fail-fast` twice: once defaulting to AST (current baseline) and once with `LUALIKE_ENGINE=bytecode`. Fail-fast keeps feedback tight while still surfacing the first divergence.
- **Lua test suite parity** – update `tool/test.dart` to accept an `--engine` flag that toggles between AST and bytecode before invoking the official Lua 5.4 regression corpus. CI and developers can run `dart tool/test.dart --engine bytecode --fail-fast` to compare exit codes, emitted output, and duration. The script will record results to `benchmarks/lua_suite_<engine>.log` for later inspection.
- **Golden behaviour fixtures** – add snapshot-style tests for tricky semantics (numeric `for`, `pcall`/`xpcall`, metamethod fallbacks, vararg propagation) that assert identical stdout/stderr and return values across engines. These tests ensure the compatibility checklist remains actionable.
- **Performance benchmarks** – create dedicated benchmarks in `tool/benchmarks/` (e.g., `loop_hot_path_benchmark.dart`, `table_constructor_benchmark.dart`) that execute representative workloads under both engines, measuring wall-clock (via `Stopwatch`) and allocation counts (using `GenerationalGCManager.statistics`). Results will be emitted as JSON to `benchmarks/*.json` so we can track regressions over time. Loop-heavy scripts such as the user-provided `_soft` example will be included verbatim.
- **Bytecode stability tests** – add serialization/deserialization tests that compile a script to bytecode, persist it, reload it, and execute under both engines, verifying that constant pools, upvalues, and debug info survive round-trips.

### 6.3 Rollout Steps & Risk Management
1. **Behind a feature flag** – introduce an engine selector (`EngineMode { ast, bytecode }`) exposed via CLI flag (`--engine`), environment variable (`LUALIKE_ENGINE`), and programmatic API. Default stays `ast`.
2. **Dogfood & parity gates** – require the parity checklist to be 100% complete and automated test matrix green for both engines before enabling beta usage. Add a CI gate that fails if bytecode mode diverges on existing tests.
3. **Performance sign-off** – run the new benchmarks on representative hardware and compare against AST results. Publish findings in `docs/performance.md` and block rollout if bytecode is slower on the targeted loop-heavy scenarios.
4. **Documentation & tooling** – update `docs/cli.md`, `README.md`, and `docs/runtime.md` with instructions on selecting engines, expectations, and troubleshooting. Provide a `lualike --dump-bytecode` flag for developers when the VM ships.
5. **Gradual default switch** – once confidence is high, flip the default engine to bytecode behind a release flag, while keeping `--engine ast` available as an escape hatch for at least one minor release. Monitor issue tracker for regressions.

**Risks / follow-ups**
- Variance in floating point edge cases (`NaN`, `-0`) between interpreter math and VM math needs targeted tests; block rollout until resolved.
- Coroutine scheduling across async Dart futures may expose races if the VM pauses at different instruction boundaries; capture such cases in the parity checklist.
- Bytecode chunks must remain forward compatible; document versioning strategy and bump the feature flag byte when the instruction set evolves.

## 7. Open Questions
- Instruction granularity: adopt pure register VM or hybrid (stack + registers) for easier lowering?
- Tail-call optimisation semantics: ensure emitter preserves Lua’s guarantees while enabling VM tail-call elimination.
- How to share or fork existing interpreter mixins: convert them into reusable AST visitors that target the emitter?
- Source maps / line info: determine format to translate bytecode PCs back to Lua source for error traces.
- Tooling: do we need separate CLI commands to dump bytecode for debugging similar to txtlang IR dumps?
