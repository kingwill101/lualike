# LuaLike Project Guide

LuaLike is a Lua 5.5-compatible runtime and optimizing bytecode compiler written in Dart.

## Project Structure

```
pkgs/lualike/
  lib/
    src/
      compile/          # Compiler pipeline passes
        compiler_pass.dart       # Abstract base class
        constant_folding_pass.dart  # Constant expression analysis
        simplify_pass.dart       # AST rewriting after folding
        const_propagation_pass.dart  # Single-assignment const forwarding
        type_narrowing_pass.dart  # Type tracking via type() checks
        dead_code_pass.dart      # Module export tree-shaking
        bundler.dart             # require() resolution
        analyzer_pass.dart       # Lightweight type inference
        metatable_folding_pass.dart  # setmetatable() tracking
        inlining_heuristics_pass.dart  # Inlining profitability config
        fold_result.dart         # ConstantFoldingResult data
        pipeline.dart            # Pass orchestration
      ir/               # Intermediate representation
        compiler.dart            # AST → IR compiler
        emitter.dart             # IR instruction emitter
        peephole_pass.dart       # Post-emission IR optimization
        vm.dart                  # IR VM
      lua_bytecode/      # Lua 5.5 bytecode backend
        emitter.dart             # AST → Lua 5.4/5.5 bytecode
        serializer.dart          # Bytecode serialization
        parser.dart              # Bytecode parsing
        vm.dart                  # Lua 5.5 bytecode VM
        builder.dart             # Prototype builder
        chunk.dart               # Binary chunk types
    command/             # CLI entry points
      lualike_command_runner.dart  # Main CLI
      script_command.dart        # Script execution
      execute_command.dart       # -e flag
    stdlib/              # Standard library implementations
      lib_math.dart, lib_string.dart, lib_base.dart, etc.
  test/
    constant_folding_test.dart   # 37 tests for folding passes
    compiler_passes_test.dart    # 13 tests for all passes
    cli_integration_test.dart    # CLI end-to-end tests
  doc/
    cli.md                       # CLI reference
    logging.md                   # Logging controls
    lsp.md                       # LSP integration
  example/
    compiler_pipeline_example.dart  # Using the compiler from Dart
```

## Compiler Pipeline

The pipeline runs in this order during `--compile`:

```
[Bundler] → [Analyzer] → [ConstPropagation] → [TypeNarrowing]
  → [MetatableFolding] → [InliningHeuristics] → [ConstantFolding]
  → [Simplifier] → [DeadCodeElimination] → [Peephole]
```

All passes extend `CompilerPass` and implement:
```dart
class MyPass extends CompilerPass {
  @override String get name => 'my_pass';
  @override Program run(Program program, CompilerContext context) { ... }
}
```

To add a new pass:
1. Create the class extending `CompilerPass`
2. Add it to `_buildPassList()` in `pipeline.dart`
3. Add a config flag in `CompilePipelineConfig`
4. Write tests in `test/compiler_passes_test.dart`

## CLI Flags

See `doc/cli.md` for full reference. Key commands:

```sh
lualike script.lua                  # Run with AST interpreter
lualike --lua-bytecode script.lua   # Run with bytecode VM
lualike --compile script.lua -o out # Compile to bytecode (all optimizations)
lualike --fold script.lua           # Run with constant folding
lualike --ir --dump-ir script.lua   # Show IR instructions
lualike --compile script.lua -o out --preserve-debug  # Keep line info
lualike --compile script.lua -o out --dart-output out.dart  # Also emit Dart embed
```

## Cross-Compatibility

The bytecode VM supports both:
- Bytecode from `lualike --compile`
- Bytecode from official `luac55`

```sh
lualike --compile s.lua -o s.lub && lua55 s.lub  # works
luac55 -o s.lub s.lua && lualike --lua-bytecode s.lub  # works
```

## Testing

```sh
# Run compiler tests
dart run test test/constant_folding_test.dart
dart run test test/compiler_passes_test.dart

# Run CLI integration tests (requires compiled binary)
dart compile exe bin/main.dart -o /tmp/lualike_bin
LUALIKE_BIN=/tmp/lualike_bin dart run test test/cli_integration_test.dart

# Run all compiler tests
dart run test test/constant_folding_test.dart test/compiler_passes_test.dart

# Compare IR with/without passes
dart run tool/compare_ir.dart luascripts/folding/
