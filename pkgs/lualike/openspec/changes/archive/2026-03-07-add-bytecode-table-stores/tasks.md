## 1. Compiler Enhancements
- [x] 1.1 Lower table field assignments (`tbl.key = value`) to `SETFIELD`.
- [x] 1.2 Lower table index assignments (`tbl[index] = value`) to `SETI` for integer literals, otherwise `SETTABLE`.
- [x] 1.3 Support `AssignmentIndexAccessExpr` nodes for backward-compatible AST targets.

## 2. VM Execution
- [x] 2.1 Implement `SETFIELD`, `SETI`, and `SETTABLE` execution in `BytecodeVm`, reusing `Value` helpers to respect `__newindex` metamethods.

## 3. Validation
- [x] 3.1 Add compiler unit tests covering table field/index assignments.
- [x] 3.2 Add VM unit tests for table writes (string and integer keys, dynamic keys).
- [x] 3.3 Add executor integration tests verifying bytecode table writes mutate state identically to the AST interpreter (including metamethod trigger).
