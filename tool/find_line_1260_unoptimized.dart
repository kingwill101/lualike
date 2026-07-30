import 'dart:io';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/parse.dart';

Future<void> main() async {
  final source = await File('pkgs/love2d/example/assets/relic_breach/main.lua').readAsString();
  final program = parse(source, url: 'assets/relic_breach/main.lua');
  final artifact = (CompilePipeline(config: const CompilePipelineConfig(
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
  )).compile(program) as LuaBytecodeArtifact);
  final lines = const LuaBytecodeDisassembler().render(artifact.chunk).split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains('[1260]')) {
      for (var j = i - 10; j < i + 20; j++) {
        if (j >= 0 && j < lines.length) print('${j + 1}: ${lines[j]}');
      }
      print('---');
    }
  }
}
