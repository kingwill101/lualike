import 'package:lualike/src/parse.dart';

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

  /// Whether [source] parses as a valid Lua chunk.
  bool _parses(String source) {
    try {
      parse(source);
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  Future<void> run() async {
    try {
      // Setup arg table for -e mode
      setupArgTable(originalArgs: originalArgs, codeStrings: [code]);

      // Use a special script path name for code executed via -e
      // This allows debug.getinfo to report something meaningful for -e code
      const scriptPath = '<command line>';

      // Lua chunks must be statements.  If the raw code doesn't parse (e.g.
      // `-e "1+2"` is an expression, not a statement), wrap with `return`.
      final source = _parses(code) ? code : 'return $code';

      await bridge.execute(source, scriptPath: scriptPath);
    } catch (e) {
      safePrint('Error executing code: $e');
      rethrow;
    }
  }
}
