import 'dart:io';

import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';

void main(List<String> args) {
  if (args.length < 4) {
    stderr.writeln(
      'Usage: dart run tool/compare_bytecode_span.dart '
      '<source.lua> <upstream.luac> <start-line> <end-line>',
    );
    exit(64);
  }

  final sourcePath = args[0];
  final luacPath = args[1];
  final startLine = int.parse(args[2]);
  final endLine = int.parse(args[3]);

  final source = File(sourcePath).readAsStringSync();
  final emitted = const LuaBytecodeEmitter().compileSource(
    source,
    chunkName: sourcePath,
    sourceName: sourcePath,
  );
  final upstream = const LuaBytecodeParser().parse(
    File(luacPath).readAsBytesSync(),
  );
  final disassembler = const LuaBytecodeDisassembler();

  final emittedInstructions = disassembler.disassemble(emitted.chunk).mainPrototype.instructions;
  final upstreamInstructions = disassembler.disassemble(upstream).mainPrototype.instructions;

  _printSpanSummary(
    label: 'emitted',
    instructions: emittedInstructions,
    startLine: startLine,
    endLine: endLine,
  );
  stdout.writeln();
  _printSpanSummary(
    label: 'upstream',
    instructions: upstreamInstructions,
    startLine: startLine,
    endLine: endLine,
  );
}

void _printSpanSummary({
  required String label,
  required List<LuaBytecodeDecodedInstruction> instructions,
  required int startLine,
  required int endLine,
}) {
  final inSpan = instructions.where((instruction) {
    final line = instruction.lineNumber;
    return line != null && line >= startLine && line <= endLine;
  }).toList(growable: false);

  final perOpcode = <String, int>{};
  final perLine = <int, int>{};
  for (final instruction in inSpan) {
    perOpcode.update(instruction.opcode.name, (value) => value + 1, ifAbsent: () => 1);
    perLine.update(instruction.lineNumber!, (value) => value + 1, ifAbsent: () => 1);
  }

  final sortedOpcodes = perOpcode.entries.toList()
    ..sort((left, right) {
      final countCompare = right.value.compareTo(left.value);
      return countCompare != 0
          ? countCompare
          : left.key.compareTo(right.key);
    });
  final sortedLines = perLine.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));

  stdout.writeln('$label line span [$startLine, $endLine]');
  stdout.writeln('  instructions: ${inSpan.length}');
  stdout.writeln('  opcode histogram:');
  for (final entry in sortedOpcodes.take(20)) {
    stdout.writeln('    ${entry.key.padRight(10)} ${entry.value}');
  }
  stdout.writeln('  per-line instruction counts:');
  for (final entry in sortedLines) {
    stdout.writeln('    ${entry.key}: ${entry.value}');
  }
}
