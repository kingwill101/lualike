## 1. Compiler & Builder Updates
- [x] 1.1 Audit local declaration emission to ensure registers are marked const and seal points cover multi-expression initialisers.
- [x] 1.2 Populate prototype const metadata (flags + seal points) for parameters and detect scope exit so const locals seal once initialised.

## 2. VM Enforcement
- [x] 2.1 Update bytecode VM frames to honour const metadata, prevent late writes, and include source span diagnostics.

## 3. Regression Coverage
- [x] 3.1 Add bytecode-focused tests for const locals (successful initialisation, reassignment failure, multi-value binding).
- [x] 3.2 Run `dart test test/bytecode test/unit/executor_bytecode_parity_test.dart` to verify parity and update docs on remaining gaps if failures appear.
