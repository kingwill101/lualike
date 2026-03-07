# Add Bytecode Support for Closures and Varargs

## Why
- The bytecode path still falls back to the AST interpreter for Lua function definitions, nested closures, and vararg access (`...`). Without emitting `CLOSURE` and child prototypes, bytecode execution cannot run real-world scripts that define functions or rely on varargs.
- Supporting closures unlocks additional opcode families (`CLOSURE`, `MOVE`/upvalue bindings) and is a prerequisite for full vararg handling via `VARARGPREP`/`VARARG`.
- Completing this work keeps bytecode mode aligned with the existing interpreter behaviour and follows the roadmap outlined in the earlier coverage plan.

## What Changes
- Lower Lua function declarations and literals into child prototypes, emitting `CLOSURE` instructions and tracking parameters/vararg metadata.
- Extend the bytecode VM with a lightweight call-frame stack capable of instantiating and invoking bytecode closures, including upvalue capture for locals referenced by inner functions.
- Implement vararg opcodes so `...` expressions and tail vararg returns behave identically to the AST interpreter.

## Impact
- Bytecode mode will execute nested functions, closures, and vararg-heavy code without interpreter fallbacks.
- Provides the structural base needed for subsequent feature work (upvalues, stdlib functions compiled to bytecode).
