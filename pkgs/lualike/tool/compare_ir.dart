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
  print('╔══════════════════════════════════════════════════════════════════════════════════════════════╗');
  print('║  IR instructions (Off / On / SSA)  and  serialized byte size                         ║');
  print('╚══════════════════════════════════════════════════════════════════════════════════════════════╝');
  print('');
  print('  ${'Script'.padRight(20)} ${'Off'.padRight(5)} ${'On'.padRight(5)} ${'SSA'.padRight(5)}  ${'%On'.padRight(7)} ${'%SSA'.padRight(7)}  '
        '${'OffSz'.padRight(9)} ${'OnSz'.padRight(9)} ${'SSASz'.padRight(9)}  ${'%OnSz'.padRight(7)} ${'%SSASz'}');
  print('  ${''.padRight(110, '─')}');

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
    final offBytes = offIr.serializedBytes.length;

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
    final onCount = _totalInstrs(onIr.chunk.mainPrototype);
    final onBytes = onIr.serializedBytes.length;

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
        enableSsaLicm: true,
        enableSsaCoalesce: true,
        enableSsaEscape: true,
        target: CompileBackend.lualikeIR,
      ),
    );
    final ssaArtifact = ssa.compileSource(source);
    final ssaIr = ssaArtifact as LualikeIrArtifact;
    final ssaCount = _totalInstrs(ssaIr.chunk.mainPrototype);
    final ssaBytes = ssaIr.serializedBytes.length;

    final delta = offCount - onCount;
    final ssaDelta = offCount - ssaCount;
    final pct = offCount > 0 ? (delta / offCount * 100).toStringAsFixed(1) : '0.0';
    final ssaPct = offCount > 0 ? (ssaDelta / offCount * 100).toStringAsFixed(1) : '0.0';
    final bDelta = offBytes - onBytes;
    final bSsaDelta = offBytes - ssaBytes;
    final bPct = offBytes > 0 ? (bDelta / offBytes * 100).toStringAsFixed(1) : '0.0';
    final bSsaPct = offBytes > 0 ? (bSsaDelta / offBytes * 100).toStringAsFixed(1) : '0.0';
    print('  ${name.padRight(20)} '
        '${offCount.toString().padRight(5)} ${onCount.toString().padRight(5)} ${ssaCount.toString().padRight(5)} '
        '${'$pct%'.padRight(7)} ${'$ssaPct%'.padRight(7)} '
        '${'${offBytes}b'.padRight(9)} ${'${onBytes}b'.padRight(9)} ${'${ssaBytes}b'.padRight(9)} '
        '${'$bPct%'.padRight(7)} ${'$bSsaPct%'}');
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

  // On + SSA
  final ssaPipeline = CompilePipeline(
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
      enableSsaLicm: true,
      enableSsaCoalesce: true,
      enableSsaEscape: true,
      target: CompileBackend.lualikeIR,
    ),
  );
  final ssaArtifact = ssaPipeline.compileSource(source);
  final ssaIr = ssaArtifact as LualikeIrArtifact;

  final offCount = _totalInstrs(offIr.chunk.mainPrototype);
  final onCount = _totalInstrs(onIr.chunk.mainPrototype);
  final ssaCount = _totalInstrs(ssaIr.chunk.mainPrototype);
  final delta = offCount - onCount;
  final ssaDelta = offCount - ssaCount;
  final pct = offCount > 0
      ? (delta / offCount * 100).toStringAsFixed(1)
      : '0.0';
  final ssaPct = offCount > 0
      ? (ssaDelta / offCount * 100).toStringAsFixed(1)
      : '0.0';

  print('$name: off=$offCount on=$onCount ssa=$ssaCount '
      '(Δ=$delta, $pct% from off; Δssa=$ssaDelta, $ssaPct% from off)');
  print('');

  // Show IR disassembly
  print('═══ IR (all passes OFF) ═══');
  print(formatLualikeIrChunk(offIr.chunk));
  print('');
  print('═══ IR (all passes ON) ═══');
  print(formatLualikeIrChunk(onIr.chunk));
  print('');
  print('═══ IR (ON + SSA) ═══');
  print(formatLualikeIrChunk(ssaIr.chunk));
}

int _totalInstrs(LualikeIrPrototype proto) {
  var count = proto.instructions.length;
  for (final sub in proto.prototypes) {
    count += _totalInstrs(sub);
  }
  return count;
}
