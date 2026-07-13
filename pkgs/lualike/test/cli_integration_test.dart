/// Integration tests for the lualike CLI.
///
/// Tests the binary end-to-end: --compile, --lua-bytecode, --fold,
/// --preserve-debug, --dump-ir, and cross-compatibility with luac55.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/package_paths.dart';

/// Path to the compiled lualike binary.
/// Set LUALIKE_BIN env var, or default to the dev entrypoint.
String get _bin =>
    Platform.environment['LUALIKE_BIN'] ?? packagePath('bin/main.dart');

/// Whether to use `dart run` or direct binary.
bool get _useDartRun => _bin.endsWith('.dart');

Future<ProcessResult> _lualike(List<String> args) async {
  if (_useDartRun) {
    return Process.run('dart', ['run', _bin, ...args], runInShell: true);
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
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('print("hello")');
      final lub = File(p.join(tmpDir.path, 'test.lub'));

      final result = await _lualike(['--compile', lua.path, '-o', lub.path]);
      expect(result.exitCode, equals(0));
      expect(lub.existsSync(), isTrue);
      expect(lub.lengthSync(), greaterThan(0));
    }, timeout: Timeout.factor(4));

    test('compiled bytecode runs correctly', () async {
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('print("hello from compiled code")');
      final lub = File(p.join(tmpDir.path, 'test.lub'));

      await _lualike(['--compile', lua.path, '-o', lub.path]);

      final runResult = await _lualike(['--lua-bytecode', lub.path]);
      expect(runResult.exitCode, equals(0));
      expect(runResult.stdout, contains('hello from compiled code'));
    }, timeout: Timeout.factor(4));

    test('arithmetic folded in compiled output', () async {
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('print(2 + 3 * 4 - 1)');
      final lub = File(p.join(tmpDir.path, 'test.lub'));

      await _lualike(['--compile', lua.path, '-o', lub.path]);

      final runResult = await _lualike(['--lua-bytecode', lub.path]);
      expect(runResult.exitCode, equals(0));
      expect(runResult.stdout.trim(), equals('13'));
    }, timeout: Timeout.factor(4));
  });

  group('--fold', () {
    test('folding produces correct results', () async {
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('print(2 + 3 * 4 - 1)');

      final result = await _lualike(['--fold', lua.path]);
      expect(result.exitCode, equals(0));
      expect(result.stdout.trim(), equals('13'));
    }, timeout: Timeout.factor(4));

    test('--no-fold also produces correct results', () async {
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('print(2 + 3 * 4 - 1)');

      final result = await _lualike(['--lua-bytecode', '--no-fold', lua.path]);
      expect(result.exitCode, equals(0));
      expect(result.stdout.trim(), equals('13'));
    }, timeout: Timeout.factor(4));
  });

  group('--preserve-debug', () {
    test('preserved bytecode is larger than stripped', () async {
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('''
          local function fib(n)
            if n < 2 then return n end
            return fib(n-1) + fib(n-2)
          end
          print(fib(5))
        ''');

      final stripped = File(p.join(tmpDir.path, 'stripped.lub'));
      final preserved = File(p.join(tmpDir.path, 'preserved.lub'));

      await _lualike(['--compile', lua.path, '-o', stripped.path]);
      await _lualike([
        '--compile',
        lua.path,
        '-o',
        preserved.path,
        '--preserve-debug',
      ]);

      // Preserved should be same size or larger.
      expect(
        preserved.lengthSync(),
        greaterThanOrEqualTo(stripped.lengthSync()),
      );
    }, timeout: Timeout.factor(4));

    test('both produce same output', () async {
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('print("hello")');

      final stripped = File(p.join(tmpDir.path, 'stripped.lub'));
      final preserved = File(p.join(tmpDir.path, 'preserved.lub'));

      await _lualike(['--compile', lua.path, '-o', stripped.path]);
      await _lualike([
        '--compile',
        lua.path,
        '-o',
        preserved.path,
        '--preserve-debug',
      ]);

      final r1 = await _lualike(['--lua-bytecode', stripped.path]);
      final r2 = await _lualike(['--lua-bytecode', preserved.path]);
      expect(r1.stdout, equals(r2.stdout));
    }, timeout: Timeout.factor(4));
  });

  group('--dump-ir', () {
    test('prints IR instructions', () async {
      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('return 42');

      final result = await _lualike(['--ir', '--dump-ir', lua.path]);
      expect(result.exitCode, equals(0));
      expect(result.stderr, contains('LOADI'));
      expect(result.stderr, contains('RETURN'));
    }, timeout: Timeout.factor(4));
  });

  group('error handling', () {
    test('reports missing file', () async {
      final result = await _lualike(['nonexistent.lua']);
      expect(result.exitCode, equals(1));
    }, timeout: Timeout.factor(4));

    test('reports syntax error', () async {
      final lua = File(p.join(tmpDir.path, 'bad.lua'))
        ..writeAsStringSync('local = 42');

      final result = await _lualike([lua.path]);
      expect(result.exitCode, equals(1));
    }, timeout: Timeout.factor(4));
  });

  group('--version', () {
    test('prints version', () async {
      final result = await _lualike(['--version']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, isNotEmpty);
    }, timeout: Timeout.factor(4));
  });

  group('cross-compatibility with luac55', () {
    test('luac55 bytecode runs in lualike VM', () async {
      final luac55 = await _resolveLuac55Binary();

      final lua = File(p.join(tmpDir.path, 'test.lua'))
        ..writeAsStringSync('print("from luac55")');
      final lub = File(p.join(tmpDir.path, 'test.lub'));

      // Compile with official luac55
      final compileResult = await Process.run(luac55, [
        '-o',
        lub.path,
        lua.path,
      ]);
      expect(compileResult.exitCode, equals(0));

      // Run with lualike VM
      final runResult = await _lualike(['--lua-bytecode', lub.path]);
      expect(runResult.exitCode, equals(0));
      expect(runResult.stdout, contains('from luac55'));
    }, timeout: Timeout.factor(4));
  });
}

