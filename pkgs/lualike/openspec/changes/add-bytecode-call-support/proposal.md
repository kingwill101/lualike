# Add Bytecode Support for Function Calls

## Why
- Bytecode mode still falls back to the AST interpreter for Lua function calls, tail calls, and returns, preventing real-world scripts from running purely under the bytecode engine.
- Supporting the `CALL`, `TAILCALL`, and `RETURN*` opcode family (plus vararg preparation) unlocks lowering of function bodies, closures, and stdlib wiring already planned in the coverage roadmap.
- Implementing call semantics now provides the foundation needed before tackling closures/upvalues and interop-heavy features.

## What Changes
- Extend the compiler to lower call expressions, function definitions, and return statements into the Lua 5.4 call/return opcode sequence, including vararg handling stubs.
- Update the bytecode VM to execute `CALL`, `TAILCALL`, `RETURN`, `RETURN0`, `RETURN1`, and `VARARGPREP`, managing stack frames, results, and coroutine safety.
- Add regression tests (compiler, VM, executor) confirming direct calls, tail calls, and vararg functions behave identically to the AST interpreter.
- Follow-up work will introduce bytecode closures (`CLOSURE` opcode, nested prototypes) so that vararg support (`VARARGPREP`/`VARARG`) can be implemented without AST fallbacks.

## Impact
- Bytecode execution will be able to run function-heavy programs without interpreter fallbacks.
- Sets the stage for subsequent work on closures/upvalues and metamethod-driven calls.
