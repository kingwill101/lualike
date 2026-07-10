/// Compare instruction counts with/without folding for each demo script.
///
/// Usage: dart run tool/fold_compare.dart

import 'dart:io';

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/parse.dart';

void main(List<String> args) async {
  final scriptsDir = args.isNotEmpty
      ? args.first
      : '../luascripts/folding';

  final dir = Directory(scriptsDir);
  if (!await dir.exists()) {
    stderr.writeln('Directory not found: $scriptsDir');
    exit(1);
  }

  final files = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.lua'))
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));

  // Header
  print('=' * 80);
  print('  Constant Folding Comparison');
  print('=' * 80);
  print('');
  print(
      '  ${'Script'.padRight(30)} ${'Unfolded'.padRight(10)} ${'Folded'.padRight(10)} ${'Saved'.padRight(8)} ${'Reduction'}');
  print('  ${''.padRight(30, '-')} ${''.padRight(10, '-')} ${''.padRight(10, '-')} ${''.padRight(8, '-')} ${''.padRight(10, '-')}');

  for (final file in files) {
    final name = file.path.split('/').last;
    final source = await file.readAsString();

    // Compile with folding OFF
    final unfoldedPipeline = CompilePipeline(
      config: const CompilePipelineConfig(
        enableConstantFolding: false,
        target: CompileBackend.lualikeIR,
      ),
    );
    final unfolded = unfoldedPipeline.compileSource(source);
    final unfoldedIr = unfolded as LualikeIrArtifact;
    final ui = unfoldedIr.chunk.mainPrototype.instructions.length;

    // Compile with folding ON
    final foldedPipeline = CompilePipeline(
      config: const CompilePipelineConfig(
        enableConstantFolding: true,
        target: CompileBackend.lualikeIR,
      ),
    );
    final folded = foldedPipeline.compileSource(source);
    final foldedIr = folded as LualikeIrArtifact;
    final fi = foldedIr.chunk.mainPrototype.instructions.length;

    final saved = ui - fi;
    final pct = ui > 0 ? (saved / ui * 100).toStringAsFixed(1) : '0.0';
    print(
      '  ${name.padRight(30)} ${ui.toString().padRight(10)} ${fi.toString().padRight(10)} ${saved.toString().padRight(8)} ${'$pct%'}',
    );
  }

  print('');
}
