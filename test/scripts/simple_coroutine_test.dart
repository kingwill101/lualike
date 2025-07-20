import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('coroutine.resume does not clear caller variables', () async {
    final scriptPath = '/tmp/simple.lua';
    await File(scriptPath).writeAsString('''
f = coroutine.create(function() coroutine.yield() end)
local s = coroutine.resume(f)
print(type(f))
''');
    final result = await Process.run('dart', [
      'run',
      'bin/main.dart',
      scriptPath,
    ]);
    expect(result.exitCode, equals(0));
    expect(
      result.stdout.toString().trim().split("\n").last,
      contains('thread'),
    );
  });
}
