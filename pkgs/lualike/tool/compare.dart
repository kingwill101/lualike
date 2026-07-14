import 'dart:io';

import 'package:artisanal/args.dart';

import 'compare_disasm.dart';
import 'compare_ir.dart';

Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<void>(
          'lualike_compare',
          'Compare lualike optimization output with unoptimized IR and luac55.',
        )
        ..addCommand(_DisassemblyCommand())
        ..addCommand(_IrCommand())
        ..addCommand(_FoldingCommand());

  await runner.run(arguments);
}

abstract class _CompareCommand extends Command<void> {
  Future<void> runGuarded(Future<void> Function() action) async {
    try {
      await action();
    } on ArgumentError catch (error) {
      usageException(error.message?.toString() ?? error.toString());
    }
  }

  String requireSinglePath() {
    final paths = argResults!.rest;
    if (paths.length != 1) {
      usageException('Expected exactly one file or directory path.');
    }
    return paths.single;
  }
}

class _DisassemblyCommand extends _CompareCommand {
  _DisassemblyCommand() {
    argParser.addFlag(
      'bundle',
      abbr: 'b',
      negatable: false,
      help: 'Bundle static require dependencies before disassembly.',
    );
  }

  @override
  String get name => 'disasm';

  @override
  String get description =>
      'Compare luac55 and lualike disassembly for a file or directory.';

  @override
  String get invocation => '$name [--bundle] <file-or-directory>';

  @override
  Future<void> run() => runGuarded(() async {
    final path = requireSinglePath();
    final forceBundle = argResults!['bundle'] as bool;
    final directory = Directory(path);
    if (await directory.exists()) {
      var succeeded = true;
      final files = await directory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.lua'))
          .cast<File>()
          .toList();
      files.sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        succeeded =
            await compareDisassembly(
              file,
              io: io,
              bundle: forceBundle || hasStaticRequires(file),
            ) &&
            succeeded;
      }
      if (!succeeded) {
        exitCode = 1;
      }
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      throw ArgumentError('File not found: $path');
    }
    final succeeded = await compareDisassembly(
      file,
      io: io,
      bundle: forceBundle || hasStaticRequires(file),
    );
    if (!succeeded) {
      exitCode = 1;
    }
  });
}

class _IrCommand extends _CompareCommand {
  _IrCommand() {
    argParser.addFlag(
      'bundle',
      abbr: 'b',
      negatable: false,
      help: 'Bundle static require dependencies for optimized variants.',
    );
  }

  @override
  String get name => 'ir';

  @override
  String get description =>
      'Compare IR size with optimizations off, on, and on with SSA.';

  @override
  String get invocation => '$name [--bundle] [file-or-directory]';

  @override
  Future<void> run() => runGuarded(() async {
    final paths = argResults!.rest;
    if (paths.length > 1) {
      usageException('Expected at most one file or directory path.');
    }
    await compareIrPath(
      paths.isEmpty ? null : paths.single,
      io: io,
      bundle: argResults!['bundle'] as bool,
    );
  });
}

class _FoldingCommand extends _CompareCommand {
  _FoldingCommand() {
    argParser.addFlag(
      'disassemble',
      abbr: 'd',
      negatable: false,
      help: 'Also compare luac55 and lualike disassembly for every fixture.',
    );
  }

  @override
  String get name => 'folding';

  @override
  String get description => 'Validate every folding fixture and bundle.';

  @override
  Future<void> run() => runGuarded(() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('The folding command does not accept path arguments.');
    }

    const fixturePath = 'luascripts/folding';
    await compareIrPath(fixturePath, io: io, bundle: true);
    if (!(argResults!['disassemble'] as bool)) {
      return;
    }

    final files = await Directory(fixturePath)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.lua'))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    var succeeded = true;
    for (final file in files) {
      succeeded =
          await compareDisassembly(
            file,
            io: io,
            bundle: hasStaticRequires(file),
          ) &&
          succeeded;
    }
    if (!succeeded) {
      exitCode = 1;
    }
  });
}
