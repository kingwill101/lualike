import 'base_command.dart';

/// Command to execute code strings (-e flag)
class ExecuteCommand extends BaseCommand {
  @override
  String get name => 'execute';

  @override
  String get description => 'Execute a string of Lua code';

  final String code;
  final List<String> originalArgs;

  ExecuteCommand(this.code, this.originalArgs);

  @override
  Future<void> run() async {
    try {
      // Setup arg table for -e mode
      setupArgTable(originalArgs: originalArgs, codeStrings: [code]);

      // Use a special script path name for code executed via -e
      // This allows debug.getinfo to report something meaningful for -e code
      const scriptPath = '<command line>';
      
      // Execute with script path for proper line tracking
      await bridge.execute(code, scriptPath: scriptPath);
    } catch (e) {
      safePrint('Error executing code: $e');
      rethrow;
    }
  }
}
