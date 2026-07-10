// Test: bundler combines require("module") into single bytecode
import 'dart:io';

import 'package:lualike/src/compile/bundler.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/parse.dart';

void main() {
  final source = File(
    '/run/media/kingwill101/disk2/code/code/dart_packages/lualike.worktrees/multipass-compiler/luascripts/test_bundle_a.lua',
  ).readAsStringSync();

  // Parse
  final program = parse(source, url: 'test_bundle_a.lua');

  // Bundle
  final bundler = Bundler(searchPaths: [
    '/run/media/kingwill101/disk2/code/code/dart_packages/lualike.worktrees/multipass-compiler/luascripts',
  ]);
  final bundled = bundler.bundle(program);

  print('=== Bundled statements ===');
  for (var i = 0; i < bundled.statements.length; i++) {
    final src = bundled.statements[i].toSource();
    print('  [${i}] ${src.length > 80 ? src.substring(0, 80) : src}');
  }

  // Compile the bundled program
  final pipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      target: CompileBackend.luaBytecode,
    ),
  );
  final artifact = pipeline.compile(bundled);
  final lua = artifact as LuaBytecodeArtifact;

  print('\n=== Compiled bytecode ===');
  print('  Size: ${lua.serializedBytes.length} bytes');
  print('  Constants: ${lua.chunk.mainPrototype.constants.length}');
  print('  Instructions: ${lua.chunk.mainPrototype.code.length}');

  // Save and run
  File('/tmp/test_bundle.lub').writeAsBytesSync(lua.serializedBytes);
  print('\n=== Running compiled bundle ===');
  Process.runSync('/tmp/lualike_bin', ['--lua-bytecode', '/tmp/test_bundle.lub']);
}
