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

      await bridge.execute(code);
    } catch (e) {
      safePrint('Error executing code: $e');
      rethrow;
    }
  }
}
