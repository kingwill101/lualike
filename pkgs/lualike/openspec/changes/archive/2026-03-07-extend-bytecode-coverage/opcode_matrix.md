# Lua 5.4 Opcode Coverage Plan

| Opcode | Category | Compiler Responsibilities | VM Responsibilities | Notes / Blockers |
| --- | --- | --- | --- | --- |
| MOVE | Registers | Emit register-to-register move when targets differ; integrate with allocator. | Copy register values without coercion; maintain GC barriers when moving complex values. | Depends on register allocator enhancements (Task 3.2). |
| LOADI | Literals | Lower integer literals outside constant pool range; ensure extraarg usage for large immediates. | Write signed immediate to target register with integer tagging. | Requires immediate encoding helpers. |
| LOADF | Literals | Emit float immediates similar to LOADI; ensure reusing registers. | Store double precision immediate. | Same helper as LOADI. |
| LOADK | Literals | Already supported; extend constant pool growth checks. | Already supported; ensure GC tracking when returning Value wrappers. |  |
| LOADKX | Literals | Emit paired EXTRAARG for extended constant indices. | Decode next instruction for constant index. | Depends on EXTRAARG handling. |
| LOADFALSE | Literals | Already supported. | Already supported. |  |
| LFALSESKIP | Branch Prep | Lower boolean conversion in conditional expressions. | Emit false and skip next instruction when needed. | Requires branch lowering design. |
| LOADTRUE | Literals | Already supported. | Already supported. |  |
| LOADNIL | Literals | Already supported. | Already supported. |  |
| GETUPVAL | Upvalues | Emit capture reads based on closure environment mapping. | Fetch upvalue contents with GC barriers. | Needs closure analysis (Task 3.1). |
| SETUPVAL | Upvalues | Emit writes to captured variables. | Update upvalue storage, respect GC barriers. |  |
| GETTABUP | Globals | Already supported. | Already supported. |  |
| GETTABLE | Table Access | Emit dynamic key access using RK operands. | Implement raw lookup with metamethod fallback hooks. | Requires metamethod path (Task 2.1). |
| GETI | Table Access | Emit numeric index accesses (array part). | Optimised integer lookup with fallback to `GETTABLE`. |  |
| GETFIELD | Table Access | Emit string-key lookups using constant short strings. | Use interned strings and metamethod fallback. |  |
| SETTABUP | Globals | Implement constant key writes to environment/upvalue tables. | Assign to table respecting metamethods and GC barriers. |  |
| SETTABLE | Table Access | Emit store with RK operands (value/register). | Write to table and trigger metamethods; handle tbc values. |  |
| SETI | Table Access | Emit numeric key writes. | Update array/dense storage or fallback to hash. |  |
| SETFIELD | Table Access | Emit constant string key writes. | Write to table and maintain metamethod semantics. |  |
| NEWTABLE | Tables | Emit table constructor with array/hash hints and EXTRAARG usage. | Allocate TableStorage with sizing hints. | Shares logic with SETLIST (Task 4.1). |
| SELF | Method Call Prep | Emit `obj:method` expansion (copies table register and loads method). | Duplicate receiver and fetch method; handles metamethod load. |  |
| ADDI | Arithmetic | Compile `reg + immediate` variant; reuse left register; handle signed immediates. | Perform int/float arithmetic with coercion; propagate metamethod fallback. |  |
| ADDK | Arithmetic | Compile register + constant. | Numeric operation or metamethod fallback. |  |
| SUBK | Arithmetic | Similar to ADDK. | Similar to ADDK. |  |
| MULK | Arithmetic | Similar to ADDK. | Similar to ADDK. |  |
| MODK | Arithmetic | Emit modulo with constant operand. | Implement `luaV_mod` semantics. |  |
| POWK | Arithmetic | Emit exponentiation with constant operand. | Use `pow` and metamethod fallback. |  |
| DIVK | Arithmetic | Emit floating division constant variant. | Use float arithmetic, handle division by zero. |  |
| IDIVK | Arithmetic | Emit floor division constant variant. | Use integer division semantics; convert to int. |  |
| BANDK | Bitwise | Emit bitwise and with constant. | Implement using integer semantics. |  |
| BORK | Bitwise | Emit bitwise or with constant. |  |  |
| BXORK | Bitwise | Emit bitwise xor with constant. |  |  |
| SHLI | Bitwise | Emit left shift reg by signed immediate. | Implement shift semantics with bounds. |  |
| SHRI | Bitwise | Emit right shift reg by immediate. |  |  |
| ADD | Arithmetic | Already supported for register/register. | Extend to metamethod fallback. |  |
| SUB | Arithmetic | Emit register subtraction. |  |  |
| MUL | Arithmetic | Emit multiplication. |  |  |
| MOD | Arithmetic | Emit modulus; convert to call to `luaV_mod`. |  |  |
| POW | Arithmetic | Emit exponentiation. |  |  |
| DIV | Arithmetic | Emit float division. |  |  |
| IDIV | Arithmetic | Emit integer floor division. |  |  |
| BAND | Bitwise | Emit bitwise and register version. |  |  |
| BOR | Bitwise | Emit bitwise or register version. |  |  |
| BXOR | Bitwise | Emit bitwise xor register version. |  |  |
| SHL | Bitwise | Emit left shift register version. |  |  |
| SHR | Bitwise | Emit right shift register version. |  |  |
| MMBIN | Metamethod | Lower arithmetic fallback invocation after failed primitive op. | Dispatch to metamethod using `__add` etc. | Depends on metamethod support infrastructure. |
| MMBINI | Metamethod | Metamethod with immediate operand variant. |  |  |
| MMBINK | Metamethod | Metamethod with constant operand variant. |  |  |
| UNM | Unary | Compile unary minus. | Perform numeric negation with coercion. |  |
| BNOT | Unary | Compile bitwise not. | Implement bitwise complement. |  |
| NOT | Unary | Compile logical not. | Convert to boolean semantics. |  |
| LEN | Unary | Compile length operator (#). | Table length semantics via `luaV_objlen`. |  |
| CONCAT | String | Emit concatenation for register range. | Implement optimized string buffer concat with metamethod fallback. |  |
| CLOSE | Upvalues | Emit closing stack upvalues when leaving block. | Close all to-be-closed variables. | Depends on call frame model. |
| TBC | Upvalues | Mark register as to-be-closed. | Track and close at exit. | Requires register metadata. |
| JMP | Control Flow | Emit unconditional jumps with PC offsets. | Adjust PC and update trap/hook state. |  |
| EQ | Comparison | Emit equality comparison for registers. | Perform raw comparison and metamethod fallback. |  |
| LT | Comparison | Emit less-than using metatable logic. |  |  |
| LE | Comparison | Emit less-or-equal. |  |  |
| EQK | Comparison | Emit equality vs constant. |  |  |
| EQI | Comparison | Emit equality vs signed immediate. |  |  |
| LTI | Comparison | Emit less-than immediate. |  |  |
| LEI | Comparison | Emit less-or-equal immediate. |  |  |
| GTI | Comparison | Emit greater-than immediate. |  |  |
| GEI | Comparison | Emit greater-or-equal immediate. |  |  |
| TEST | Control Flow | Emit test of register truthiness for branch formation. | Evaluate truthiness and manage PC skip. |  |
| TESTSET | Control Flow | Emit test with assignment. | Evaluate register and conditionally copy value. |  |
| CALL | Calls | Emit function call with argument/return counts. | Set up new frame, handle closures, builtin values. | Requires frame model (Task 5.2). |
| TAILCALL | Calls | Emit tail call rewriting current frame. | Reuse frame and pop stack correctly; support varargs. |  |
| RETURN | Calls | Already implemented for simple case; extend for multiple returns and varargs. | Propagate values and close upvalues. |  |
| RETURN0 | Calls | Already supported implicit returns. | Already supported. |  |
| RETURN1 | Calls | Emit single-value fast return. | Already supported? ensure semantics. |  |
| FORLOOP | Loops | Emit numeric for loop iteration and jump. | Update loop counters and guard as per Lua semantics. |  |
| FORPREP | Loops | Emit preparation of numeric for loops (init, limit, step). | Already partly in loop VM; integrate here. |  |
| TFORPREP | Iteration | Emit preparation for generic for; create to-be-closed var. | Setup iterator call and jump. |  |
| TFORCALL | Iteration | Emit iterator call returning multiple values. | Manage call and register assignment. |  |
| TFORLOOP | Iteration | Emit loop continuation with nil check. | Jump if control variable non-nil. |  |
| SETLIST | Tables | Emit bulk array assignments; manage EXTRAARG. | Assign registers to table sequence. |  |
| CLOSURE | Functions | Emit closure creation referencing child prototypes. | Instantiate closure and bind upvalues. |  |
| VARARG | Varargs | Emit vararg pack for register range. | Materialise vararg values to registers. | Requires frame/stack design. |
| GETVARG | Varargs | Emit access to vararg table entry. | Provide metamethod-friendly access. |  |
| VARARGPREP | Varargs | Emit parameter adjustment for vararg functions. | Prepare stack/closure vararg state. |  |
| EXTRAARG | Auxiliary | Emit extended operand bits for preceding instruction. | Decode and apply to prior opcode. |  |

## Cross-Cutting Infrastructure (Task 1.2)
- **Register allocator upgrades**: support explicit allocation/free, spill handling, vararg growth, and per-register metadata (to-be-closed, constant reuse). Introduce SSA-like planning or linear-scan scheduler.
- **Frame model**: design call frame stack including base register, function proto reference, open upvalues list, and to-be-closed tracking.
- **Constant pool management**: extend builder to deduplicate strings/literals, enforce 25-bit limits, and merge with chunk serializer.
- **Debug info**: capture PC-to-line mapping, local variable lifetimes, and upvalue names for parity with AST traces.
- **Metamethod dispatch**: centralise fallback helper invoked by arithmetic/comparison/table ops and integrate with VM stack/hook system.

## Expression & Metamethod Plan (Tasks 2.1/2.2)
- Emit arithmetic/bitwise/comparison opcodes in pairs: primitive fast path + metamethod fallback (MMBIN variants).
- Implement numeric coercion mirroring `luaV_tonumber_`/`luaV_tointeger` from AST interpreter; reuse helper in VM.
- Concatenation requires string buffer optimisation and metamethod `__concat` fallback; compiler must collapse ranges of registers per Lua semantics.
- Comparison ops share metamethod resolution; plan shared helper mirroring `luaV_equalobj` and `luaV_lessthan` from interpreter.

## Variable & Function Semantics Plan (Tasks 3.1/3.2)
- Track locals via register slots; integrate with parser/upvalue analyser to map `MOVE`, `GETUPVAL`, `SETUPVAL`.
- Support `VARARG`/`VARARGPREP` by capturing call frame argument count and copying to requested registers.
- Implement closure creation: emit child prototypes, bind upvalues with in-stack flag, ensure GC barriers.
- To-be-closed (`TBC`, `CLOSE`) requires metadata per register and integration with upvalue closing when leaving scope.

## Table Operations & Iteration Plan (Tasks 4.1/4.2)
- `NEWTABLE`/`SETLIST`: compile constructor expressions with array/hash sizing, deal with EXTRAARG for overflow. VM pre-allocates TableStorage and writes sequential elements.
- `GETTABLE`/`SETTABLE`/`GETFIELD`/`SETFIELD`: centralise metamethod logic (`__index`, `__newindex`), handle Value wrappers.
- Iterator opcodes (`TFOR*`): compile generic for loops to call iterator function, assign results, and continue when `nil`; ensure VM cooperates with coroutines/yield boundaries.

## Control Flow & Call Plan (Tasks 5.1/5.2)
- Jumps/tests: compile structured control flow (if/else, while, repeat) using PC offsets; ensure VM updates trap/hook state.
- Numeric for loops reuse `_executeForPrep/_executeForLoop` semantics from interpreter with integer/float support.
- Calls/tailcalls: design frame structure storing base register, function, return target; support varargs and builtins. Tailcall must pop current frame before invoking callee.
- Returns: handle multiple values, varargs, and closing to-be-closed registers when leaving scope.

## Tooling & Validation Plan (Tasks 6.1/6.2)
- For each opcode group, add compiler unit tests (instruction assertions) and VM execution tests comparing to AST interpreter results.
- Establish parity harness running selected Lua test-suite categories in both engines and diffing results.
- Expand benchmark scripts once loops/tables/calls are supported; record AST vs bytecode timings.
- Update docs (`docs/runtime.md`, `docs/cli.md`) when bytecode mode achieves feature parity and when default flip occurs.
