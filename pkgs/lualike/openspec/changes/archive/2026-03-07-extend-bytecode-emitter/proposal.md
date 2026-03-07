# Extend Bytecode Emitter and VM Baseline

## Why
- The existing bytecode prototype can only lower literal returns, limiting its usefulness for real scripts.
- We need arithmetic expression support to evaluate hotspots and begin parity testing against the AST interpreter.
- A richer emitter/VM slice unblocks further work on assignments, control flow, and library integration.

## What Changes
- Enhance the bytecode compiler to handle identifiers and basic arithmetic binary expressions while reusing the current environment abstraction.
- Expand the bytecode VM to execute the additional opcodes emitted for arithmetic and global lookup.
- Add regression tests covering compilation artefacts and end-to-end execution via the new engine selection path.

## Impact
- Enables running simple arithmetic-heavy scripts through the bytecode path, supporting forthcoming performance experiments.
- Keeps the AST interpreter as the default while making bytecode mode more representative for upcoming parity work.
