/// Demonstration: Constant folding in action.
///
/// Compiles the same expression with and without folding, shows the IR
/// disassembly to prove instruction reduction, and runs it to verify results.
library;

import 'dart:io';

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
import 'package:lualike/src/ir/textual_formatter.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/value.dart';

void main(List<String> args) async {
  final verbose = args.contains('-v') || args.contains('--verbose');

  // Example 1: Pure constant arithmetic
  print('=' * 60);
  print('Example 1: return 2 + 3 * 4 - 1');
  print('=' * 60);
  await _compareWithAndWithoutFolding(
    'return 2 + 3 * 4 - 1',
    verbose: verbose,
  );

  // Example 2: String concatenation
  print('\n' + '=' * 60);
  print('Example 2: return "hello" .. " " .. "world"');
  print('=' * 60);
  await _compareWithAndWithoutFolding(
    'return "hello" .. " " .. "world"',
    verbose: verbose,
  );

  // Example 3: Mixed const local
  print('\n' + '=' * 60);
  print('Example 3: local x <const> = 42; return x + 1');
  print('=' * 60);
  await _compareWithAndWithoutFolding(
    'local x <const> = 42\nreturn x + 1',
    verbose: verbose,
  );

  // Example 4: Boolean chain
  print('\n' + '=' * 60);
  print('Example 4: return true and not false or false');
  print('=' * 60);
  await _compareWithAndWithoutFolding(
    'return true and not false or false',
    verbose: verbose,
  );

  // Example 5: The actual benchmark script
  print('\n' + '=' * 60);
  print('Example 5: Benchmark script (test_fold_bench.lua)');
  print('=' * 60);
  final benchSource = await File('/run/media/kingwill101/disk2/code/code/dart_packages/lualike.worktrees/multipass-compiler/test_fold_bench.lua').readAsString();

  final foldedPipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      target: CompileBackend.lualikeIR,
    ),
  );
  final foldedArtifact = foldedPipeline.compileSource(benchSource);
  final foldedIr = foldedArtifact as LualikeIrArtifact;

  final unfoldedPipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: false,
      target: CompileBackend.lualikeIR,
    ),
  );
  final unfoldedArtifact = unfoldedPipeline.compileSource(benchSource);
  final unfoldedIr = unfoldedArtifact as LualikeIrArtifact;

  final fi = foldedIr.chunk.mainPrototype.instructions.length;
  final ui = unfoldedIr.chunk.mainPrototype.instructions.length;
  print('  Without folding: $ui instructions');
  print('  With folding:    $fi instructions');
  print('  Saved:           ${ui - fi} instructions (${((ui - fi) / ui * 100).toStringAsFixed(1)}%)');
  print('  Bytecode:        ${foldedIr.serializedBytes.length} bytes vs ${unfoldedIr.serializedBytes.length} bytes');

  // Run to verify correctness
  print('\n--- Running benchmark to verify correctness ---');
  final runtime = LualikeIrRuntime();
  final chunk = await runtime.loadBytecode(
    foldedIr.serializedBytes,
    moduleName: 'bench',
  );
  print('  Calling compiled function...');
  final runSw = Stopwatch()..start();
  await runtime.callFunction(chunk, []);
  runSw.stop();
  print('  Run time: ${runSw.elapsedMilliseconds}ms');
}

Future<void> _compareWithAndWithoutFolding(
  String source, {
  bool verbose = false,
}) async {
  // Compile with folding
  final foldedPipeline = CompilePipeline(
    config: CompilePipelineConfig(
      enableConstantFolding: true,
      target: CompileBackend.lualikeIR,
    ),
  );
  final folded = foldedPipeline.compileSource(source);
  final foldedIr = folded as LualikeIrArtifact;

  // Compile without folding
  final unfoldedPipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: false,
      target: CompileBackend.lualikeIR,
    ),
  );
  final unfolded = unfoldedPipeline.compileSource(source);
  final unfoldedIr = unfolded as LualikeIrArtifact;

  final foldedInstrs = foldedIr.chunk.mainPrototype.instructions.length;
  final unfoldedInstrs = unfoldedIr.chunk.mainPrototype.instructions.length;

  print('  Without folding: $unfoldedInstrs instructions');
  print('  With folding:    $foldedInstrs instructions');
  print('  Saved:           ${unfoldedInstrs - foldedInstrs} instructions');

  if (verbose) {
    print('\n  --- IR (unfolded) ---');
    print(formatLualikeIrChunk(unfoldedIr.chunk));
    print('\n  --- IR (folded) ---');
    print(formatLualikeIrChunk(foldedIr.chunk));
  }

  // Run through IR VM to verify correctness
  final runtime1 = LualikeIrRuntime();
  final chunk1 = await runtime1.loadBytecode(
    unfoldedIr.serializedBytes,
    moduleName: 'test',
  );
  final result1 = await runtime1.callFunction(chunk1, []);

  final runtime2 = LualikeIrRuntime();
  final chunk2 = await runtime2.loadBytecode(
    foldedIr.serializedBytes,
    moduleName: 'test',
  );
  final result2 = await runtime2.callFunction(chunk2, []);

  final r1 = result1.toString();
  final r2 = result2.toString();
  print('  Unfolded result: $r1');
  print('  Folded result:   $r2');
  print('  Match:           ${r1 == r2}');
}