Future<String> _resolveLuac55Binary() async {
  final envPath = Platform.environment['LUAC55'];
  if (envPath != null && File(envPath).existsSync()) {
    return envPath;
  }

  final cachedPath = _findLuacBinary(_luacCacheDir);
  if (cachedPath != null) {
    return cachedPath;
  }

  await _downloadLuac55Binary();

  final resolvedPath = _findLuacBinary(_luacCacheDir);
  if (resolvedPath != null) {
    return resolvedPath;
  }

  throw StateError('Failed to resolve a luac55 binary after download');
}

Directory get _luacCacheDir =>
    Directory(p.join(Directory.systemTemp.path, 'lualike_luac55_cache'));

String _luac55DownloadUrl() {
  if (Platform.isWindows) {
    return 'https://downloads.sourceforge.net/project/luabinaries/5.5.0/Tools%20Executables/lua-5.5.0_Win64_bin.zip';
  }
  if (Platform.isMacOS) {
    return 'https://downloads.sourceforge.net/project/luabinaries/5.5.0/Tools%20Executables/lua-5.5.0_MacOS1011_bin.tar.gz';
  }
  return 'https://downloads.sourceforge.net/project/luabinaries/5.5.0/Tools%20Executables/lua-5.5.0_Linux515_64_bin.tar.gz';
}

Future<void> _downloadLuac55Binary() async {
  _luacCacheDir.createSync(recursive: true);

  final url = Uri.parse(_luac55DownloadUrl());
  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to download luac55 from $url: ${response.statusCode}',
    );
  }

  final archiveBytes = response.bodyBytes;
  if (url.path.endsWith('.zip')) {
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    _extractArchive(archive, _luacCacheDir);
  } else {
    final archive = TarDecoder().decodeBytes(gzip.decode(archiveBytes));
    _extractArchive(archive, _luacCacheDir);
  }
}

void _extractArchive(Archive archive, Directory destination) {
  for (final entry in archive) {
    final relativePath = p.posix.normalize(entry.name);
    final outputPath = p.joinAll(<String>[
      destination.path,
      ...p.posix.split(relativePath),
    ]);
    if (entry.isFile) {
      final outputFile = File(outputPath);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsBytesSync(entry.content as List<int>);
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['+x', outputFile.path]);
      }
    } else {
      Directory(outputPath).createSync(recursive: true);
    }
  }
}

String? _findLuacBinary(Directory root) {
  if (!root.existsSync()) {
    return null;
  }

  final candidates = <String>['luac55', 'luac', 'luac55.exe', 'luac.exe'];

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final base = p.basename(entity.path);
    if (candidates.contains(base)) {
      return entity.path;
    }
  }

  return null;
}
