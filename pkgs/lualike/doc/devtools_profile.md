# DevTools Profiling Harness

The profiling harness lives at
[tool/devtools_profile/main.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/tool/devtools_profile/main.dart).
It runs selected Lua suite scenarios under timeline markers so Dart DevTools
can capture CPU and memory behavior.

For faster local iteration before opening DevTools, use
[tool/scenario_bench.dart](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/tool/scenario_bench.dart).

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

## `cstack` Breakdown

The profiler exposes the main upstream
[cstack.lua](/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/luascripts/test/cstack.lua)
sections as individual scenarios:

- `--scenario=cstack`
- `--scenario=cstack-message`
- `--scenario=cstack-gsub`
- `--scenario=cstack-gsub-metatable`
- `--scenario=cstack-coroutine-deep`
- `--scenario=cstack-close-chain`
- `--scenario=cstack-resume-nesting`
- `--scenario=cstack-recoverable-errors`

Use `--scenario=cstack` to run all of those sections in sequence under separate
timeline markers, or pick one of the `cstack-*` scenarios to profile a single
failure mode directly.

## Useful Flags

- `--scenario=math`
- `--scenario=nextvar`
- `--scenario=cstack`
- `--scenario=cstack-message`
- `--scenario=cstack-close-chain`
- `--engine=ast|ir|bytecode`
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
  --engine=bytecode \
  --warmup=0 \
  --repeat=1 \
  --wait-seconds=10
```
