/// Trace a Lua source through every IR/bytecode pipeline phase.
///
/// Shows output after each compiler pass so structural changes are visible.
/// Optionally includes luac55 reference for comparison.
///
/// Usage:
///   dart run tool/trace.dart script.lua                          # all phases
///   dart run tool/trace.dart script.lua --phase=dce             # stop at DCE
///   dart run tool/trace.dart script.lua --luac55                # compare to luac55
///   dart run tool/trace.dart -e 'return 1+2' --phase=coalesce   # inline source
library;

import 'dart:io';

import 'package:lualike/ir.dart';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/peephole_pass.dart' as ir_peep;
import 'package:lualike/src/ir/ssa_dead_code_pass.dart';
import 'package:lualike/src/ir/ssa_gvn_pass.dart';
import 'package:lualike/src/ir/ssa_sccp_pass.dart';
import 'package:lualike/src/ir/ssa_licm_pass.dart';
import 'package:lualike/src/ir/ssa_coalesce_pass.dart';
import 'package:lualike/src/ir/ssa_escape_pass.dart';
import 'package:lualike/src/ir/bytecode_lowering.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/ir/textual_formatter.dart';
import 'package:lualike/src/parse.dart';

const _defaultLuac55 =
    '/home/kingwill101/Downloads/lua-5.5.0_Linux68_64_bin/luac55';

enum TracePhase {
  ir,
  peephole,
  dce,
  gvn,
  sccp,
  licm,
  coalesce,
  escape,
  bc,
}

void main(List<String> args) async {
  String? source;
  String sourceLabel = '=(stdin)';
  TracePhase? stopAt;
  bool showLuac55 = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--phase':
        i++;
        stopAt = TracePhase.values.byName(args[i]);
      case '--luac55':
        showLuac55 = true;
      case '-e':
        i++;
        source = args[i];
        sourceLabel = '=(inline)';
      default:
        if (source == null && !args[i].startsWith('-')) {
          final f = File(args[i]);
          if (await f.exists()) {
            source = await f.readAsString();
            sourceLabel = args[i];
          } else {
            stderr.writeln('File not found: ${args[i]}');
            exit(1);
          }
        }
    }
  }

  if (source == null) {
    stderr.writeln('Usage: dart run tool/trace.dart <script.lua> [options]');
    stderr.writeln('       dart run tool/trace.dart -e "lua code" [options]');
    stderr.writeln('');
    stderr.writeln('Phases (default: show all):');
    stderr.writeln('  ir        Raw IR compiler output');
    stderr.writeln('  peephole  After IR peephole pass');
    stderr.writeln('  dce       After SSA dead-code elimination');
    stderr.writeln('  gvn       After global value numbering');
    stderr.writeln('  sccp      After sparse conditional constant prop');
    stderr.writeln('  licm      After loop-invariant code motion');
    stderr.writeln('  coalesce  After register coalescing');
    stderr.writeln('  escape    After escape analysis / SROA');
    stderr.writeln('  bc        Final bytecode disassembly');
    stderr.writeln('');
    stderr.writeln('Options:');
    stderr.writeln('  --phase=<phase>  Show only up to this phase');
    stderr.writeln('  --luac55         Include luac55 reference listing');
    exit(1);
  }

  final program = parse(source, url: sourceLabel);
  final sections = <String>[];

  // ── luac55 reference ────────────────────────────────────────────────
  if (showLuac55) {
    final luaResult = await Process.run(
      Platform.environment['LUAC55'] ?? _defaultLuac55,
      ['-l', '-l', sourceLabel],
      runInShell: true,
    );
    if (luaResult.exitCode == 0) {
      sections.add('═══ luac55 ═══════════════════════════════════════════');
      sections.add((luaResult.stdout as String).trimRight());
    }
  }

  // ── Step through each pipeline phase ────────────────────────────────
  var irChunk = LualikeIrCompiler().compile(program);
  var chunk = irChunk;
  bool showAll = stopAt == null;

  void emit(String label) {
    sections.add('');
    sections.add('═' * 60);
    sections.add('  $label');
    sections.add('═' * 60);
    sections.add(formatLualikeIrChunk(chunk).trimRight());
  }

  // 1. Raw IR
  if (showAll || stopAt == TracePhase.ir) {
    emit('IR compiler (raw)');
    if (!showAll) return _printAndExit(sections);
  }

  // 2. Peephole
  chunk = ir_peep.PeepholePass().optimize(chunk);
  if (showAll || stopAt == TracePhase.peephole) {
    emit('After peephole');
    if (!showAll) return _printAndExit(sections);
  }

  // 3. DCE
  if (chunk != irChunk) { irChunk = chunk; }
  chunk = LualikeIrChunk(
    flags: irChunk.flags,
    mainPrototype: eliminateDeadCode(chunk.mainPrototype),
  );
  if (showAll || stopAt == TracePhase.dce) {
    emit('After DCE');
    if (!showAll) return _printAndExit(sections);
  }

  // 4. GVN
  chunk = LualikeIrChunk(
    flags: irChunk.flags,
    mainPrototype: eliminateRedundantComputations(chunk.mainPrototype),
  );
  if (showAll || stopAt == TracePhase.gvn) {
    emit('After GVN');
    if (!showAll) return _printAndExit(sections);
  }

  // 5. SCCP
  chunk = LualikeIrChunk(
    flags: irChunk.flags,
    mainPrototype: runSccp(chunk.mainPrototype),
  );
  if (showAll || stopAt == TracePhase.sccp) {
    emit('After SCCP');
    if (!showAll) return _printAndExit(sections);
  }

  // 6. LICM
  chunk = LualikeIrChunk(
    flags: irChunk.flags,
    mainPrototype: hoistLoopInvariants(chunk.mainPrototype),
  );
  if (showAll || stopAt == TracePhase.licm) {
    emit('After LICM');
    if (!showAll) return _printAndExit(sections);
  }

  // 7. Coalesce
  chunk = LualikeIrChunk(
    flags: irChunk.flags,
    mainPrototype: coalesceRegisters(chunk.mainPrototype),
  );
  if (showAll || stopAt == TracePhase.coalesce) {
    emit('After coalesce');
    if (!showAll) return _printAndExit(sections);
  }

  // 8. Escape / SROA
  chunk = LualikeIrChunk(
    flags: irChunk.flags,
    mainPrototype: replaceScalars(chunk.mainPrototype),
  );
  if (showAll || stopAt == TracePhase.escape) {
    emit('After escape / SROA');
    if (!showAll) return _printAndExit(sections);
  }

  // 9. Bytecode
  if (showAll || stopAt == TracePhase.bc) {
    final lowered = lowerIrChunkToLuaBytecodeChunk(
      chunk,
      chunkName: sourceLabel,
    );
    sections.add('');
    sections.add('═' * 60);
    sections.add('  Bytecode (lowered)');
    sections.add('═' * 60);
    sections.add(const LuaBytecodeDisassembler().render(lowered).trimRight());
    if (!showAll) return _printAndExit(sections);
  }

  _printAndExit(sections);
}

void _printAndExit(List<String> sections) {
  print(sections.join('\n'));
  exit(0);
}
