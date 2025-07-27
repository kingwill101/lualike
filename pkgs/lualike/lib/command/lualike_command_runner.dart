import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart' as pkg_logging;
import 'package:lualike/command/version_command.dart';
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
  static const String luaCompatVersion = '5.4';

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

    argParser.addOption(
      'category',
      help: 'Set log category to filter (only logs for this category)',
    );

    argParser.addFlag(
      'ast',
      help: 'Use AST interpreter (default)',
      defaultsTo: true,
    );

    argParser.addFlag('bytecode', help: 'Use bytecode VM', defaultsTo: false);

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
    // Enable hierarchical logging
    pkg_logging.hierarchicalLoggingEnabled = true;

    try {
      // Parse arguments
      final argResults = argParser.parse(args);

      if (argResults['help'] as bool) {
        throw UsageException(usage, usage);
      }

      // Handle debug mode
      if (argResults['debug'] as bool) {
        debugMode = true;
        print('Debug mode enabled');
      }

      // Set up logging
      final logLevel = argResults['level'] as String?;
      final logCategory = argResults['category'] as String?;

      pkg_logging.Level? cliLevel;
      if (logLevel != null && logLevel.isNotEmpty) {
        cliLevel = pkg_logging.Level.LEVELS.firstWhere(
          (lvl) => lvl.name.toUpperCase() == logLevel.toUpperCase(),
          orElse: () => pkg_logging.Level.WARNING,
        );
      }

      setLualikeLogging(
        enabled: debugMode,
        level: cliLevel,
        category: logCategory,
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
      final restArgs = argResults.rest;
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
