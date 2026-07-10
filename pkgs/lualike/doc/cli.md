# CLI Reference

LuaLike is a **Lua 5.5-compatible** runtime and bytecode compiler written in Dart.

## Usage

```
lualike [options] [script [args]]
```

If no script or code is provided, lualike starts in interactive REPL mode.

## Engine Selection

| Flag | Description |
|------|-------------|
| `--ast` | Use the AST interpreter (default) |
| `--ir` | Use the lualike IR runtime |
| `--lua-bytecode` | Use the Lua 5.5 bytecode VM |

## Compilation

| Flag | Description |
|------|-------------|
| `--compile <file>` | Compile script to bytecode binary (all optimizations enabled) |
| `-o, --output <file>` | Output path for `--compile` bytecode file |
| `--dart-output <file>` | Also emit a Dart embed file (precompiled_module.dart style) |
| `--preserve-debug` | Keep debug line info in compiled bytecode (default: stripped) |

## Optimization Control

| Flag | Description |
|------|-------------|
| `--fold` / `--no-fold` | Enable/disable constant folding pass (default: off) |
| `--dump-ir` | Print IR instruction dump and exit (IR mode) |

## Execution

| Flag | Description |
|------|-------------|
| `-e, --execute <code>` | Execute string as Lua code |
| `-l, --require <file>` | Require a module before the main script |
| `-i, --interactive` | Enter interactive mode after running script |
| `--version` | Print version information |
| `-h, --help` | Print usage information |

## Debug and Logging

| Flag | Description |
|------|-------------|
| `--debug` | Enable debug mode with detailed logging |
| `--level <LEVEL>` | Set log level (FINE, INFO, WARNING, SEVERE, etc) |
| `--category <CAT>` | Filter logs by category (repeat or comma-separated) |

## Lua 5.5 Compliance

LuaLike targets full Lua 5.5 compatibility. The bytecode VM can run:
- Bytecode compiled by `lualike --compile`
- Bytecode compiled by the official `luac55` compiler
- Lua source files directly

## Compiler Pipeline

When `--compile` is used, lualike runs a multi-pass optimization pipeline:

```
Source → [Bundler] → [Analyzer] → [ConstPropagation] → [TypeNarrowing]
  → [MetatableFolding] → [InliningHeuristics] → [ConstantFolding]
  → [Simplifier] → [DeadCodeElimination] → [Peephole] → Bytecode
```

| Pass | Description | Default |
|------|-------------|---------|
| Bundler | Resolves `require("path")` and inlines dependencies | off |
| Analyzer | Lightweight type inference for local variables | off |
| ConstPropagation | Forwards single-assignment constants without `<const>` | off |
| TypeNarrowing | Tracks types through `type(x) == "number"` checks | off |
| MetatableFolding | Detects `setmetatable` on constant tables | off |
| InliningHeuristics | Limits function inlining to small bodies | off |
| ConstantFolding | Evaluates constant expressions at compile time | off |
| Simplifier | Rewrites folded AST into literal nodes | off |
| DeadCodeElimination | Tree-shakes unused module exports | off |
| Peephole | Cleans up redundant IR instructions post-emission | off |

All passes are enabled during `--compile`. Use `--fold` to enable folding
for ad-hoc optimization during development.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `LOGGING_ENABLED=true` | Enable logging in all modes |
| `LOGGING_LEVEL=FINE` | Set default log level |
| `LOGGING_CATEGORY=Interp,GC` | Comma-separated category filters |
| `LOGGING_BACKEND=contextual|basic` | Select logging backend |
| `LOGGING_PRETTY=true|false` | Pretty formatting for contextual backend |

## Examples

```sh
# Run a script
lualike myscript.lua

# Compile to bytecode (all optimizations enabled)
lualike --compile myscript.lua -o myscript.lub

# Run compiled bytecode
lualike --lua-bytecode myscript.lub

# Compile with debug info preserved
lualike --compile myscript.lua -o myscript.lub --preserve-debug

# Compile and generate Dart embed file
lualike --compile myscript.lua -o myscript.lub --dart-output myscript_precompiled.dart

# Run with constant folding (development)
lualike --fold myscript.lua

# Compare IR with and without optimizations
lualike --ir --dump-ir myscript.lua
lualike --ir --no-fold --dump-ir myscript.lua

# Execute inline code
lualike -e "print('hello from lualike')"

# Run with debug logging
lualike --debug myscript.lua

# REPL with warnings only
lualike --level WARNING
```
