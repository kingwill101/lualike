## ADDED Requirements

### Requirement: Dense Table Construction Must Be Fast
`TableStorage` MUST build contiguous numeric tables without quadratic slowdowns.

#### Scenario: literal constructor benchmark
- **GIVEN** `dart run tool/table_construct_bench.dart 512 50`
- **THEN** the output line `literal_construct` MUST report `<= 300.00 ms`
- **AND** the benchmark MUST complete without timeouts.

### Requirement: Reverse Assignment Loops Must Complete Promptly
Nested reverse numeric writes MUST finish in single-digit seconds for constructs-style loops.

#### Scenario: reverse assignment benchmark
- **GIVEN** `dart run tool/table_construct_bench.dart 512 50`
- **THEN** the output line `reverse_assign` MUST report `<= 10000.00 ms`.

### Requirement: Vararg Table Constructors Must Scale Linearly
Expanding `{table.unpack(...)}` MUST avoid per-element hash lookups.

#### Scenario: vararg constructor benchmark
- **GIVEN** `dart run tool/table_construct_bench.dart 512 50`
- **THEN** the output line `vararg_constructor` MUST report `<= 12000.00 ms`.

### Requirement: Sequential Lookup Performance Must Match Baseline
Forward and backward numeric scans MUST stay within 10% of the pre-optimization Map implementation.

#### Scenario: sequential read benchmark
- **GIVEN** `dart run tool/table_bench.dart 1000 2`
- **THEN** both `forward_read` and `backward_read` output lines MUST report `<= 620.00 ms`.
