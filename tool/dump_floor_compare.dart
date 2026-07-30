import 'dart:io';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/parse.dart';

void dump(List<String> lines, String label) {
  print('=== $label ===');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains('<assets/relic_breach/main.lua:1248,1265>')) {
      for (var j = i; j < i + 50 && j < lines.length; j++) {
        print('${j + 1}: ${lines[j]}');
      }
      break;
    }
  }
}

Future<void> main() async {
  final source = await File('pkgs/love2d/example/assets/relic_breach/main.lua').readAsString();
  final program = parse(source, url: 'assets/relic_breach/main.lua');
  for (final pair in [
    ('optimized', CompilePipelineConfig.luaBytecodeOptimized()),
    ('unoptimized', const CompilePipelineConfig(
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
    final artifact = (CompilePipeline(config: pair.$2).compile(program) as LuaBytecodeArtifact);
    final lines = const LuaBytecodeDisassembler().render(artifact.chunk).split('\n');
    dump(lines, pair.$1);
  }
}
