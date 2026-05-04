# Small Parser Corpus

Generated: `2026-05-03T11:01:12.710519`

Baseline: `origin/ir small-parser-corpus`, revision `3f9069998692`, captured `2026-05-03T11:01:07.487256`

Latest: `current small-parser-corpus`, revision `a6d79f1e2b13`, branch `profiling/parser-performance`, captured `2026-05-03T11:01:11.924994`

Percentage improvement is mean parse-time reduction:

```text
(baseline mean - latest mean) / baseline mean
```

| Case | Baseline | Latest | Reduction | Speedup |
| --- | ---: | ---: | ---: | ---: |
| `attributes_and_labels` | `2.413 ms` | `0.772 ms` | `68.0%` | `3.1x` |
| `branches_and_loops` | `1.788 ms` | `1.219 ms` | `31.8%` | `1.5x` |
| `functions_and_calls` | `1.820 ms` | `0.692 ms` | `62.0%` | `2.6x` |
| `literals_and_expressions` | `0.921 ms` | `0.517 ms` | `43.9%` | `1.8x` |
| `strings_and_comments` | `2.847 ms` | `0.386 ms` | `86.4%` | `7.4x` |
| `table_shapes` | `3.334 ms` | `0.574 ms` | `82.8%` | `5.8x` |
| **Total** | `13.124 ms` | `4.161 ms` | **`68.3%`** | **`3.2x`** |
