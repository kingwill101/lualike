import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:lualike/docs.dart';
import 'package:lualike/command/version_command.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/interop.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/logging/level.dart' as ctx;
import 'package:lualike/src/logging/logging.dart';
import 'package:lualike/src/parse.dart';

import 'base_command.dart';
import 'execute_command.dart';
import 'interactive_command_wrapper.dart';
import 'require_command.dart';
import 'script_command.dart';
import 'stdin_command.dart';

/// Main command runner for LuaLike following Lua CLI specification
class LuaLikeCommandRunner extends CommandRunner {
  static const String lualikeVersion = '0.0.1';
  static const String luaCompatVersion = '5.5';

  bool debugMode = false;

  @override
  String get invocation => '$executableName [options] [script [args]]';

  LuaLikeCommandRunner()
    : super(
        'lualike',
        'LuaLike $lualikeVersion - A Lua-like scripting language for Dart\n'
            'Lua $luaCompatVersion compatible',
      ) {
    argParser
      ..addFlag(
        'debug',
        help: 'Enable debug mode with detailed logging',
        negatable: false,
      )
      ..addOption(
        'level',
        help: 'Set log level (FINE, INFO, WARNING, SEVERE, etc)',
      )
      ..addMultiOption(
        'category',
        help: 'Set log category filter (repeatable or comma-separated)',
        splitCommas: true,
      )
      ..addFlag('ast', help: 'Use AST interpreter (default)', defaultsTo: true)
      ..addFlag('ir', help: 'Use lualike IR runtime', defaultsTo: false)
      ..addFlag(
        'lua-bytecode',
        help: 'Use the opt-in lua_bytecode source engine',
        defaultsTo: false,
      )
      ..addFlag(
        'dump-ir',
        help: 'Print IR instructions and exit without executing (IR mode)',
        negatable: false,
        defaultsTo: false,
      )
      ..addFlag(
        'emit-llvm',
        help:
            'Emit LLVM IR from the IR pipeline and exit without executing',
        negatable: false,
        defaultsTo: false,
      )
      ..addFlag(
        'emit-dart',
        help:
            'Emit Dart source from the IR pipeline and exit without executing',
        negatable: false,
        defaultsTo: false,
      )
      ..addFlag(
        'disassemble',
        help:
            'Print bytecode disassembly and exit without executing'
            ' (lua-bytecode mode)',
        negatable: false,
        defaultsTo: false,
      )
      ..addFlag(
        'raw',
        help: 'Skip bytecode peephole pass (raw lowering output)',
        negatable: false,
        defaultsTo: false,
      )
      ..addFlag(
        'fold',
        help: 'Enable constant folding pass for bytecode engines',
        negatable: true,
        defaultsTo: false,
      )
      ..addFlag(
        'compile',
        help:
            'Compile script to binary chunk; requires --output (do not execute)',
        negatable: false,
        defaultsTo: false,
      )
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Output path for --compile (required; any path — binary is '
            'detected by chunk header, not extension)',
        valueHelp: 'file',
      )
      ..addOption(
        'dart-output',
        help: 'Dart embed output file (precompiled_module.dart style)',
        valueHelp: 'file',
      )
      ..addFlag(
        'preserve-debug',
        help: 'Preserve debug line info in compiled bytecode',
        negatable: false,
        defaultsTo: false,
      )
      ..addMultiOption(
        'execute',
        abbr: 'e',
        help: 'Execute string',
        valueHelp: 'code',
        splitCommas: false,
      )
      ..addMultiOption(
        'require',
        abbr: 'l',
        help: 'Require file',
        valueHelp: 'file',
        splitCommas: false,
      )
      ..addFlag(
        'interactive',
        abbr: 'i',
        help: 'Enter interactive mode after running script',
        negatable: false,
      )
      ..addFlag('version', help: 'Print version information', negatable: false)
      ..addOption(
        'emit-docs',
        help: 'Emit built-in library documentation and exit.',
        allowed: const ['html', 'json', 'luals'],
        allowedHelp: const {
          'html': 'Shared documentation UI.',
          'json': 'Editor-friendly library metadata manifest.',
          'luals': 'LuaLS annotation stubs for existing Lua LSPs.',
        },
      )
      ..addOption(
        'lua-test',
        help:
            'Run a Lua test suite file with the standard test environment'
            ' (sets _port, _soft, package.path). Example: --lua-test calls',
        valueHelp: 'test',
      )
      ..addOption(
        'emit-docs-output',
        help: 'Output path for --emit-docs. Defaults to stdout.',
        valueHelp: 'path',
      )
      ..addFlag(
        'stdin',
        help: 'Execute stdin as a file (use - on command line)',
        negatable: false,
        hide: true,
      );
  }

