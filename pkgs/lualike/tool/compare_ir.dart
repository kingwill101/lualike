/// Compares IR instruction count across optimization levels.
///
/// Usage: dart run tool/compare_ir.dart [script.lua] [--all]
///
/// Shows instruction counts at three levels:
///   OFF  — no optimizations
///   ON   — AST folding + peephole
///   SSA  — ON + SSA passes (DCE, GVN, SCCP, LICM, Coalesce, Escape)
library;

import 'dart:io';

import 'package:lualike/ir.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/ir/textual_formatter.dart';

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
  print('╔══════════════════════════════════════════════════════════════════════════════╗');
  print('║  IR instruction count: OFF vs ON (folding+peephole) vs SSA (all + passes)  ║');
  print('╚══════════════════════════════════════════════════════════════════════════════╝');
  print('');
  print('  ${'Script'.padRight(24)} ${'Off'.padRight(7)} ${'On'.padRight(7)} ${'Δ'.padRight(6)} ${'%'.padRight(7)} ${'SSA'.padRight(7)} ${'ΔS'.padRight(6)} ${'%S'}');
  print('  ${''.padRight(80, '─')}');

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
    final offCount = _totalInstrs(offIr.chunk.mainPrototype);

    // All optimizations ON (AST folding + peephole)
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

    // ON + all SSA passes
    final ssa = CompilePipeline(
      config: const CompilePipelineConfig(
        enableConstantFolding: true,
        enableConstPropagation: true,
        enableTypeNarrowing: true,
        enableMetatableFolding: true,
        enablePeephole: true,
        enableDeadCodeElimination: true,
        enableSsaDeadCodeElimination: true,
        enableSsaGlobalValueNumbering: true,
        enableSsaSccp: true,
        target: CompileBackend.lualikeIR,
      ),
    );
    final ssaArtifact = ssa.compileSource(source);
    final ssaIr = ssaArtifact as LualikeIrArtifact;
    final ssaCount = ssaIr.chunk.mainPrototype.instructions.length;

    final delta = offCount - onCount;
    final ssaDelta = offCount - ssaCount;
    final pct = offCount > 0 ? (delta / offCount * 100).toStringAsFixed(1) : '0.0';
    final ssaPct = offCount > 0 ? (ssaDelta / offCount * 100).toStringAsFixed(1) : '0.0';
    final deltaStr = delta >= 0 ? '+$delta' : '$delta';
    final ssaDeltaStr = ssaDelta >= 0 ? '+$ssaDelta' : '$ssaDelta';
    print('  ${name.padRight(24)} ${offCount.toString().padRight(7)} ${onCount.toString().padRight(7)} ${deltaStr.padRight(6)} ${'$pct%'.padRight(7)} ${ssaCount.toString().padRight(7)} ${ssaDeltaStr.padRight(6)} ${'$ssaPct%'}');
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

int _totalInstrs(LualikeIrPrototype proto) {
  var count = proto.instructions.length;
  for (final sub in proto.prototypes) {
    count += _totalInstrs(sub);
  }
  return count;
}
