# Scenario Bench

The quick benchmark harness lives at
[tool/scenario_bench.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/tool/scenario_bench.dart).
Use it for fast local iteration before opening DevTools.

It times named scenarios repeatedly and prints:
- mean
- median
- min
- max
- simple throughput when a scenario has a natural work unit

## Why This Exists

DevTools is still the source of truth for final profiling, but it is too slow
for every small optimization pass. This harness gives a stable local loop for:

- full interpreter scenarios like `calls`, `math`, `sort`, `constructs`
- parser-only scenarios like `parse-calls` and `parse-math`
- direct string-path scenarios like `string-sub`, `string-byte`,
  `string-unpack`
- direct legacy chunk decode scenarios like `legacy-deserialize-calls`
- direct `BinaryFormatParser` scenarios

## Basic Usage

Run a single scenario:

```sh
dart run tool/scenario_bench.dart -scalls --warmup=0 --repeat=5
```

Run a grouped benchmark set:

```sh
dart run tool/scenario_bench.dart -sall --warmup=1 --repeat=3
```

Useful groups:

- `all`
- `interpreter-all`
- `parse-all`
- `string-all`
- `legacy-all`
- `binary-format-all`

## Parser Profiling

For parser scenarios, the harness can also run PetitParser's own
`profile()` and `linter()` output, inspired by the profiling setup in the
`liquid_grammar` repo.

Example:

```sh
dart run tool/scenario_bench.dart \
  -sparse-calls \
  --warmup=0 \
  --repeat=1 \
  --parser-profile \
  --profile-top=10
```

Run the linter too:

```sh
dart run tool/scenario_bench.dart \
  -sparse-calls \
  --warmup=0 \
  --repeat=1 \
  --parser-lint
```

## Recommended Workflow

1. Use `tool/scenario_bench.dart` to compare small changes quickly.
2. Keep changes that improve the relevant scenario without regressing the
   interpreter suite.
3. Once a change looks good locally, confirm it with the DevTools harness in
   [tool/devtools_profile/main.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/tool/devtools_profile/main.dart).
