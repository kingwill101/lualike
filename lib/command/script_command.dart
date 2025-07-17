import 'dart:convert';

import 'dart:io';

import 'base_command.dart';

/// Command to execute script files
class ScriptCommand extends BaseCommand {
  @override
  String get name => 'script';

  @override
  String get description => 'Execute a Lua script file';

  final String scriptPath;
  final List<String> scriptArgs;
  final List<String> originalArgs;

  ScriptCommand(this.scriptPath, this.scriptArgs, this.originalArgs);

  @override
  Future<void> run() async {
    try {
      // Setup arg table for script mode
      setupArgTable(
        originalArgs: originalArgs,
        scriptPath: scriptPath,
        scriptArgs: scriptArgs,
      );

      // Execute the script
      final file = File(scriptPath);
      if (!file.existsSync()) {
        safePrint('Error: Script file "$scriptPath" not found');
        exit(1);
      }

      final sourceCode = await file.readAsBytes().then(
        (bytes) => utf8.decode(bytes),
      );
      await bridge.execute(sourceCode, scriptPath: scriptPath);
    } catch (e) {
      safePrint('Error executing script "$scriptPath": $e');
      rethrow;
    }
  }
}
