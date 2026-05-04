# Small Parser Corpus

Generated: `2026-05-03T10:52:27.561531`

Baseline: `origin/ir small-parser-corpus`, revision `3f9069998692`, captured `2026-05-03T10:52:21.336790`

Latest: `current small-parser-corpus`, revision `ab37db12192b`, branch `profiling/parser-performance`, captured `2026-05-03T10:52:26.679227`

Percentage improvement is mean parse-time reduction:

```text
(baseline mean - latest mean) / baseline mean
```

| Case | Baseline | Latest | Reduction | Speedup |
| --- | ---: | ---: | ---: | ---: |
| `attributes_and_labels` | `3.615 ms` | `1.576 ms` | `56.4%` | `2.3x` |
| `branches_and_loops` | `2.158 ms` | `2.433 ms` | `-12.7%` | `0.9x` |
| `functions_and_calls` | `1.319 ms` | `0.944 ms` | `28.4%` | `1.4x` |
| `literals_and_expressions` | `0.830 ms` | `0.526 ms` | `36.6%` | `1.6x` |
| `strings_and_comments` | `3.338 ms` | `0.322 ms` | `90.4%` | `10.4x` |
| `table_shapes` | `4.358 ms` | `0.594 ms` | `86.4%` | `7.3x` |
| **Total** | `15.619 ms` | `6.395 ms` | **`59.1%`** | **`2.4x`** |
