/// Analyzes SSA form for compiled IR prototypes.
///
/// Usage: dart run tool/analyze_ssa.dart `<script.lua>` [--verbose]
///        dart run tool/analyze_ssa.dart `<dir>` [--verbose]
library;

import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/ir/ssa_dead_code_pass.dart';
import 'package:lualike/src/ir/ssa_gvn_pass.dart';

final _results = <String, _SsaMetrics>{};

final class _SsaMetrics {
  const _SsaMetrics({
    required this.name,
    required this.instrCount,
    required this.blockCount,
    required this.phiCount,
    required this.defCount,
    required this.unusedCount,
    required this.phiBlocks,
    required this.singleUse,
    required this.multiUse,
  });

  final String name;
  final int instrCount;
  final int blockCount;
  final int phiCount;
  final int defCount;
  final int unusedCount;
  final int phiBlocks;
  final int singleUse;
  final int multiUse;

  double get unusedPct =>
      defCount > 0 ? (unusedCount / defCount * 100) : 0.0;

  double get phiDensity =>
      blockCount > 0 ? phiCount / blockCount : 0.0;
}

void main(List<String> args) async {
  final verbose = args.contains('--verbose') || args.contains('-v');
  final paths = args.where((a) => !a.startsWith('-')).toList();

  if (paths.isEmpty) {
    stderr.writeln('Usage: dart run tool/analyze_ssa.dart <script.lua> [--verbose]');
    stderr.writeln('       dart run tool/analyze_ssa.dart <dir> [--verbose]');
    exit(1);
  }

  for (final path in paths) {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      final dir = Directory(path);
      final files = <File>[];
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.lua')) files.add(e);
      }
      files.sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        await _analyzeFile(file, verbose: verbose);
      }
    } else {
      await _analyzeFile(File(path), verbose: verbose);
    }
  }

  // Summary table
  if (_results.length > 1) {
    _printSummary();
  }
}

Future<void> _analyzeFile(File file, {bool verbose = false}) async {
  final name = file.path.split('/').last;

  String source;
  try {
    source = await file.readAsString();
  } on FileSystemException {
    return; // skip binary files
  }

  Program program;
  try {
    program = parse(source, url: name);
  } catch (e) {
    stderr.writeln('  ✗ $name: parse error — $e');
    return;
  }

  final pipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: false,
      target: CompileBackend.lualikeIR,
    ),
  );
  CompileArtifact artifact;
  try {
    artifact = pipeline.compile(program);
  } catch (e) {
    stderr.writeln('  ✗ $name: compile error — $e');
    return;
  }
  final ir = artifact as LualikeIrArtifact;

  _analyzePrototype(ir.chunk.mainPrototype, name: name, verbose: verbose);

  // Show dead code elimination impact
  final cleaned = eliminateDeadCode(ir.chunk.mainPrototype);
  final gvnCleaned = eliminateRedundantComputations(cleaned);
  final beforeCount = ir.chunk.mainPrototype.instructions.length;
  final afterDce = cleaned.instructions.length;
  final afterGvn = gvnCleaned.instructions.length;
  final dceRemoved = beforeCount - afterDce;
  if (dceRemoved > 0) {
    final pct = (dceRemoved / beforeCount * 100).toStringAsFixed(1);
    print('  → SSA DCE:  $beforeCount → $afterDce (-$dceRemoved, $pct%)');
  }
  final gvnRemoved = afterDce - afterGvn;
  if (gvnRemoved > 0) {
    final pct = (gvnRemoved / afterDce * 100).toStringAsFixed(1);
    print('  → SSA GVN:  $afterDce → $afterGvn (-$gvnRemoved, $pct%)');
  }
  final totalRemoved = beforeCount - afterGvn;
  if (totalRemoved > 0) {
    final pct = (totalRemoved / beforeCount * 100).toStringAsFixed(1);
    print('  → Total:    $beforeCount → $afterGvn (-$totalRemoved, $pct%)');
  }
}

