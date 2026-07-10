import 'dart:io';
import 'package:lualike/src/compile/bundler.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/parse.dart';

void main() {
  final base = '/run/media/kingwill101/disk2/code/code/dart_packages/lualike.worktrees/multipass-compiler/luascripts';
  final source = File('$base/graph_main.lua').readAsStringSync();
  final program = parse(source, url: 'graph_main.lua');
  final bundler = Bundler(searchPaths: [base]);

  // Bundle, fold, compile
  final bundled = bundler.bundle(program);
  final pipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      target: CompileBackend.luaBytecode,
    ),
  );
  final artifact = pipeline.compile(bundled);
  final lua = artifact as LuaBytecodeArtifact;

  print('=== Bundled + compiled ===');
  print('  Size: ${lua.serializedBytes.length} bytes');
  print('  Constants: ${lua.chunk.mainPrototype.constants.length}');
  print('  Instructions: ${lua.chunk.mainPrototype.code.length}');

  // Run
  File('/tmp/graph_bundle.lub').writeAsBytesSync(lua.serializedBytes);
  print('');
  Process.runSync('/tmp/lualike_bin', ['--lua-bytecode', '/tmp/graph_bundle.lub']);
}
