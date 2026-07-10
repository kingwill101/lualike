import 'dart:io';
import 'package:lualike/src/compile/bundler.dart';
import 'package:lualike/src/compile/dead_code_elimination.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/parse.dart';

void main() {
  final base = '/run/media/kingwill101/disk2/code/code/dart_packages/lualike.worktrees/multipass-compiler/luascripts';
  final source = File('$base/graph_main.lua').readAsStringSync();
  final program = parse(source, url: 'graph_main.lua');

  // Bundle
  final bundler = Bundler(searchPaths: [base]);
  final bundled = bundler.bundle(program);

  // DCE
  final dce = DeadCodeEliminationPass();
  final cleaned = dce.eliminate(bundled);

  // Compile and compare
  final pipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      target: CompileBackend.luaBytecode,
    ),
  );

  final before = pipeline.compile(bundled) as LuaBytecodeArtifact;
  final after = pipeline.compile(cleaned) as LuaBytecodeArtifact;

  print('');
  print('=== Size comparison ===');
  print('  Before DCE: ${before.serializedBytes.length}B, ${before.chunk.mainPrototype.code.length} instr');
  print('  After DCE:  ${after.serializedBytes.length}B, ${after.chunk.mainPrototype.code.length} instr');

  // Run to verify
  File('/tmp/graph_dce.lub').writeAsBytesSync(after.serializedBytes);
  print('');
  final result = Process.runSync('/tmp/lualike_bin', ['--lua-bytecode', '/tmp/graph_dce.lub']);
  print('Output: ${result.stdout}${result.stderr}');
}
