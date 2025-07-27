import 'dart:io';

import 'package:test/test.dart';

class Compare {
  String _luaCommand = '';
  String _replCommand = '';

  Compare lua(String command) {
    _luaCommand = command;
    return this;
  }

  Compare repl(String command) {
    _replCommand = command;
    return this;
  }

  void execute() {
    List<String> luaArgs;
    List<String> replArgs;

    if (File(_luaCommand).existsSync()) {
      luaArgs = [_luaCommand];
      replArgs = ['run', 'bin/main.dart', _luaCommand];
    } else {
      luaArgs = ['-e', _luaCommand];
      replArgs = ['run', 'bin/main.dart', '-e', _replCommand];
    }

    final luaResult = Process.runSync('lua', luaArgs);
    final replResult = Process.runSync('dart', replArgs);

    print('Lua Result:');
    print(luaResult.stdout);
    print('REPL Result:');
    print(replResult.stdout);

    expect(
      luaResult.stdout.trim(),
      equals(replResult.stdout.trim()),
      reason: 'Results do not match.',
    );
  }

  Compare and(String nextCommand) {
    _luaCommand += '; $nextCommand';
    _replCommand += '; $nextCommand';
    return this;
  }

  void assertResultsMatch() {
    List<String> luaArgs;
    List<String> replArgs;

    if (File(_luaCommand).existsSync()) {
      luaArgs = [_luaCommand];
      replArgs = ['run', 'bin/main.dart', _luaCommand];
    } else {
      luaArgs = ['-e', _luaCommand];
      replArgs = ['run', 'bin/main.dart', '-e', _replCommand];
    }

    final luaResult = Process.runSync('lua', luaArgs);
    final replResult = Process.runSync('dart', replArgs);

    expect(
      luaResult.stdout.trim(),
      equals(replResult.stdout.trim()),
      reason: 'Results do not match.',
    );
  }
}

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    print('Usage: dart compare.dart <lua_command_or_file>');
    exit(1);
  }

  final input = arguments.join(' ');
  Compare().lua(input).repl(input).execute();
}