void _analyzePrototype(
  LualikeIrPrototype prototype, {
  String name = '?',
  bool verbose = false,
}) {
  final instrCount = prototype.instructions.length;
  if (instrCount == 0) return;

  final ssa = buildLualikeIrSsaFunction(prototype);

  final blockCount = ssa.blocks.length;
  final totalPhis = ssa.blocks.fold<int>(0, (s, b) => s + b.phis.length);
  final totalDefs = ssa.blocks.fold<int>(0, (s, b) => s + b.definedValues.length);
  final unusedCount = ssa.unusedDefinitions.length;
  final phiBlocks = ssa.blocks.where((b) => b.hasPhis).length;

  final unusedPct = totalDefs > 0
      ? (unusedCount / totalDefs * 100).toStringAsFixed(1)
      : '0.0';
  final phiDensity = blockCount > 0
      ? (totalPhis / blockCount).toStringAsFixed(2)
      : '0.00';

  var zeroUse = 0, oneUse = 0, multiUse = 0;
  for (final block in ssa.blocks) {
    for (final value in block.definedValues) {
      if (value.isUnused) {
        zeroUse++;
      } else if (value.useCount == 1) {
        oneUse++;
      } else {
        multiUse++;
      }
    }
  }

  print('');
  print('  ┌─ $name ─${''.padRight(48, '─')}┐');
  print('  │ Instr: ${instrCount.toString().padRight(5)}  Blocks: ${blockCount.toString().padRight(4)}  Phis: ${totalPhis.toString().padRight(4)}');
  print('  │ Defs:  ${totalDefs.toString().padRight(5)}  Unused: ${unusedCount.toString().padRight(3)} ($unusedPct%)  Φ/blk: $phiDensity');
  print('  │ Phi blocks: $phiBlocks/$blockCount  Uses: 0=$zeroUse  1=$oneUse  2+=$multiUse');
  print('  └${''.padRight(60, '─')}┘');

  if (unusedCount > 0) {
    print('  ⚠  Unused definitions:');
    var shown = 0;
    for (final value in ssa.unusedDefinitions) {
      if (shown >= 10 && !verbose) {
        print('     ... and ${unusedCount - shown} more (use --verbose for full list)');
        break;
      }
      shown++;
      final details = value.uses.map((u) => u.toString()).join(', ');
      print('     ${value.label}  pc=${value.definingPc}  ${details.isNotEmpty ? "→ $details" : "(no uses)"}');
    }
  }

  _results[name] = _SsaMetrics(
    name: name,
    instrCount: instrCount,
    blockCount: blockCount,
    phiCount: totalPhis,
    defCount: totalDefs,
    unusedCount: unusedCount,
    phiBlocks: phiBlocks,
    singleUse: oneUse,
    multiUse: multiUse,
  );

  if (verbose && blockCount <= 20) {
    print('');
    print('  SSA graph:');
    for (final line in formatLualikeIrSsaFunction(ssa).split('\n')) {
      print('    $line');
    }
    print('');
    print('  IR disassembly:');
    for (final line in formatLualikeIrChunk(
      LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: prototype,
      ),
    ).split('\n')) {
      print('    $line');
    }
  }
}

void _printSummary() {
  final sorted = _results.values.toList()
    ..sort((a, b) => b.unusedPct.compareTo(a.unusedPct));

  print('');
  print('═══════════════════════════════════════════════════════════════════');
  print('  SSA Summary — sorted by unused %');
  print('═══════════════════════════════════════════════════════════════════');
  print('');
  print('  ${'Script'.padRight(24)} ${'Instr'.padRight(6)} ${'Blk'.padRight(5)} ${'Phis'.padRight(5)} ${'Defs'.padRight(6)} ${'Unused'.padRight(7)} ${'1-use'.padRight(6)} ${'2+use'}');
  print('  ${''.padRight(80, '─')}');

  for (final m in sorted) {
    print('  ${m.name.padRight(24)} '
        '${m.instrCount.toString().padRight(6)} '
        '${m.blockCount.toString().padRight(5)} '
        '${m.phiCount.toString().padRight(5)} '
        '${m.defCount.toString().padRight(6)} '
        '${'${m.unusedCount} (${m.unusedPct.toStringAsFixed(1)}%)'.padRight(7)} '
        '${m.singleUse.toString().padRight(6)} '
        '${m.multiUse}');
  }
}
