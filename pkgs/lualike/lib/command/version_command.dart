import 'base_command.dart';

/// Command to display version information (-v flag)
class VersionCommand extends BaseCommand {
  @override
  String get name => 'version';

  @override
  String get description => 'Display version information';

  @override
  Future<void> run() async {
    safePrint('LuaLike 1.0.0  Copyright (C) 2024 LuaLike Contributors');
    safePrint('Based on Lua 5.4.7  Copyright (C) 1994-2024 Lua.org, PUC-Rio');
  }
}
