import 'dart:io';

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/disassembler.dart';
import 'package:lualike/src/ir/serialization.dart';
import 'package:lualike/src/parse.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/dump_ir.dart <file.lua|file.lir> [-o output.lir]',
    );
    exit(64);
  }

  String? outputPath;
  if (args.length >= 3 && (args[1] == '-o' || args[1] == '--output')) {
    outputPath = args[2];
  } else if (args.length > 1) {
    stderr.writeln('Unsupported arguments: ${args.sublist(1).join(' ')}');
    exit(64);
  }

  final inputFile = File(args.first);
  final inputBytes = inputFile.readAsBytesSync();
  final chunk = switch (looksLikeLualikeIrBytes(inputBytes)) {
    true => deserializeLualikeIrBytes(inputBytes),
    false => LualikeIrCompiler().compile(parse(inputFile.readAsStringSync())),
  };

  if (outputPath != null) {
    File(outputPath).writeAsBytesSync(serializeLualikeIrChunk(chunk));
  }

  stdout.write(
    disassembleChunk(
      chunk,
      includeSubPrototypes: true,
      includeConstants: true,
      includeLineInfo: false,
    ),
  );
}
