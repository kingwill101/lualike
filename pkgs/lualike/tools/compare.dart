import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    print('Usage: dart compare.dart <lua_command_or_file>');
    exit(1);
  }

  final input = arguments.join(' ');
  List<String> luaArgs;
  List<String> replArgs;

  if (File(input).existsSync()) {
    luaArgs = [input];
    replArgs = ['run', 'bin/main.dart', input];
  } else {
    luaArgs = ['-e', input];
    replArgs = ['run', 'bin/main.dart', '-e', input];
  }

  final luaResult = Process.runSync('lua', luaArgs);
  final replResult = Process.runSync('dart', replArgs);

  print('Lua Result:');
  print(luaResult.stdout);
  print('REPL Result:');
  print(replResult.stdout);

  assert(luaResult.stdout.trim() == replResult.stdout.trim());
}
