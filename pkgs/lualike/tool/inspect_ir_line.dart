import 'dart:io';

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/disassembler.dart';
import 'package:lualike/src/parse.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/inspect_ir_line.dart <file.lua> [start] [end]',
    );
    exit(64);
  }

  final filePath = args.first;
  final start = args.length > 1 ? int.parse(args[1]) : 1;
  final end = args.length > 2 ? int.parse(args[2]) : start;

  final source = File(filePath).readAsStringSync();
  final program = parse(source, url: filePath);
  final chunk = LualikeIrCompiler().compile(program);

  final disassembly = disassembleChunk(
    chunk,
    includeSubPrototypes: false,
    includeConstants: false,
    includeLineInfo: true,
  );

  final buffer = StringBuffer();
  for (final line in disassembly.split('\n')) {
    final atIndex = line.indexOf('@');
    if (atIndex == -1) {
      continue;
    }
    final tail = line.substring(atIndex + 1).trimLeft();
    final lineNumber = int.tryParse(tail.split(' ').first);
    if (lineNumber == null) {
      continue;
    }
    if (lineNumber >= start && lineNumber <= end) {
      buffer.writeln(line);
    }
  }

  stdout.write(buffer.toString());
}
