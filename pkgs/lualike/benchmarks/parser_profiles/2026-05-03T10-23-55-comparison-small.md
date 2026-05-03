# Small Parser Corpus

Generated: `2026-05-03T10:24:06.576844`

Baseline: `origin/ir small-parser-corpus`, revision `9fddd67a706a`, captured `2026-05-03T10:24:01.905949`

Latest: `current small-parser-corpus`, revision `2e71bc07415f`, branch `profiling/parser-performance`, captured `2026-05-03T10:24:05.876652`

Percentage improvement is mean parse-time reduction:

```text
(baseline mean - latest mean) / baseline mean
```

| Case | Baseline | Latest | Reduction | Speedup |
| --- | ---: | ---: | ---: | ---: |
| `attributes_and_labels` | `1.816 ms` | `1.121 ms` | `38.3%` | `1.6x` |
| `branches_and_loops` | `1.567 ms` | `1.359 ms` | `13.3%` | `1.2x` |
| `functions_and_calls` | `1.038 ms` | `0.672 ms` | `35.3%` | `1.5x` |
| `literals_and_expressions` | `0.863 ms` | `0.412 ms` | `52.2%` | `2.1x` |
| `strings_and_comments` | `2.594 ms` | `0.293 ms` | `88.7%` | `8.8x` |
| `table_shapes` | `3.651 ms` | `0.617 ms` | `83.1%` | `5.9x` |
| **Total** | `11.529 ms` | `4.474 ms` | **`61.2%`** | **`2.6x`** |
