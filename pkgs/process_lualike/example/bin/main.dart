import 'dart:convert';
import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:process_lualike/process_lualike.dart';

class LocalProcessBackend implements ProcessBackend {
  @override
  bool get isShellAvailable => true;

  @override
  ProcessRunResult runSync(String command) {
    final result = Process.runSync(
      Platform.isWindows ? 'cmd' : 'sh',
      Platform.isWindows ? ['/c', command] : ['-c', command],
    );
    return ProcessRunResult(
      result.exitCode as int,
      result.stdout.toString(),
      result.stderr.toString(),
    );
  }

  @override
  Future<ProcessRunResult> run(String command) async {
    final result = await Process.run(
      Platform.isWindows ? 'cmd' : 'sh',
      Platform.isWindows ? ['/c', command] : ['-c', command],
    );
    return ProcessRunResult(
      result.exitCode as int,
      result.stdout.toString(),
      result.stderr.toString(),
    );
  }

  @override
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  }) async {
    final result = await run(command);
    onStdout?.call(utf8.encode(result.stdout));
    onStderr?.call(utf8.encode(result.stderr));
    onDone?.call();
    return result.exitCode;
  }
}

Future<void> main() async {
  useProcessBackend(LocalProcessBackend());

  final lua = LuaLike();
  print('LuaLike process backend example');

  await lua.execute('''
    local ok, kind, code = os.execute("echo process_lualike works")
    print(ok, kind, code)
  ''');
}
