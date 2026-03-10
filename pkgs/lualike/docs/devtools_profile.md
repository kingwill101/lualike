# DevTools Profiling Harness

The profiling harness lives at
[tool/devtools_profile/main.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/tool/devtools_profile/main.dart).
It runs selected Lua suite scenarios under timeline markers so Dart DevTools
can capture CPU and memory behavior.

## Launching

Use `--observe` when you want to attach DevTools:

```sh
dart run --observe tool/devtools_profile/main.dart --scenario=math --wait-seconds=10
```

Without `--observe`, the harness still runs, but it prints a warning because no
VM service is available for DevTools to attach to.

You can launch it from either the `pkgs/lualike` package directory or the
monorepo root. The harness resolves `pkgs/lualike` automatically in both
layouts.

## Runner Parity

Lua suite scenarios should run with the same prelude as
[tool/test.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/tool/test.dart):

- `_port = true` by default
- `_soft = true` by default
- `package.path = 'luascripts/test/?.lua;' .. package.path`

This matters for scenarios like `math.lua`, which intentionally execute extra
non-portable `% 0` and `fmod` checks when `_port` is false.

If the profiler diverges from the test runner prelude, the profile stops being
representative of the suite and may fail before the measured region starts.

## Useful Flags

- `--scenario=math`
- `--scenario=nextvar`
- `--engine=ast|ir`
- `--warmup=N`
- `--repeat=N`
- `--wait-seconds=N`
- `--keep-alive-seconds=N`
- `--no-soft`
- `--no-port`

## Example

```sh
dart run --observe tool/devtools_profile/main.dart \
  --scenario=math \
  --engine=ast \
  --warmup=0 \
  --repeat=1 \
  --wait-seconds=10
```
