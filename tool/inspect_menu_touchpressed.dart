import 'dart:io';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';

Future<void> main() async {
  final source = await File('pkgs/love2d/example/assets/pocket_bomber/src/states/menu.lua').readAsString();
  final program = parse(source, url: 'src/states/menu.lua');
  for (final entry in [
    ('ast', const CompilePipelineConfig(target: CompileBackend.ast)),
    ('bytecode', CompilePipelineConfig.luaBytecodeOptimized()),
    ('unopt', const CompilePipelineConfig(
      target: CompileBackend.luaBytecode,
      enableAnalyzer: false,
      enableConstantFolding: false,
      enableConstPropagation: false,
      enableTypeNarrowing: false,
      enableMetatableFolding: false,
      enablePeephole: false,
      enableBytecodePeephole: false,
      enableSsaDeadCodeElimination: false,
      enableSsaGlobalValueNumbering: false,
      enableSsaSccp: false,
      enableSsaLicm: false,
      enableSsaCoalesce: false,
      enableSsaEscape: false,
      enableFunctionInlining: false,
      enableLoopUnrolling: false,
      enableBundling: false,
      bundleSearchPaths: ['.'],
      enableDeadCodeElimination: false,
    )),
  ]) {
    final artifact = CompilePipeline(config: entry.$2).compile(program);
    print('=== ${entry.$1} ${artifact.runtimeType} ===');
    if (artifact is LuaBytecodeArtifact) {
      final bytecode = await LuaBytecodeRuntime().loadBytecode(artifact.serializedBytes, moduleName: 'src/states/menu.lua');
      print('chunk: $bytecode');
    }
  }
}
