/// Compares IR instruction count with all optimizations enabled vs disabled.
///
/// Usage: dart run tool/compare_ir.dart [script.lua]
///
/// Shows a table comparing instruction counts per script for each optimization
/// level, helping identify which passes have the most impact.
library;

import 'dart:io';

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/ir/textual_formatter.dart';
import 'package:lualike/src/parse.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    // Default: run on all demo scripts
    final candidates = [
      '../luascripts/folding',
      '/run/media/kingwill101/disk2/code/code/dart_packages/lualike.worktrees/multipass-compiler/luascripts/folding',
    ];
    Directory? dir;
    for (final c in candidates) {
      final d = Directory(c);
      if (await d.exists()) { dir = d; break; }
    }
    if (dir == null) {
      stderr.writeln('Usage: dart run tool/compare_ir.dart <script.lua | dir>');
      exit(1);
    }
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.lua'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    _runTable(files);
  } else {
    final path = args.first;
    final dir = Directory(path);
    if (await dir.exists()) {
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.lua'))
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      _runTable(files);
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      stderr.writeln('File not found: $path');
      exit(1);
    }
    _runSingle(file);
  }
}

Future<void> _runTable(List<File> files) async {
  print('╔══════════════════════════════════════════════════════════════════╗');
  print('║  IR instruction count: all passes OFF vs ON                    ║');
  print('╚══════════════════════════════════════════════════════════════════╝');
  print('');
  print('  ${'Script'.padRight(30)} ${'Off'.padRight(8)} ${'On'.padRight(8)} ${'Δ'.padRight(8)} ${'Reduction'}');
  print('  ${''.padRight(70, '─')}');

  for (final file in files) {
    final name = file.path.split('/').last;
    final source = await file.readAsString();

    // All optimizations OFF
    final off = CompilePipeline(
      config: const CompilePipelineConfig(
        enableConstantFolding: false,
        enableConstPropagation: false,
        enableTypeNarrowing: false,
        enableMetatableFolding: false,
        enableDeadCodeElimination: false,
        enableBundling: false,
        enablePeephole: false,
        target: CompileBackend.lualikeIR,
      ),
    );
    final offArtifact = off.compileSource(source);
    final offIr = offArtifact as LualikeIrArtifact;
    final offCount = offIr.chunk.mainPrototype.instructions.length;

    // All optimizations ON
    final on = CompilePipeline(
      config: const CompilePipelineConfig(
        enableConstantFolding: true,
        enableConstPropagation: true,
        enableTypeNarrowing: true,
        enableMetatableFolding: true,
        enablePeephole: true,
        enableDeadCodeElimination: true,
        target: CompileBackend.lualikeIR,
      ),
    );
    final onArtifact = on.compileSource(source);
    final onIr = onArtifact as LualikeIrArtifact;
    final onCount = onIr.chunk.mainPrototype.instructions.length;

    final delta = offCount - onCount;
    final pct = offCount > 0 ? (delta / offCount * 100).toStringAsFixed(1) : '0.0';
    final deltaStr = delta >= 0 ? '+$delta' : '$delta';
    print('  ${name.padRight(30)} ${offCount.toString().padRight(8)} ${onCount.toString().padRight(8)} ${deltaStr.padRight(8)} ${'$pct%'}');
  }
}

Future<void> _runSingle(File file) async {
  final name = file.path.split('/').last;
  final source = await file.readAsString();

  // Off
  final offPipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: false,
      enableConstPropagation: false,
      enableTypeNarrowing: false,
      enableMetatableFolding: false,
      enableDeadCodeElimination: false,
      enableBundling: false,
      enablePeephole: false,
      target: CompileBackend.lualikeIR,
    ),
  );
  final off = offPipeline.compileSource(source);
  final offIr = off as LualikeIrArtifact;

  // On
  final onPipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      enableConstPropagation: true,
      enableTypeNarrowing: true,
      enableMetatableFolding: true,
      enablePeephole: true,
      enableDeadCodeElimination: true,
      target: CompileBackend.lualikeIR,
    ),
  );
  final onArtifact = onPipeline.compileSource(source);
  final onIr = onArtifact as LualikeIrArtifact;

  final delta = offIr.chunk.mainPrototype.instructions.length -
      onIr.chunk.mainPrototype.instructions.length;
  final pct = offIr.chunk.mainPrototype.instructions.length > 0
      ? (delta / offIr.chunk.mainPrototype.instructions.length * 100)
          .toStringAsFixed(1)
      : '0.0';

  print('$name: ${offIr.chunk.mainPrototype.instructions.length} → '
      '${onIr.chunk.mainPrototype.instructions.length} instructions '
      '(${delta >= 0 ? '+' : ''}$delta, $pct%)');
  print('');

  // Show IR disassembly side by side
  print('═══ IR (all passes OFF) ═══');
  print(formatLualikeIrChunk(offIr.chunk));
  print('');
  print('═══ IR (all passes ON) ═══');
  print(formatLualikeIrChunk(onIr.chunk));
}
