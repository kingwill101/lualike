import 'base_command.dart';

/// Command to require modules (-l flag)
class RequireCommand extends BaseCommand {
  @override
  String get name => 'require';

  @override
  String get description => 'Require a Lua module';

  final String moduleName;
  final List<String> originalArgs;

  RequireCommand(this.moduleName, this.originalArgs);

  @override
  Future<void> run() async {
    try {
      // Setup arg table for -l mode
      setupArgTable(originalArgs: originalArgs);

      // Load the module
      await bridge.runCode('require("$moduleName")');
    } catch (e) {
      safePrint('Error requiring module "$moduleName": $e');
      rethrow;
    }
  }
}
