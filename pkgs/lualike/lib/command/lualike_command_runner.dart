import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lualike/command/version_command.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/logging/level.dart' as ctx;
import 'package:lualike/src/logging/logging.dart';

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

  LuaLikeCommandRunner()
    : super(
        'lualike',
        'LuaLike $lualikeVersion - A Lua-like scripting language for Dart\n'
            'Lua $luaCompatVersion compatible\n'
            'Usage: lualike [options] [script [args]]',
      ) {
    argParser.addFlag(
      'debug',
      help: 'Enable debug mode with detailed logging',
      negatable: false,
    );

    // argParser.addFlag('help', help: 'Show help', negatable: false);

    argParser.addOption(
      'level',
      help: 'Set log level (FINE, INFO, WARNING, SEVERE, etc)',
    );

    argParser.addMultiOption(
      'category',
      help: 'Set log category filter (repeatable or comma-separated)',
      splitCommas: true,
    );

    argParser.addFlag(
      'ast',
      help: 'Use AST interpreter (default)',
      defaultsTo: true,
    );

    argParser.addFlag('ir', help: 'Use lualike IR runtime', defaultsTo: false);

    argParser.addFlag(
      'lua-bytecode',
      help: 'Use the opt-in lua_bytecode source engine',
      defaultsTo: false,
    );

    argParser.addFlag(
      'dump-ir',
      help: 'Print IR instructions after compilation (IR mode)',
      negatable: false,
      defaultsTo: false,
    );

    // Add standard Lua options
    argParser.addMultiOption(
      'execute',
      abbr: 'e',
      help: 'Execute string',
      valueHelp: 'code',
      splitCommas: false,
    );

    argParser.addMultiOption(
      'require',
      abbr: 'l',
      help: 'Require file',
      valueHelp: 'file',
      splitCommas: false,
    );

    argParser.addFlag(
      'interactive',
      abbr: 'i',
      help: 'Enter interactive mode after running script',
      negatable: false,
    );

    argParser.addFlag(
      'version',
      abbr: 'v',
      help: 'Print version information',
      negatable: false,
    );

    argParser.addFlag(
      'stdin',
      help: 'Execute stdin as a file (use - on command line)',
      negatable: false,
      hide: true,
    );
  }

  @override
  Future<void> run(Iterable<String> args) async {
    // Contextual backend is used by default; no hierarchical setup required.

    try {
      // Parse arguments
      final argResults = argParser.parse(args);
      final restArgs = argResults.rest;

      if (argResults['help'] as bool) {
        throw UsageException(usage, usage);
      }

      final config = LuaLikeConfig();
      final useIr = argResults['ir'] as bool;
      final useLuaBytecode = argResults['lua-bytecode'] as bool;
      final useAst = argResults['ast'] as bool;
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
      BaseCommand.resetBridge();

      // Handle debug mode
      if (argResults['debug'] as bool) {
        debugMode = true;
        print('Debug mode enabled');
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

      // Note: execution mode is handled by individual commands

      // Handle special case where no arguments provided
      if (args.isEmpty) {
        if (stdin.hasTerminal) {
          // Terminal mode: show version and enter interactive mode
          final versionCmd = VersionCommand();
          await versionCmd.run();
          final interactiveCmd = InteractiveCommandWrapper(
            debugMode: debugMode,
          );
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

      // Handle version flag
      if (argResults['version'] as bool) {
        final versionCmd = VersionCommand();
        await versionCmd.run();
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
    } catch (e) {
      if (e is UsageException) {
        print(usage);
        exit(1);
      }
      rethrow;
    }
  }
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
    return looksLikeTrackedLuaBytecodeBytes(file.readAsBytesSync());
  } catch (_) {
    return false;
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
