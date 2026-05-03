# Small Parser Corpus

Generated: `2026-05-03T09:22:10.511352`

Baseline: `origin/ir small-parser-corpus`, revision `ae3c7fc3eef6`, captured `2026-05-03T09:19:35.586857`

Latest: `current small-parser-corpus`, revision `a85d083aee33`, branch `profiling/parser-performance`, captured `2026-05-03T09:19:40.305093`

Percentage improvement is mean parse-time reduction:

```text
(baseline mean - latest mean) / baseline mean
```

| Case | Baseline | Latest | Reduction | Speedup |
| --- | ---: | ---: | ---: | ---: |
| `attributes_and_labels` | `3.139 ms` | `1.002 ms` | `68.1%` | `3.1x` |
| `branches_and_loops` | `1.351 ms` | `1.033 ms` | `23.5%` | `1.3x` |
| `functions_and_calls` | `1.342 ms` | `0.655 ms` | `51.2%` | `2.0x` |
| `literals_and_expressions` | `1.036 ms` | `0.476 ms` | `54.0%` | `2.2x` |
| `strings_and_comments` | `2.717 ms` | `0.239 ms` | `91.2%` | `11.4x` |
| `table_shapes` | `2.886 ms` | `0.647 ms` | `77.6%` | `4.5x` |
| **Total** | `12.470 ms` | `4.052 ms` | **`67.5%`** | **`3.1x`** |
