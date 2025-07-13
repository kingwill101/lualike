import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('luascripts/test/bitwise.lua runs to completion', () async {
    final result = await Process.run('dart', [
      'run',
      'bin/main.dart',
      'luascripts/test/bitwise.lua',
    ]);
    expect(result.exitCode, equals(0));
    expect(result.stdout.toString().trim().endsWith('OK'), isTrue);
  });
}
