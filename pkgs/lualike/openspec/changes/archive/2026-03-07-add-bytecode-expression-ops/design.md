# Design – Expression Opcode Support for Bytecode

## Scope
- **Compiler**
  - Detect binary expressions using bitwise (`&`, `|`, `~`, `<<`, `>>`) and comparison (`==`, `~=`, `<`, `<=`, `>`, `>=`) operators, lowering them into the respective Lua 5.4 opcodes (`BAND`, `BOR`, `BXOR`, `SHL`, `SHR`, `EQ`, `LT`, `LE`, `EQI`, etc.).
  - Lower unary expressions (`not`, unary minus, bitwise not, length) to `NOT`, `UNM`, `BNOT`, and `LEN`.
  - Handle equality/relational operators by ensuring register allocation for operands and returning truthy results in registers.
  - For immediate/constant variants (`EQK`, `EQI`, `LTI`, etc.), start with register/register lowering for correctness; constant/immediate opcodes can be emitted in future optimization passes.

- **VM**
  - Implement numeric coercion helper to support integer/float comparison and bitwise operations.
  - Add truthiness evaluation for comparisons/unary not consistent with Lua semantics (`nil`/`false` are falsey).
  - Provide length operator implementation delegating to existing `Value` helpers.

## Tests
- Add compiler unit tests asserting expected opcode sequences for bitwise and comparison expressions.
- Add VM tests verifying results for bitwise arithmetic and comparisons.
- Add integration tests using `executeCode` in bytecode mode for unary and comparison logic.

## Out of Scope
- Metamethod fallback (`__eq`, `__lt`, etc.) – will be handled in a future change once core opcode paths exist.
- Constant/immediate opcode variants beyond register/register lowering; this change focuses on correctness over optimization.
