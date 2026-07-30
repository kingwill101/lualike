import 'dart:io';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/parse.dart';

Future<void> dump(bool optimized) async {
  final source = await File('pkgs/love2d/example/assets/relic_breach/main.lua').readAsString();
  final program = parse(source, url: 'assets/relic_breach/main.lua');
  final config = optimized
      ? CompilePipelineConfig.luaBytecodeOptimized()
      : const CompilePipelineConfig(
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
        );
  final artifact = (CompilePipeline(config: config).compile(program) as LuaBytecodeArtifact);
  final lines = const LuaBytecodeDisassembler().render(artifact.chunk).split('\n');
  print('=== ${optimized ? 'optimized' : 'unoptimized'} ===');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains('[1260]')) {
      final start = i - 120 < 0 ? 0 : i - 120;
      final end = i + 40 < lines.length ? i + 40 : lines.length - 1;
      for (var j = start; j <= end; j++) {
        print('${j + 1}: ${lines[j]}');
      }
      break;
    }
  }
}

Future<void> main() async {
  await dump(true);
  await dump(false);
}
