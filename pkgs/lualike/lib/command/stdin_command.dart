import 'dart:convert';
import 'dart:io';

import 'base_command.dart';

/// Command to execute code from stdin
class StdinCommand extends BaseCommand {
  @override
  String get name => 'stdin';

  @override
  String get description => 'Execute code from stdin';

  final List<String> scriptArgs;
  final List<String> originalArgs;

  StdinCommand(this.scriptArgs, this.originalArgs);

  @override
  Future<void> run() async {
    try {
      // Setup arg table for stdin
      setupArgTable(
        originalArgs: originalArgs,
        scriptPath: '', // Empty for stdin
        scriptArgs: scriptArgs,
      );

      // Read from stdin
      final lines = <String>[];
      await for (final line
          in stdin.transform(utf8.decoder).transform(LineSplitter())) {
        lines.add(line);
      }
      final code = lines.join('\n');
      await bridge.execute(code);
    } catch (e) {
      safePrint('Error executing stdin: $e');
      rethrow;
    }
  }
}
