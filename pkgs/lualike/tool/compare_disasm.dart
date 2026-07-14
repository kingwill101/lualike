/// Disassembly comparison implementation used by `tool/compare.dart`.
library;

import 'dart:io';

import 'package:artisanal/artisanal.dart' show Console;
import 'package:artisanal/style.dart';
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/parse.dart';
import 'package:path/path.dart' as p;

const _defaultLuac55 =
    '/home/kingwill101/Downloads/lua-5.5.0_Linux68_64_bin/luac55';

/// Prints luac55 and lualike disassembly for [sourceFile].
///
/// Returns whether every compiler process and bundle compilation succeeded.
Future<bool> compareDisassembly(
  File sourceFile, {
  required Console io,
  required bool bundle,
}) async {
  if (!await sourceFile.exists()) {
    throw ArgumentError('File not found: ${sourceFile.path}');
  }

  final sourcePath = sourceFile.path;
  final shortName = sourcePath.split('/').last;
  final luac55Bin = Platform.environment['LUAC55'] ?? _defaultLuac55;

  if (bundle) {
    return _compareBundle(sourceFile, luac55Bin, io);
  }

  var succeeded = true;
  io.writeln(_titleStyle(io).render(shortName));
  io.newLine();

  // ── luac55 reference ──────────────────────────────────────────
  final luaResult = await Process.run(luac55Bin, [
    '-l',
    '-l',
    sourcePath,
  ], runInShell: true);
  io.writeln(_sectionStyle(io).render('luac55'));
  if (luaResult.exitCode != 0) {
    succeeded = false;
    io.error('luac55 exited with ${luaResult.exitCode}.');
    if ((luaResult.stderr as String).isNotEmpty) {
      io.writelnErr(luaResult.stderr as String);
    }
  } else {
    io.writeln(luaResult.stdout.toString().trimRight());
  }
  io.newLine();

  io.writeln(_sectionStyle(io).render('lualike'));
  try {
    final source = await sourceFile.readAsString();
    final artifact =
        CompilePipeline(
              config: CompilePipelineConfig.luaBytecodeOptimized(),
            ).compile(parse(source, url: sourcePath))
            as LuaBytecodeArtifact;
    io.writeln(
      const LuaBytecodeDisassembler().render(artifact.chunk).trimRight(),
    );
  } catch (error, stackTrace) {
    succeeded = false;
    io.error('lualike disassembly failed: $error');
    io.writelnErr(stackTrace.toString());
  }
  io.newLine();
  return succeeded;
}

/// Compares separate luac chunks with one optimized lualike bundle.
Future<bool> _compareBundle(
  File sourceFile,
  String luac55Bin,
  Console io,
) async {
  final entry = File(p.normalize(p.absolute(sourceFile.path)));
  final sources = _collectStaticModuleGraph(entry);
  var referenceInstructionCount = 0;
  var succeeded = true;

  io.writeln(_titleStyle(io).render('${p.basename(entry.path)} (bundled)'));
  io.newLine();
  io.info('luac55 compiles require() dependencies as separate chunks.');
  io.info('lualike inlines the same static dependency graph below.');
  io.newLine();

  for (final source in sources) {
    final result = await Process.run(luac55Bin, [
      '-l',
      '-l',
      source.path,
    ], runInShell: true);
    io.writeln(
      _sectionStyle(
        io,
      ).render('luac55: ${p.relative(source.path, from: entry.parent.path)}'),
    );
    if (result.exitCode != 0) {
      succeeded = false;
      io.error('luac55 exited with ${result.exitCode}.');
      if ((result.stderr as String).isNotEmpty) {
        io.writelnErr(result.stderr as String);
      }
    } else {
      final listing = result.stdout.toString().trimRight();
      referenceInstructionCount += _countLuacInstructions(listing);
      io.writeln(listing);
    }
    io.newLine();
  }

  try {
    final source = await entry.readAsString();
    final program = parse(source, url: entry.path);
    final artifact =
        CompilePipeline(
              config: CompilePipelineConfig.luaBytecodeOptimized(
                enableBundling: true,
                bundleSearchPaths: <String>[entry.parent.path],
              ),
            ).compile(program)
            as LuaBytecodeArtifact;
    final bundledInstructionCount = _countInstructions(
      artifact.chunk.mainPrototype,
    );

    io.writeln(_sectionStyle(io).render('lualike: single optimized bundle'));
    io.writeln(
      const LuaBytecodeDisassembler().render(artifact.chunk).trimRight(),
    );
    io.newLine();
    io.writeln(_sectionStyle(io).render('bundle summary'));
    io.twoColumnDetail('Source files', sources.length.toString());
    io.twoColumnDetail(
      'luac55 separate instructions',
      referenceInstructionCount.toString(),
    );
    io.twoColumnDetail(
      'lualike bundle instructions',
      bundledInstructionCount.toString(),
    );
  } catch (error, stackTrace) {
    io.error('Bundled disassembly failed: $error');
    io.writelnErr(stackTrace.toString());
    succeeded = false;
  }
  return succeeded;
}

/// Whether [source] contains a static require supported by the bundler.
bool hasStaticRequires(File source) {
  final program = parse(source.readAsStringSync(), url: source.path);
  return _staticRequirePaths(program).isNotEmpty;
}

/// Returns the entry file and all statically bundled dependencies.
List<File> _collectStaticModuleGraph(File entry) {
  final ordered = <File>[];
  final visited = <String>{};

  void visit(File source) {
    final normalized = p.normalize(p.absolute(source.path));
    if (!visited.add(normalized)) {
      return;
    }
    final file = File(normalized);
    ordered.add(file);
    final program = parse(file.readAsStringSync(), url: normalized);
    for (final requirePath in _staticRequirePaths(program)) {
      final dependency = _resolveModule(requirePath, file.parent.path);
      if (dependency != null) {
        visit(dependency);
      }
    }
  }

  visit(entry);
  return ordered;
}

Iterable<String> _staticRequirePaths(Program program) sync* {
  for (final statement in program.statements) {
    final expressions = switch (statement) {
      LocalDeclaration(:final exprs) when exprs.length == 1 => exprs,
      Assignment(:final exprs) when exprs.length == 1 => exprs,
      _ => null,
    };
    if (expressions == null || expressions.single is! FunctionCall) {
      continue;
    }
    final call = expressions.single as FunctionCall;
    if (call.name case Identifier(name: 'require') when call.args.length == 1) {
      if (call.args.single case StringLiteral(:final value)) {
        yield value;
      }
    }
  }
}

File? _resolveModule(String modulePath, String currentDirectory) {
  for (final extension in <String>['', '.lua']) {
    final candidate = File(
      p.normalize(p.join(currentDirectory, '$modulePath$extension')),
    );
    if (candidate.existsSync()) {
      return candidate;
    }
  }
  return null;
}

int _countLuacInstructions(String listing) {
  return RegExp(r'^\s*\d+\s+\[', multiLine: true).allMatches(listing).length;
}

int _countInstructions(LuaBytecodePrototype prototype) {
  return prototype.code.length +
      prototype.prototypes.fold<int>(0, (total, child) {
        return total + _countInstructions(child);
      });
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
