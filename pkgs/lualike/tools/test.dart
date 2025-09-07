import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as path;

/// List of Lua test files to run
final testFiles = [
  'attrib.lua',
  'bitwise.lua',
  'constructs.lua',
  'events.lua',
  'strings.lua',
  'literals.lua',
  'tpack.lua',
  'utf8.lua',
  'files.lua',
  'vararg.lua',
  'events.lua',
  'sort.lua',
  'math.lua',
  'heavy.lua',
];

/// Console instance for colored output
final console = Console();

/// Test result class to store information about each test run
class TestResult {
  final String fileName;
  final int exitCode;
  final Duration duration;
  final List<String> output;
  final List<String> errors;

  TestResult({
    required this.fileName,
    required this.exitCode,
    required this.duration,
    required this.output,
    required this.errors,
  });

  bool get passed => exitCode == 0;
}

/// Helper function to handle process output
Future<List<String>> collectProcessOutput(Stream<List<int>> stream) async {
  final output = <String>[];
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    output.add(line);
  }
  return output;
}

/// Smart compilation system that only recompiles when source files change
class SmartCompiler {
  final String projectRoot;
  final String cacheDir;
  final String binaryName;
  final List<String> sourceDirectories;

  SmartCompiler({
    required this.projectRoot,
    this.cacheDir = 'tools/build_cache',
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

/// Compile the lualike binary using smart compilation
Future<void> compile({bool force = false}) async {
  final compiler = SmartCompiler(projectRoot: '.');

  final success = await compiler.smartCompile(force: force);
  if (!success) {
    console.setForegroundColor(ConsoleColor.red);
    console.setTextStyle(bold: true);
    console.write("Compilation failed");
    console.resetColorAttributes();
    console.writeLine();
    exit(1);
  }
}

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    )
    ..addFlag(
      'skip-compile',
      abbr: 's',
      negatable: false,
      help: 'Skip compile if lualike binary exists',
    )
    ..addFlag(
      'force-compile',
      abbr: 'f',
      negatable: false,
      help: 'Force recompilation ignoring cache',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show verbose output for each test.',
    )
    ..addFlag(
      'soft',
      negatable: true,
      defaultsTo: true,
      help:
          'Enable soft mode (sets _soft = true). Enabled by default; use --no-soft to disable.',
    )
    ..addFlag(
      'port',
      negatable: true,
      defaultsTo: true,
      help:
          'Enable portability mode (sets _port = true). Enabled by default; use --no-port to disable.',
    )
    ..addMultiOption(
      'test',
      abbr: 't',
      help: 'Run specific test(s) by name (e.g., --test=bitwise.lua,math.lua)',
      splitCommas: true,
    )
    ..addMultiOption(
      'tests',
      help: 'Alias for --test; accepts comma-separated names',
      splitCommas: true,
    );

  ArgResults r;
  try {
    r = parser.parse(args);
  } on FormatException catch (e) {
    // Provide a friendlier error message for CLI parsing issues
    console.setForegroundColor(ConsoleColor.red);
    console.setTextStyle(bold: true);

    final msg = e.message;
    console.writeLine();
    console.write('Argument error');
    console.resetColorAttributes();
    console.writeLine();
    console.writeLine();

    console.writeLine("   $msg");
    console.writeLine();
    console.setForegroundColor(ConsoleColor.cyan);
    console.setTextStyle(bold: true);
    console.write('Usage');
    console.resetColorAttributes();
    console.writeLine();
    console.writeLine(parser.usage);
    exit(64); // EX_USAGE
  }

  if (r['help'] as bool) {
    console.setForegroundColor(ConsoleColor.cyan);
    console.setTextStyle(bold: true);
    console.write("Lualike Test Runner");
    console.resetColorAttributes();
    console.writeLine();
    console.writeLine(parser.usage);
    exit(0);
  }

  final binaryExists = File('lualike').existsSync();
  final shouldSkipCompile = (r['skip-compile'] as bool) && binaryExists;
  final forceCompile = r['force-compile'] as bool;

  if (!shouldSkipCompile) {
    await compile(force: forceCompile);
  } else {
    console.setForegroundColor(ConsoleColor.yellow);
    console.write("Skip-compile flag specified, using existing binary");
    console.resetColorAttributes();
    console.writeLine();
  }

  console.writeLine();
  console.setForegroundColor(ConsoleColor.cyan);
  console.setTextStyle(bold: true);
  console.write("Running tests...");
  console.resetColorAttributes();
  console.writeLine();

  final t1 = (r['test'] as List<String>?) ?? const <String>[];
  final t2 = (r['tests'] as List<String>?) ?? const <String>[];
  final combinedTests = <String>[...t1, ...t2];
  var testsToRun = combinedTests.isNotEmpty
      ? combinedTests
      : List<String>.from(testFiles);

  // Auto-skip known heavy tests on CI unless explicitly requested
  final isCI =
      (Platform.environment['CI']?.toLowerCase() == 'true') ||
      (Platform.environment['GITHUB_ACTIONS']?.toLowerCase() == 'true');
  const heavyTests = {'heavy.lua'};
  if (combinedTests.isEmpty && isCI) {
    final skipped = testsToRun.where((t) => heavyTests.contains(t)).toList();
    if (skipped.isNotEmpty) {
      testsToRun = testsToRun.where((t) => !heavyTests.contains(t)).toList();

      console.setForegroundColor(ConsoleColor.yellow);
      console.setTextStyle(bold: true);
      console.write('Auto-skip');
      console.resetColorAttributes();
      console.write(' on CI: ');
      console.setForegroundColor(ConsoleColor.yellow);
      console.write(skipped.join(', '));
      console.resetColorAttributes();
      console.writeLine();

      console.setForegroundColor(ConsoleColor.cyan);
      console.write('Tip: run explicitly with ');
      console.setTextStyle(bold: true);
      console.write("--test=${skipped.first}");
      console.resetColorAttributes();
      console.write(' to include it.');
      console.writeLine();
    }
  }

  final results = await runTests(
    tests: testsToRun,
    verbose: r['verbose'] as bool,
    soft: r['soft'] as bool, // default true  => _soft = true
    port: r['port'] as bool, // default true  => _port = true
  );

  printTestSummary(results);

  // Exit with non-zero code if any test failed
  if (results.any((result) => !result.passed)) {
    exit(1);
  }
}

/// Run the specified tests and return results
Future<List<TestResult>> runTests({
  List<String> tests = const [],
  bool verbose = false,
  bool soft = true,
  bool port = true,
}) async {
  final results = <TestResult>[];
  final testsToRun = tests.isEmpty ? testFiles : tests;

  for (final file in testsToRun) {
    console.setForegroundColor(ConsoleColor.cyan);
    console.write("Testing ");
    console.setTextStyle(bold: true);
    console.write(file);
    console.resetColorAttributes();
    console.writeLine();

    final stopwatch = Stopwatch()..start();

    // Build LUA_INIT to set flags in the Lua environment
    final initParts = <String>[];
    initParts.add(port ? '_port = true' : '_port = false');
    initParts.add(soft ? '_soft = true' : '_soft = false');
    final luaInit = initParts.join('; ');

    // Provide absolute path to compiled binary so child can resolve 'lualike'
    final lualikeBinary = 'lualike';
    final binaryPath = path.join(Directory.current.path, lualikeBinary);

    final environment = {
      'LUA_INIT': luaInit,
      'LUALIKE_BIN': binaryPath,
      ...Platform.environment,
    };
    final workingDir = path.join('luascripts', 'test');

    final process = await Process.start(
      binaryPath,
      [file],
      environment: environment,
      workingDirectory: workingDir,
    );

    // Collect stdout and stderr
    final stdoutFuture = collectProcessOutput(process.stdout);
    final stderrFuture = collectProcessOutput(process.stderr);

    // Wait for process to complete
    final exitCode = await process.exitCode;
    stopwatch.stop();

    // Get collected output
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;

    // Create test result
    final result = TestResult(
      fileName: file,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      output: stdout,
      errors: stderr,
    );

    results.add(result);

    // Print result status
    if (result.passed) {
      console.setForegroundColor(ConsoleColor.green);
      console.write("✓ Test passed in ${result.duration.inMilliseconds}ms");
      console.resetColorAttributes();
      console.writeLine();
    } else {
      console.setForegroundColor(ConsoleColor.red);
      console.write("✗ Test failed in ${result.duration.inMilliseconds}ms");
      console.resetColorAttributes();
      console.writeLine();
    }

    // Print verbose output if requested
    if (verbose) {
      if (result.output.isNotEmpty) {
        console.writeLine();
        console.setForegroundColor(ConsoleColor.white);
        console.write("Output:");
        console.resetColorAttributes();
        console.writeLine();
        for (final line in result.output) {
          console.writeLine("  $line");
        }
      }

      if (result.errors.isNotEmpty) {
        console.writeLine();
        console.setForegroundColor(ConsoleColor.red);
        console.write("Errors:");
        console.resetColorAttributes();
        console.writeLine();
        for (final line in result.errors) {
          console.writeLine("  $line");
        }
      }

      console.writeLine(); // Empty line for spacing
    }
  }

  return results;
}

/// Print a summary of all test results
void printTestSummary(List<TestResult> results) {
  final totalTests = results.length;
  final passedTests = results.where((r) => r.passed).length;
  final failedTests = totalTests - passedTests;

  final totalDuration = results.fold<Duration>(
    Duration.zero,
    (prev, result) => prev + result.duration,
  );

  console.writeLine();
  console.setTextStyle(bold: true);
  console.write("Test Summary:");
  console.resetColorAttributes();
  console.writeLine();

  console.setForegroundColor(ConsoleColor.cyan);
  console.writeLine("Total tests: $totalTests");
  console.resetColorAttributes();

  console.setForegroundColor(ConsoleColor.green);
  console.writeLine("Passed: $passedTests");
  console.resetColorAttributes();

  if (failedTests > 0) {
    console.setForegroundColor(ConsoleColor.red);
    console.writeLine("Failed: $failedTests");
    console.resetColorAttributes();

    // List failed tests
    console.writeLine();
    console.setForegroundColor(ConsoleColor.red);
    console.setTextStyle(bold: true);
    console.write("Failed tests:");
    console.resetColorAttributes();
    console.writeLine();

    for (final result in results.where((r) => !r.passed)) {
      console.setForegroundColor(ConsoleColor.red);
      console.writeLine("✗ ${result.fileName}");
      console.resetColorAttributes();
    }
  }

  console.writeLine();
  console.setForegroundColor(ConsoleColor.cyan);
  console.write("Total time: ${totalDuration.inMilliseconds}ms");
  console.resetColorAttributes();
  console.writeLine();
}
