/// Build tool for precompiling Lua stdlib sources into bytecode.
///
/// Usage: dart run tool/compile_stdlib.dart [options]
///
/// Reads Lua source files, runs the multi-pass compilation pipeline, and
/// outputs bytecode suitable for distribution via Flutter assets or Dart
/// package embedding.
///
/// Inspired by Hetu Script's approach in `third_party/hetu-script/utils/compile_hetu.dart`
/// and `third_party/hetu_std/Makefile`.
library;

import 'dart:io';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/parse.dart';

void main(List<String> args) async {
  final config = _parseArgs(args);

  if (config.help) {
    _printUsage();
    return;
  }

  final pipeline = CompilePipeline(
    config: CompilePipelineConfig(
      enableConstantFolding: !config.noFold,
      dumpIr: config.dumpIr,
      stripDebug: config.stripDebug,
      target: config.irOnly ? CompileBackend.lualikeIR : CompileBackend.luaBytecode,
    ),
  );

  for (final input in config.inputs) {
    stdout.writeln('Compiling $input...');
    final source = await File(input).readAsString();
    final program = parse(source, url: input);
    final artifact = pipeline.compile(program);

    // Write the output(s)
    if (config.outputDir != null) {
      await Directory(config.outputDir!).create(recursive: true);

      final baseName = pathWithoutExtension(basename(input));

      switch (artifact) {
        case LuaBytecodeArtifact(
          :final serializedBytes,
          :final chunk,
        ):
          // Binary bytecode output
          if (config.binaryOutput) {
            final outPath = join(
              config.outputDir!,
              '$baseName${config.irOnly ? '.irb' : '.out'}',
            );
            await File(outPath).writeAsBytes(serializedBytes);
            stdout.writeln('  → wrote $outPath (${serializedBytes.length} bytes)');
          }

          // Dart embed output (like Hetu's precompiled_module.dart)
          if (config.dartOutput) {
            final dartOut = _generateDartEmbed(
              serializedBytes,
              variableName: '${baseName}Module',
              foldingStats: _foldingStats(artifact.foldingResult, program),
            );
            final dartPath = join(config.outputDir!, '$baseName.precompiled.dart');
            await File(dartPath).writeAsString(dartOut);
            stdout.writeln('  → wrote $dartPath');
          }

          // Optional disassembly
          if (config.dumpLua) {
            _dumpLuaChunk(chunk);
          }

        case LualikeIrArtifact(
          :final serializedBytes,
          :final disassembly,
        ):
          if (config.binaryOutput) {
            final outPath = join(
              config.outputDir!,
              '$baseName.irb',
            );
            await File(outPath).writeAsBytes(serializedBytes);
            stdout.writeln(
              '  → wrote $outPath (${serializedBytes.length} bytes)',
            );
          }

          if (disassembly != null && config.dumpIr) {
            stdout.writeln('--- IR disassembly: $baseName ---');
            stdout.writeln(disassembly);
          }
      }

      // Print folding statistics
      if (config.verbose) {
        final total = _countNodes(program);
        final folded = _countFolded(artifact.foldingResult, program);
        stdout.writeln(
          '  folding: $folded/$total expressions folded (${(folded / total * 100).toStringAsFixed(1)}%)',
        );
      }
    }
  }
}

/// Parsed command-line configuration.
final class _Config {
  final List<String> inputs;
  final String? outputDir;
  final String? chunkName;
  final bool noFold;
  final bool dumpIr;
  final bool dumpLua;
  final bool binaryOutput;
  final bool dartOutput;
  final bool irOnly;
  final bool stripDebug;
  final bool verbose;
  final bool help;

  const _Config({
    this.inputs = const [],
    this.outputDir,
    this.chunkName,
    this.noFold = false,
    this.dumpIr = false,
    this.dumpLua = false,
    this.binaryOutput = true,
    this.dartOutput = false,
    this.irOnly = false,
    this.stripDebug = false,
    this.verbose = false,
    this.help = false,
  });
}

_Config _parseArgs(List<String> args) {
  var help = false;
  final inputs = <String>[];
  String? outputDir;
  String? chunkName;
  var noFold = false;
  var dumpIr = false;
  var dumpLua = false;
  var binaryOutput = true;
  var dartOutput = false;
  var irOnly = false;
  var stripDebug = false;
  var verbose = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--help' || '-h':
        help = true;
      case '--output' || '-o':
        outputDir = args[++i];
      case '--chunk-name' || '-n':
        chunkName = args[++i];
      case '--no-fold':
        noFold = true;
      case '--dump-ir':
        dumpIr = true;
      case '--dump-lua':
        dumpLua = true;
      case '--no-binary':
        binaryOutput = false;
      case '--dart-output':
        dartOutput = true;
      case '--ir-only':
        irOnly = true;
      case '--strip-debug':
        stripDebug = true;
      case '--verbose' || '-v':
        verbose = true;
      default:
        if (!args[i].startsWith('--')) {
          inputs.add(args[i]);
        }
    }
  }

  return _Config(
    help: help,
    inputs: inputs,
    outputDir: outputDir,
    chunkName: chunkName,
    noFold: noFold,
    dumpIr: dumpIr,
    dumpLua: dumpLua,
    binaryOutput: binaryOutput,
    dartOutput: dartOutput,
    irOnly: irOnly,
    stripDebug: stripDebug,
    verbose: verbose,
  );
}

