/// IR comparison implementation used by `tool/compare.dart`.
///
/// Shows instruction counts at three levels:
///   OFF  — no optimizations
///   ON   — AST folding + peephole
///   SSA  — ON + SSA passes (DCE, GVN, SCCP, LICM, Coalesce, Escape)
library;

import 'dart:io';

import 'package:artisanal/artisanal.dart' show Console;
import 'package:artisanal/style.dart';
import 'package:lualike/ir.dart';
import 'package:lualike/src/compile/pipeline.dart';

/// Compares optimization levels for one source file or directory.
Future<void> compareIrPath(
  String? path, {
  required Console io,
  required bool bundle,
}) async {
  if (path == null) {
    // Default: run on all demo scripts
    final candidates = [
      'luascripts/folding',
      '/run/media/kingwill101/disk2/code/code/dart_packages/lualike.worktrees/multipass-compiler/luascripts/folding',
    ];
    Directory? dir;
    for (final c in candidates) {
      final d = Directory(c);
      if (await d.exists()) {
        dir = d;
        break;
      }
    }
    if (dir == null) {
      throw ArgumentError('Folding fixture directory not found.');
    }
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.lua'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    _runTable(files, io: io, bundle: bundle);
  } else {
    final dir = Directory(path);
    if (await dir.exists()) {
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.lua'))
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      _runTable(files, io: io, bundle: bundle);
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      throw ArgumentError('File not found: $path');
    }
    _runSingle(file, io: io, bundle: bundle);
  }
}

Future<void> _runTable(
  List<File> files, {
  required Console io,
  required bool bundle,
}) async {
  io.writeln(
    _titleStyle(
      io,
    ).render('IR instructions (Off / On / SSA) and serialized byte size'),
  );
  io.newLine();
  io.writeln(
    _tableHeaderStyle(io).render(
      '${'Script'.padRight(20)} ${'Off'.padRight(5)} ${'On'.padRight(5)} ${'SSA'.padRight(5)}  ${'%On'.padRight(7)} ${'%SSA'.padRight(7)}  '
      '${'OffSz'.padRight(9)} ${'OnSz'.padRight(9)} ${'SSASz'.padRight(9)}  ${'%OnSz'.padRight(7)} ${'%SSASz'}',
    ),
  );

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
      config: CompilePipelineConfig(
        enableConstantFolding: true,
        enableConstPropagation: true,
        enableTypeNarrowing: true,
        enableMetatableFolding: true,
        enablePeephole: true,
        enableDeadCodeElimination: true,
        enableBundling: bundle,
        bundleSearchPaths: <String>[file.parent.path],
        target: CompileBackend.lualikeIR,
      ),
    );
    final onArtifact = on.compileSource(source);
    final onIr = onArtifact as LualikeIrArtifact;
    final onCount = _totalInstrs(onIr.chunk.mainPrototype);
    final onBytes = onIr.serializedBytes.length;

    // ON + all SSA passes
    final ssa = CompilePipeline(
      config: CompilePipelineConfig(
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
        enableFunctionInlining: true,
        enableBundling: bundle,
        bundleSearchPaths: <String>[file.parent.path],
        target: CompileBackend.lualikeIR,
      ),
    );
    final ssaArtifact = ssa.compileSource(source);
    final ssaIr = ssaArtifact as LualikeIrArtifact;
    final ssaCount = _totalInstrs(ssaIr.chunk.mainPrototype);
    final ssaBytes = ssaIr.serializedBytes.length;

    final delta = offCount - onCount;
    final ssaDelta = offCount - ssaCount;
    final pct = offCount > 0
        ? (delta / offCount * 100).toStringAsFixed(1)
        : '0.0';
    final ssaPct = offCount > 0
        ? (ssaDelta / offCount * 100).toStringAsFixed(1)
        : '0.0';
    final bDelta = offBytes - onBytes;
    final bSsaDelta = offBytes - ssaBytes;
    final bPct = offBytes > 0
        ? (bDelta / offBytes * 100).toStringAsFixed(1)
        : '0.0';
    final bSsaPct = offBytes > 0
        ? (bSsaDelta / offBytes * 100).toStringAsFixed(1)
        : '0.0';
    io.writeln(
      '  ${name.padRight(20)} '
      '${offCount.toString().padRight(5)} ${onCount.toString().padRight(5)} ${ssaCount.toString().padRight(5)} '
      '${'$pct%'.padRight(7)} ${'$ssaPct%'.padRight(7)} '
      '${'${offBytes}b'.padRight(9)} ${'${onBytes}b'.padRight(9)} ${'${ssaBytes}b'.padRight(9)} '
      '${'$bPct%'.padRight(7)} ${'$bSsaPct%'}',
    );
  }
}

Future<void> _runSingle(
  File file, {
  required Console io,
  required bool bundle,
}) async {
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
    config: CompilePipelineConfig(
      enableConstantFolding: true,
      enableConstPropagation: true,
      enableTypeNarrowing: true,
      enableMetatableFolding: true,
      enablePeephole: true,
      enableDeadCodeElimination: true,
      enableBundling: bundle,
      bundleSearchPaths: <String>[file.parent.path],
      target: CompileBackend.lualikeIR,
    ),
  );
  final onArtifact = onPipeline.compileSource(source);
  final onIr = onArtifact as LualikeIrArtifact;

  // On + SSA
  final ssaPipeline = CompilePipeline(
    config: CompilePipelineConfig(
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
      enableBundling: bundle,
      bundleSearchPaths: <String>[file.parent.path],
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

  io.writeln(
    '$name: off=$offCount on=$onCount ssa=$ssaCount '
    '(Δ=$delta, $pct% from off; Δssa=$ssaDelta, $ssaPct% from off)',
  );
  io.newLine();

  // Show IR disassembly
  io.writeln(_sectionStyle(io).render('IR (all passes OFF)'));
  io.writeln(formatLualikeIrChunk(offIr.chunk));
  io.newLine();
  io.writeln(_sectionStyle(io).render('IR (all passes ON)'));
  io.writeln(formatLualikeIrChunk(onIr.chunk));
  io.newLine();
  io.writeln(_sectionStyle(io).render('IR (ON + SSA)'));
  io.writeln(formatLualikeIrChunk(ssaIr.chunk));
}

int _totalInstrs(LualikeIrPrototype proto) {
  var count = proto.instructions.length;
  for (final sub in proto.prototypes) {
    count += _totalInstrs(sub);
  }
  return count;
}

Style _titleStyle(Console io) => io.style
  ..bold()
  ..foreground(Colors.cyan)
  ..border(Border.rounded)
  ..padding(0, 1);

Style _sectionStyle(Console io) => io.style
  ..bold()
  ..foreground(Colors.blue)
  ..border(Border.ascii)
  ..padding(0, 1);

Style _tableHeaderStyle(Console io) => io.style
  ..bold()
  ..border(Border.ascii)
  ..padding(0, 1);
