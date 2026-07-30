import 'dart:io';
import 'package:lualike/src/compile/pipeline.dart';

Future<void> main() async {
  final source = await File('/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/example/assets/pocket_bomber/src/touch_controls.lua').readAsString();
  final pipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      target: CompileBackend.lualikeIR,
      dumpIr: true,
      enableConstantFolding: true,
      enablePeephole: false,
    ),
  );
  final artifact = pipeline.compileSource(source, chunkName: 'touch_controls.lua');
  if (artifact is LualikeIrArtifact) {
    print(artifact.disassembly);
  }
}