  @override
  Future<void> run(Iterable<String> args) async {
    // artisanal.run(args) handles global setup and catches UsageException.
    // However, it expects subcommands. Since Lua uses flags for logic,
    // we need to handle the parsed results if no command matches.

    // Setup renderer etc by calling artisanal's run logic via super.run
    // But super.run will likely throw if we have no commands.

    // Let's use artisanal's public properties to mimic its behavior.

    final argResults = argParser.parse(args);

    if (argResults['help'] as bool) {
      printUsage();
      return;
    }

    if (argResults['version'] as bool) {
      final versionCmd = VersionCommand();
      await versionCmd.run();
      if (args.length == 1) return;
    }

    final restArgs = argResults.rest;
    final config = LuaLikeConfig();
    final useIr = argResults['ir'] as bool;
    final useLuaBytecode = argResults['lua-bytecode'] as bool;
    final useAst = argResults['ast'] as bool;
    // Precompiled chunks (detected by official Lua header bytes, not extension)
    // must use the bytecode VM so ScriptCommand can load+run without IR/SSA.
    final autoUseLuaBytecode =
        restArgs.isNotEmpty &&
        _looksLikeTrackedLuaBytecodeScript(restArgs.first);
    if (useLuaBytecode || autoUseLuaBytecode) {
      config.defaultEngineMode = EngineMode.luaBytecode;
    } else if (useIr || !useAst) {
      config.defaultEngineMode = EngineMode.ir;
    } else {
      config.defaultEngineMode = EngineMode.ast;
    }
    config.dumpIr = argResults['dump-ir'] as bool;
    config.emitLlvm = argResults['emit-llvm'] as bool;
    config.emitDart = argResults['emit-dart'] as bool;
    config.foldEnabled = argResults['fold'] as bool;

    // Handle --disassemble (print bytecode listing, no execution)
    if (argResults['disassemble'] as bool) {
      if (restArgs.isEmpty) {
        stderr.writeln('Error: --disassemble requires a script file argument.');
        exit(1);
      }
      final scriptPath = restArgs.first;
      final bytes = File(scriptPath).readAsBytesSync();
      try {
        // Official header → parse as binary chunk
        if (bytes.isNotEmpty && bytes.first == 0x1B) {
          final chunk = const LuaBytecodeParser().parse(bytes);
          print(const LuaBytecodeDisassembler().render(chunk));
        } else {
          final source = _decodeSource(bytes);
          final program = parse(source, url: scriptPath);
          final rawBc = argResults['raw'] as bool;
          final artifact = CompilePipeline(
            config: CompilePipelineConfig.luaBytecodeOptimized(
              enableBytecodePeephole: !rawBc,
            ),
          ).compile(program) as LuaBytecodeArtifact;
          print(const LuaBytecodeDisassembler().render(artifact.chunk));
        }
      } catch (e, st) {
        stderr.writeln('Disassembly failed: $e');
        stderr.writeln(st);
        exit(1);
      }
      exit(0);
    }

    // Handle --compile (compile-only, no execution)
    if (argResults['compile'] as bool) {
      if (restArgs.isEmpty) {
        stderr.writeln('Error: --compile requires a script file argument.');
        exit(1);
      }
      final scriptPath = restArgs.first;
      // No standard extension for binary chunks — caller must name the file.
      final outputPath = argResults['output'] as String?;
      if (outputPath == null || outputPath.isEmpty) {
        stderr.writeln(
          'Error: --compile requires --output / -o <path> '
          '(no default extension; binary is detected by header).',
        );
        exit(1);
      }
      _compileToBytecode(
        scriptPath,
        outputPath,
        dartOutputPath: argResults['dart-output'] as String?,
        preserveDebug: argResults['preserve-debug'] as bool,
      );
      return;
    }
    BaseCommand.resetBridge();

    final emitDocsFormat = argResults['emit-docs'] as String?;
    if (emitDocsFormat != null) {
      await _emitDocs(
        format: emitDocsFormat,
        output: argResults['emit-docs-output'] as String?,
      );
      return;
    }

    // Handle debug mode
    if (argResults['debug'] as bool) {
      debugMode = true;
      io.writeln('Debug mode enabled');
    }

    // Set up logging
    final logLevel = argResults['level'] as String?;
    final logCategories =
        (argResults['category'] as List<String>?) ?? const <String>[];

    ctx.Level? cliLevel;
    if (logLevel != null && logLevel.isNotEmpty) {
      cliLevel = parseLogLevel(logLevel) ?? ctx.Level.warning;
    }

    setLualikeLogging(
      enabled: debugMode,
      level: cliLevel,
      categories: logCategories.isEmpty ? null : logCategories,
    );

    // Handle special case where no arguments provided
    if (args.isEmpty) {
      if (stdin.hasTerminal) {
        // Terminal mode: show version and enter interactive mode
        final versionCmd = VersionCommand();
        await versionCmd.run();
        final interactiveCmd = InteractiveCommandWrapper(debugMode: debugMode);
        await interactiveCmd.run();
      } else {
        // Non-terminal mode: read from stdin
        final stdinCmd = StdinCommand([], args.toList());
        await stdinCmd.run();
      }
      return;
    }

    // Handle special case for single '-' argument (stdin)
    if (args.length == 1 && args.first == '-') {
      final stdinCmd = StdinCommand([], args.toList());
      await stdinCmd.run();
      return;
    }

    // Handle LUA_INIT using BaseCommand functionality
    final baseCmd = _LuaInitCommand();
    await baseCmd.handleLuaInit();

    // Handle require files (-l)
    final requireFiles = argResults['require'] as List<String>;
    for (final file in requireFiles) {
      final requireCmd = RequireCommand(file, args.toList());
      await requireCmd.run();
    }

    // Handle execute strings (-e)
    final executeStrings = argResults['execute'] as List<String>;
    for (final code in executeStrings) {
      final executeCmd = ExecuteCommand(code, args.toList());
      await executeCmd.run();
    }

    // Handle --lua-test (runs a Lua test suite file with standard env)
    final luaTest = argResults['lua-test'] as String?;
    if (luaTest != null) {
      final testFile = luaTest.endsWith('.lua') ? luaTest : '$luaTest.lua';
      final testPath = 'luascripts/test/$testFile';
      final initCode =
          '_port = true; _soft = true; '
          "package.path = 'luascripts/test/?.lua;luascripts/test/?/init.lua;?.lua;;'; "
          "dofile('$testPath')";
      final executeCmd = ExecuteCommand(initCode, args.toList());
      await executeCmd.run();
    }

    // Handle script file and arguments
    if (restArgs.isNotEmpty) {
      final scriptPath = restArgs.first;
      final scriptArgs = restArgs.skip(1).toList();
      final scriptCmd = ScriptCommand(scriptPath, scriptArgs, args.toList());
      await scriptCmd.run();
    }

    // Handle interactive mode (-i)
    if (argResults['interactive'] as bool) {
      final interactiveCmd = InteractiveCommandWrapper(debugMode: debugMode);
      await interactiveCmd.run();
    }
  }

