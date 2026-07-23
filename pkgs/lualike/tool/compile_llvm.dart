/// Compile Lua → native binary via lualike IR → LLVM IR → llc → Zig wrapper.
///
/// This tool is being replaced by `lualike --native script.lua -o binary`.
///   dart run tool/compile_llvm.dart myscript.lua -o mybinary
library;

import 'dart:io';
import 'package:lualike/src/ir/llvm_compile.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/compile_llvm.dart <script.lua> [-o <output>]');
    stderr.writeln('  Or use: lualike --native script.lua -o binary');
    exit(1);
  }

  final scriptPath = args.first;
  if (!await File(scriptPath).exists()) {
    stderr.writeln('File not found: $scriptPath');
    exit(1);
  }

  await checkEnvironment();

  var outputPath = '${Directory.current.path}/a.out';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '-o' || args[i] == '--output') && i + 1 < args.length) {
      outputPath = args[i + 1];
    }
  }

  final out = await compileLuaToNative(
    scriptPath: scriptPath,
    outputPath: outputPath,
  );
  stderr.writeln('Done: $out');
  stderr.writeln('Run: $out');
}
