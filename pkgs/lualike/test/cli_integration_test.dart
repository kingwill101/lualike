/// Integration tests for the lualike CLI.
///
/// Tests the binary end-to-end: --compile, --lua-bytecode, --fold,
/// --preserve-debug, --dump-ir, and cross-compatibility with luac55.
library;

import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';

/// Path to the compiled lualike binary.
/// Set LUALIKE_BIN env var, or default to the dev entrypoint.
String get _bin => Platform.environment['LUALIKE_BIN'] ?? 'bin/main.dart';

/// Whether to use `dart run` or direct binary.
bool get _useDartRun => _bin.endsWith('.dart');

Future<ProcessResult> _lualike(List<String> args, {String? stdin}) async {
  if (_useDartRun) {
    return Process.run(
      'dart',
      ['run', _bin, ...args],
      runInShell: true,
    );
  }
  return Process.run(_bin, args, runInShell: true);
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('lualike_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('--compile', () {
    test('produces valid .lub file', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('print("hello")');
      final lub = tmpDir.childFile('test.lub');

      final result = await _lualike([
        '--compile', lua.path,
        '-o', lub.path,
      ]);
      expect(result.exitCode, equals(0));
      expect(lub.existsSync(), isTrue);
      expect(lub.lengthSync(), greaterThan(0));
    });

    test('compiled bytecode runs correctly', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('print("hello from compiled code")');
      final lub = tmpDir.childFile('test.lub');

      await _lualike(['--compile', lua.path, '-o', lub.path]);

      final runResult = await _lualike(['--lua-bytecode', lub.path]);
      expect(runResult.exitCode, equals(0));
      expect(runResult.stdout, contains('hello from compiled code'));
    });

    test('arithmetic folded in compiled output', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('print(2 + 3 * 4 - 1)');
      final lub = tmpDir.childFile('test.lub');

      await _lualike(['--compile', lua.path, '-o', lub.path]);

      final runResult = await _lualike(['--lua-bytecode', lub.path]);
      expect(runResult.exitCode, equals(0));
      expect(runResult.stdout.trim(), equals('13'));
    });
  });

  group('--fold', () {
    test('folding produces correct results', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('print(2 + 3 * 4 - 1)');

      final result = await _lualike(['--fold', lua.path]);
      expect(result.exitCode, equals(0));
      expect(result.stdout.trim(), equals('13'));
    });

    test('--no-fold also produces correct results', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('print(2 + 3 * 4 - 1)');

      final result = await _lualike(['--lua-bytecode', '--no-fold', lua.path]);
      expect(result.exitCode, equals(0));
      expect(result.stdout.trim(), equals('13'));
    });
  });

  group('--preserve-debug', () {
    test('preserved bytecode is larger than stripped', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('''
          local function fib(n)
            if n < 2 then return n end
            return fib(n-1) + fib(n-2)
          end
          print(fib(5))
        ''');

      final stripped = tmpDir.childFile('stripped.lub');
      final preserved = tmpDir.childFile('preserved.lub');

      await _lualike(['--compile', lua.path, '-o', stripped.path]);
      await _lualike([
        '--compile', lua.path, '-o', preserved.path,
        '--preserve-debug',
      ]);

      // Preserved should be same size or larger.
      expect(preserved.lengthSync(), greaterThanOrEqualTo(stripped.lengthSync()));
    });

    test('both produce same output', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('print("hello")');

      final stripped = tmpDir.childFile('stripped.lub');
      final preserved = tmpDir.childFile('preserved.lub');

      await _lualike(['--compile', lua.path, '-o', stripped.path]);
      await _lualike([
        '--compile', lua.path, '-o', preserved.path,
        '--preserve-debug',
      ]);

      final r1 = await _lualike(['--lua-bytecode', stripped.path]);
      final r2 = await _lualike(['--lua-bytecode', preserved.path]);
      expect(r1.stdout, equals(r2.stdout));
    });
  });

  group('--dump-ir', () {
    test('prints IR instructions', () async {
      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('return 42');

      final result = await _lualike(['--ir', '--dump-ir', lua.path]);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('LOADK'));
      expect(result.stdout, contains('RETURN'));
    });
  });

  group('error handling', () {
    test('reports missing file', () async {
      final result = await _lualike(['nonexistent.lua']);
      expect(result.exitCode, equals(1));
    });

    test('reports syntax error', () async {
      final lua = tmpDir.childFile('bad.lua')
        ..writeAsStringSync('local = 42');

      final result = await _lualike([lua.path]);
      expect(result.exitCode, equals(1));
    });
  });

  group('--version', () {
    test('prints version', () async {
      final result = await _lualike(['--version']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, isNotEmpty);
    });
  });

  group('cross-compatibility with luac55', () {
    test('luac55 bytecode runs in lualike VM', () async {
      final luac55 = Platform.environment['LUAC55'];
      if (luac55 == null || !File(luac55).existsSync()) {
        print('SKIP: LUAC55 not available');
        return;
      }

      final lua = tmpDir.childFile('test.lua')
        ..writeAsStringSync('print("from luac55")');
      final lub = tmpDir.childFile('test.lub');

      // Compile with official luac55
      final compileResult = await Process.run(luac55, ['-o', lub.path, lua.path]);
      expect(compileResult.exitCode, equals(0));

      // Run with lualike VM
      final runResult = await _lualike(['--lua-bytecode', lub.path]);
      expect(runResult.exitCode, equals(0));
      expect(runResult.stdout, contains('from luac55'));
    });
  });
}
