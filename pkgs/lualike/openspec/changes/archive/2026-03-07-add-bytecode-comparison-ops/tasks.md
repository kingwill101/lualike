## 1. Compiler Enhancements
- [x] 1.1 Lower equality comparisons against literals to `EQK`/`EQI` as appropriate.
- [x] 1.2 Lower relational comparisons (`<`, `<=`, `>`, `>=`) against numeric literals to `LTI`, `LEI`, `GTI`, `GEI`.

## 2. VM Execution
- [x] 2.1 Implement `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, and `GEI` in `BytecodeVm` with Lua-accurate coercion and truthiness.

## 3. Validation
- [x] 3.1 Add compiler unit tests covering literal comparisons and emitted opcodes.
- [x] 3.2 Add VM and `executeCode` integration tests verifying parity for numeric and string literal comparisons.
