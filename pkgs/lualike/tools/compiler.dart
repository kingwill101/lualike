import 'dart:convert' show utf8, LineSplitter;
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as path;

import 'test.dart' show console;

/// Smart compilation system that only recompiles when source files change
class SmartCompiler {
  final String projectRoot;
  final String cacheDir;
  final String binaryName;
  final List<String> sourceDirectories;

  SmartCompiler({
    required this.projectRoot,
    this.cacheDir = '.build_cache',
    this.binaryName = 'lualike',
    this.sourceDirectories = const ['bin', 'lib'],
  });

  String get _hashFilePath => path.join(cacheDir, 'source_hash.txt');

  String get _binaryPath => path.join(projectRoot, binaryName);

  String get _compileTimeFilePath => path.join(cacheDir, 'compile_time.txt');

  /// Calculate hash of all source files in the specified directories
  Future<(String, Map<String, dynamic>)> _calculateSourceHash() async {
    final hasher = sha256;
    final files = <File>[];
    var totalFiles = 0;
    var totalSize = 0;
    var skippedFiles = 0;
    final dirStats = <String, int>{};

    // Collect all Dart files from source directories
    for (final dirName in sourceDirectories) {
      final dir = Directory(path.join(projectRoot, dirName));
      var dirFileCount = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            files.add(entity);
            totalFiles++;
            dirFileCount++;
          }
        }
      }
      dirStats[dirName] = dirFileCount;
    }

    // Sort files by path for consistent hashing
    files.sort((a, b) => a.path.compareTo(b.path));

    // Hash file contents and metadata
    final bytes = <int>[];

    for (final file in files) {
      try {
        final content = await file.readAsBytes();
        final stat = await file.stat();
        totalSize += content.length;

        // Include file path, content, and modification time in hash
        bytes.addAll(utf8.encode(file.path));
        bytes.addAll(content);
        bytes.addAll(
          utf8.encode(stat.modified.millisecondsSinceEpoch.toString()),
        );
      } catch (e) {
        // Skip files that can't be read
        skippedFiles++;
        continue;
      }
    }

    final digest = hasher.convert(bytes);
    final stats = {
      'total_files': totalFiles,
      'total_size_bytes': totalSize,
      'total_size_kb': (totalSize / 1024).round(),
      'skipped_files': skippedFiles,
      'hash_data_size': bytes.length,
      'dir_breakdown': dirStats,
    };

    return (digest.toString(), stats);
  }

  /// Read the cached hash from previous compilation
  Future<String?> _readCachedHash() async {
    try {
      final file = File(_hashFilePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      // Ignore errors reading cache
    }
    return null;
  }

  /// Save the current hash to cache
  Future<void> _saveCachedHash(String hash) async {
    try {
      final file = File(_hashFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(hash);
    } catch (e) {
      // Ignore errors writing cache
    }
  }

  /// Read the cached compilation time
  Future<Duration?> _readCachedCompileTime() async {
    try {
      final file = File(_compileTimeFilePath);
      if (await file.exists()) {
        final timeMs = int.parse(await file.readAsString());
        return Duration(milliseconds: timeMs);
      }
    } catch (e) {
      // Ignore errors reading cache
    }
    return null;
  }

  /// Save the compilation time to cache
  Future<void> _saveCachedCompileTime(Duration time) async {
    try {
      final file = File(_compileTimeFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(time.inMilliseconds.toString());
    } catch (e) {
      // Ignore errors writing cache
    }
  }

  /// Check if binary exists and is newer than source files
  Future<bool> _isBinaryUpToDate() async {
    final binary = File(_binaryPath);
    if (!await binary.exists()) {
      return false;
    }

    try {
      final binaryStat = await binary.stat();

      // Check if any source file is newer than the binary
      for (final dirName in sourceDirectories) {
        final dir = Directory(path.join(projectRoot, dirName));
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File && entity.path.endsWith('.dart')) {
              final fileStat = await entity.stat();
              if (fileStat.modified.isAfter(binaryStat.modified)) {
                return false;
              }
            }
          }
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Perform the actual compilation
  Future<bool> _compile() async {
    console.setForegroundColor(ConsoleColor.cyan);
    console.write('Compiling $binaryName...');
    console.resetColorAttributes();
    console.writeLine();

    final stopwatch = Stopwatch()..start();

    final process = await Process.start('dart', [
      'compile',
      'exe',
      '--output',
      binaryName,
      path.join('bin', 'main.dart'),
    ], workingDirectory: projectRoot);

    // Stream output in real-time
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => console.writeLine('  $line'));

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          console.setForegroundColor(ConsoleColor.red);
          console.writeLine('  ERROR: $line');
          console.resetColorAttributes();
        });

    final exitCode = await process.exitCode;
    stopwatch.stop();

    if (exitCode == 0) {
      console.setForegroundColor(ConsoleColor.green);
      console.write(
        '✓ Compilation successful in ${stopwatch.elapsed.inMilliseconds}ms',
      );
      console.resetColorAttributes();
      console.writeLine();
      return true;
    } else {
      console.setForegroundColor(ConsoleColor.red);
      console.write('✗ Compilation failed');
      console.resetColorAttributes();
      console.writeLine();
      return false;
    }
  }

  /// Smart compile: only recompile if source files have changed
  Future<bool> smartCompile({bool force = false}) async {
    if (force) {
      console.setForegroundColor(ConsoleColor.yellow);
      console.write('Force compilation requested');
      console.resetColorAttributes();
      console.writeLine();
      final compileStopwatch = Stopwatch()..start();
      final success = await _compile();
      compileStopwatch.stop();
      if (success) {
        final (hash, stats) = await _calculateSourceHash();
        await _saveCachedHash(hash);
        await _saveCachedCompileTime(compileStopwatch.elapsed);
        _logStats(stats, compileTime: compileStopwatch.elapsed);
      }
      return success;
    }

    console.setForegroundColor(ConsoleColor.cyan);
    console.write('Checking if recompilation is needed...');
    console.resetColorAttributes();
    console.writeLine();

    final stopwatch = Stopwatch()..start();

    // Calculate current source hash
    final (currentHash, stats) = await _calculateSourceHash();
    final cachedHash = await _readCachedHash();
    final cachedCompileTime = await _readCachedCompileTime();

    stopwatch.stop();

    // Determine cache status
    final cacheStatus = cachedHash == null
        ? 'no-cache'
        : (currentHash == cachedHash ? 'hit' : 'miss');

    // Log detailed stats
    _logStats(
      stats,
      hashTime: stopwatch.elapsed,
      cacheStatus: cacheStatus,
      lastCompileTime: cachedCompileTime,
    );

    // Check if hashes match
    if (currentHash == cachedHash) {
      // Additional check: ensure binary exists and is up to date
      if (await _isBinaryUpToDate()) {
        console.setForegroundColor(ConsoleColor.green);
        console.write('✓ Source files unchanged, using existing binary');
        if (cachedCompileTime != null) {
          console.write(' (saved ${cachedCompileTime.inSeconds}s)');
        }
        console.resetColorAttributes();
        console.writeLine();
        return true;
      } else {
        console.setForegroundColor(ConsoleColor.yellow);
        console.write('Binary missing or outdated, recompiling...');
        console.resetColorAttributes();
        console.writeLine();
      }
    } else {
      console.setForegroundColor(ConsoleColor.yellow);
      console.write('Source files changed, recompiling...');
      console.resetColorAttributes();
      console.writeLine();
    }

    // Recompile
    final compileStopwatch = Stopwatch()..start();
    final success = await _compile();
    compileStopwatch.stop();
    if (success) {
      await _saveCachedHash(currentHash);
      await _saveCachedCompileTime(compileStopwatch.elapsed);
    }

    return success;
  }

  /// Log compilation statistics
  void _logStats(
    Map<String, dynamic> stats, {
    Duration? hashTime,
    String? cacheStatus,
    Duration? compileTime,
    Duration? lastCompileTime,
  }) {
    console.setForegroundColor(ConsoleColor.cyan);
    console.write('📊 Stats: ');
    console.resetColorAttributes();

    // Main stats
    console.write('${stats['total_files']} files, ${stats['total_size_kb']}KB');

    // Directory breakdown
    final dirBreakdown = stats['dir_breakdown'] as Map<String, int>;
    final dirInfo = dirBreakdown.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
    console.write(' [$dirInfo]');

    if (stats['skipped_files'] > 0) {
      console.setForegroundColor(ConsoleColor.yellow);
      console.write(' (${stats['skipped_files']} skipped)');
      console.resetColorAttributes();
    }

    if (hashTime != null) {
      console.write(', hash: ${hashTime.inMilliseconds}ms');
    }

    if (cacheStatus != null) {
      console.write(', cache: ');
      switch (cacheStatus) {
        case 'hit':
          console.setForegroundColor(ConsoleColor.green);
          console.write('HIT');
          break;
        case 'miss':
          console.setForegroundColor(ConsoleColor.yellow);
          console.write('MISS');
          break;
        case 'no-cache':
          console.setForegroundColor(ConsoleColor.red);
          console.write('NONE');
          break;
      }
      console.resetColorAttributes();
    }

    if (compileTime != null) {
      console.write(', compile: ${compileTime.inSeconds}s');
    }

    console.writeLine();
  }
}
