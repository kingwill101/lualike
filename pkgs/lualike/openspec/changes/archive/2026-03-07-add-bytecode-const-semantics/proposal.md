## Why
- Bytecode execution still mishandles `<const>` locals – registers are not consistently sealed, and reassignment errors do not match AST behaviour.
- Integration tests such as `luascripts/test/math.lua` fail under `--bytecode`, blocking broader bytecode adoption.
- Aligning const semantics unlocks further parity work (e.g. `goto`, multi-target assignments) by ensuring locals remain stable.

## What Changes
- Extend bytecode compiler and chunk builder so `<const>` locals mark registers, schedule seal points, and respect scope lifetimes.
- Update the VM to enforce const write protections after initial assignment and ensure diagnostics include script context.
- Add regression tests that cover const locals, multi-assignment initialisers, and reassignment failures in bytecode mode.
- Run targeted bytecode suites (`dart test test/bytecode` and executor parity tests) to confirm the behaviour matches the AST interpreter.

## Impact
- Users can run scripts that rely on `<const>` locals with the bytecode engine.
- Future bytecode features (e.g. loop optimisations, goto resolution) can assume const locals behave correctly.
- Test coverage for const semantics increases, reducing regressions as more opcodes are implemented.