  Future<void> _emitDocs({required String format, String? output}) async {
    final lua = LuaLike();
    final libraries = documentedLibrariesForRuntime(lua.vm);
    final rendered = switch (format) {
      'html' => renderDocsPage(libraries),
      'json' => renderDocsJson(
        libraries,
        packageName: 'lualike',
        packageVersion: lualikeVersion,
      ),
      'luals' => renderLuaLsAnnotations(
        libraries,
        packageName: 'lualike',
        packageVersion: lualikeVersion,
      ),
      _ => throw ArgumentError.value(format, 'format'),
    };

    if (output == null || output == '-') {
      stdout.write(rendered);
      if (!rendered.endsWith('\n')) {
        stdout.writeln();
      }
      return;
    }

    await File(output).writeAsString(rendered);
  }
}

/// Compiles [scriptPath] to bytecode and writes to [outputPath], then exits.
void _compileToBytecode(
  String scriptPath,
  String outputPath, {
  String? dartOutputPath,
  bool preserveDebug = false,
}) {
  final source = File(scriptPath).readAsStringSync();
  // --compile uses the same IR+SSA pipeline as --lua-bytecode execution.
  // stripDebug is the OPPOSITE of preserveDebug (strip = remove debug).
  final pipeline = CompilePipeline(
    config: CompilePipelineConfig.luaBytecodeOptimized(
      stripDebug: !preserveDebug,
      enableLoopUnrolling: false,
    ),
  );
  final artifact = pipeline.compileSource(source, chunkName: scriptPath);
  final bytes = artifact.serializedBytes;
  File(outputPath).writeAsBytesSync(bytes);
  stderr.writeln(
    'Compiled $scriptPath → $outputPath '
    '(${bytes.length} bytes)',
  );

  if (dartOutputPath != null && dartOutputPath.isNotEmpty) {
    _writeDartEmbed(bytes, dartOutputPath, scriptPath);
  }

  exit(0);
}

/// Write a Dart embed file containing the bytecode as a literal list.
/// Like Hetu's precompiled_module.dart pattern.
void _writeDartEmbed(List<int> bytes, String outputPath, String scriptPath) {
  final buf = StringBuffer();
  final varName = '${scriptPath.split('/').last.replaceAll('.', '_')}Module';
  buf.writeln("/// Pre-compiled bytecode module. Generated by lualike.");
  buf.writeln("final $varName = <int>[");
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
  File(outputPath).writeAsStringSync(buf.toString());
  stderr.writeln('Dart embed → $outputPath');
}

bool _looksLikeTrackedLuaBytecodeScript(String scriptPath) {
  if (scriptPath == '-') {
    return false;
  }

  try {
    final file = File(scriptPath);
    if (!file.existsSync()) {
      return false;
    }
    // Only the first 40 bytes are needed for header detection; avoid reading
    // the entire file here since ScriptCommand will read it again later.
    final raf = file.openSync();
    try {
      final header = raf.readSync(40);
      return looksLikeTrackedLuaBytecodeBytes(header);
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return false;
  }
}

String _decodeSource(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Temporary command for accessing BaseCommand functionality
class _LuaInitCommand extends BaseCommand {
  @override
  String get name => 'lua_init';

  @override
  String get description => 'Handle LUA_INIT';

  @override
  Future<void> run() async {
    // This is only used for accessing handleLuaInit
  }
}