void _printUsage() {
  stdout.writeln('''
Usage: dart run tool/compile_stdlib.dart [options] <input.lua> [input2.lua ...]

Compile Lua source files through the multi-pass pipeline and produce bytecode.

Options:
  -h, --help              Show this help message.
  -o, --output <dir>      Output directory (default: current dir).
  -n, --chunk-name <name> Chunk name for the bytecode (default: input filename).
  --no-fold               Disable constant folding pass.
  --dump-ir               Print IR disassembly.
  --dump-lua              Print Lua 5.4 bytecode disassembly.
  --no-binary             Do not write binary bytecode output.
  --dart-output           Generate a Dart embed file (precompiled_module.dart).
  --ir-only               Emit lualike IR instead of Lua 5.4 bytecode.
  --strip-debug           Omit debug line info in bytecode.
  -v, --verbose           Verbose output (folding stats, etc.).
''');
}

String _generateDartEmbed(
  List<int> bytes, {
  required String variableName,
  String? foldingStats,
}) {
  final buf = StringBuffer();
  buf.writeln('/// Pre-compiled bytecode module.');
  buf.writeln('///');
  buf.writeln('/// Generated by lualike compile_stdlib. Do not edit manually.');
  buf.writeln('///');
  if (foldingStats != null) {
    buf.writeln('/// $foldingStats');
    buf.writeln('///');
  }
  buf.writeln('final $variableName = <int>[');

  // Write bytes in chunks of 16 per line for readability.
  for (var i = 0; i < bytes.length; i += 16) {
    final end = (i + 16) > bytes.length ? bytes.length : (i + 16);
    buf.write('  ');
    for (var j = i; j < end; j++) {
      buf.write('${bytes[j]}');
      if (j < bytes.length - 1) buf.write(', ');
    }
    buf.writeln(',');
  }

  buf.writeln('];');
  return buf.toString();
}

void _dumpLuaChunk(LuaBytecodeBinaryChunk chunk) {
  stdout.writeln('--- Lua 5.4 bytecode dump ---');
  stdout.writeln('Prototype: lines ${chunk.mainPrototype.lineDefined}-'
      '${chunk.mainPrototype.lastLineDefined}');
  stdout.writeln(
    'Stack: ${chunk.mainPrototype.maxStackSize}, '
    'Params: ${chunk.mainPrototype.parameterCount}, '
    'Upvalues: ${chunk.mainPrototype.upvalues.length}, '
    'Constants: ${chunk.mainPrototype.constants.length}, '
    'Instructions: ${chunk.mainPrototype.code.length}',
  );
}

String _foldingStats(ConstantFoldingResult folded, Program program) {
  final total = _countNodes(program);
  final count = _countFolded(folded, program);
  final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
  return 'Constant folding: $count/$total nodes folded ($pct%)';
}

int _countNodes(AstNode node) {
  var count = 1;
  if (node is Program) {
    for (final s in node.statements) count += _countNodes(s);
  } else if (node is BinaryExpression) {
    count += _countNodes(node.left) + _countNodes(node.right);
  } else if (node is UnaryExpression) {
    count += _countNodes(node.expr);
  } else if (node is GroupedExpression) {
    count += _countNodes(node.expr);
  } else if (node is ReturnStatement) {
    for (final e in node.expr) count += _countNodes(e);
  } else if (node is Assignment) {
    for (final t in node.targets) count += _countNodes(t);
    for (final e in node.exprs) count += _countNodes(e);
  } else if (node is LocalDeclaration) {
    for (final e in node.exprs) count += _countNodes(e);
  } else if (node is IfStatement) {
    count += _countNodes(node.cond);
    for (final s in node.thenBlock) count += _countNodes(s);
    for (final s in node.elseBlock) count += _countNodes(s);
  } else if (node is WhileStatement) {
    count += _countNodes(node.cond);
    for (final s in node.body) count += _countNodes(s);
  }
  return count;
}

int _countFolded(ConstantFoldingResult folded, AstNode node) {
  var count = folded.isConstant(node) ? 1 : 0;
  if (node is Program) {
    for (final s in node.statements) count += _countFolded(folded, s);
  } else if (node is BinaryExpression) {
    count += _countFolded(folded, node.left) +
        _countFolded(folded, node.right);
  } else if (node is UnaryExpression) {
    count += _countFolded(folded, node.expr);
  } else if (node is GroupedExpression) {
    count += _countFolded(folded, node.expr);
  } else if (node is ReturnStatement) {
    for (final e in node.expr) count += _countFolded(folded, e);
  } else if (node is Assignment) {
    for (final t in node.targets) count += _countFolded(folded, t);
    for (final e in node.exprs) count += _countFolded(folded, e);
  } else if (node is LocalDeclaration) {
    for (final e in node.exprs) count += _countFolded(folded, e);
  } else if (node is IfStatement) {
    count += _countFolded(folded, node.cond);
    for (final s in node.thenBlock) count += _countFolded(folded, s);
    for (final s in node.elseBlock) count += _countFolded(folded, s);
  } else if (node is WhileStatement) {
    count += _countFolded(folded, node.cond);
    for (final s in node.body) count += _countFolded(folded, s);
  }
  return count;
}

String basename(String path) => path.split(RegExp(r'[/\\]')).last;

String pathWithoutExtension(String path) {
  final name = basename(path);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String join(String a, String b) {
  if (a.endsWith('/') || a.endsWith('\\')) return '$a$b';
  return '$a/$b';
}
