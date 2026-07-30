import 'dart:io';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/parse.dart';

Future<void> main() async {
  final source = await File('pkgs/love2d/example/assets/relic_breach/main.lua').readAsString();
  final program = parse(source, url: 'assets/relic_breach/main.lua');
  final pipeline = CompilePipeline(config: const CompilePipelineConfig(
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
  ));
  final artifact = pipeline.compile(program) as LuaBytecodeArtifact;
  final rendered = const LuaBytecodeDisassembler().render(artifact.chunk);
  final lines = rendered.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains('[662]') || lines[i].contains('[663]') || lines[i].contains('[664]') || lines[i].contains('[665]') || lines[i].contains('[666]') || lines[i].contains('[667]') || lines[i].contains('[668]')) {
      for (var j = i - 5; j <= i + 10; j++) {
        if (j >= 0 && j < lines.length) print('${j + 1}: ${lines[j]}');
      }
      print('---');
    }
  }
}
