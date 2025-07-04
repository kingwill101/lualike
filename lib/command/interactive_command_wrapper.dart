import 'base_command.dart';
import 'interactive_command.dart';

/// Command wrapper for interactive mode
class InteractiveCommandWrapper extends BaseCommand {
  @override
  String get name => 'interactive';

  @override
  String get description => 'Enter interactive REPL mode';

  final bool debugMode;

  InteractiveCommandWrapper({this.debugMode = false});

  @override
  Future<void> run() async {
    final interactive = InteractiveMode(
      executionMode: executionMode,
      bridge: bridge, // Use the shared bridge
      debugMode: debugMode,
    );
    await interactive.run();
  }
}
