import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as path;

import 'compiler.dart';
import 'utils.dart';

/// List of Lua test files to run
final testFiles = [
  'calls.lua',
  'attrib.lua',
  'goto.lua',
  'bitwise.lua',
  'constructs.lua',
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

/// Compile the lualike binary using smart compilation
Future<void> compile({bool force = false, String? dartPath}) async {
  final compiler = SmartCompiler(
    projectRoot: '.',
    dartPath: dartPath ?? getExecutableName('dart'),
  );

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

/// Get the absolute path to the Dart executable
String _getDartExecutablePath() {
  // Use Platform.script to get the Dart executable that's running this script
  return Platform.executable;
}

/// Compile the test runner itself into a standalone executable
Future<void> _compileTestRunner(String? dartPath) async {
  console.setForegroundColor(ConsoleColor.cyan);
  console.setTextStyle(bold: true);
  console.write("Compiling test runner...");
  console.resetColorAttributes();
  console.writeLine();

  final currentDir = Directory.current.path;
  final testRunnerPath = path.join(currentDir, 'tool', 'test.dart');
  final outputPath = path.join(currentDir, getExecutableName('test_runner'));

  try {
    // Remove existing executable if it exists
    final outputFile = File(outputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    // Get the absolute path to the dart executable
    final dartExecutablePath = dartPath ?? _getDartExecutablePath();

    console.setForegroundColor(ConsoleColor.blue);
    console.write("Using Dart executable: ");
    console.resetColorAttributes();
    console.writeLine(dartExecutablePath);

    // Compile the test runner with define to inject the dart path
    final result = await Process.run(dartExecutablePath, [
      'compile',
      'exe',
      '-DDART_EXECUTABLE_PATH=$dartExecutablePath',
      '--output',
      outputPath,
      testRunnerPath,
    ]);

    if (result.exitCode == 0) {
      console.setForegroundColor(ConsoleColor.green);
      console.write("✓ Test runner compiled successfully: ");
      console.resetColorAttributes();
      console.writeLine(outputPath);

      // Make it executable on Unix systems
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', outputPath]);
      }
    } else {
      console.setForegroundColor(ConsoleColor.red);
      console.write("✗ Failed to compile test runner");
      console.resetColorAttributes();
      console.writeLine();
      console.writeLine("Error output:");
      console.writeLine(result.stderr);
      exit(1);
    }
  } catch (e) {
    console.setForegroundColor(ConsoleColor.red);
    console.write("✗ Error compiling test runner: $e");
    console.resetColorAttributes();
    console.writeLine();
    exit(1);
  }
}

Future<void> main(List<String> args) async {
  // Get the injected Dart executable path from compilation
  const injectedDartPath = String.fromEnvironment('DART_EXECUTABLE_PATH');
  final defaultDartPath = injectedDartPath.isNotEmpty
      ? injectedDartPath
      : _getDartExecutablePath();

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
    ..addFlag(
      'skip-heavy',
      negatable: true,
      defaultsTo: true,
      help:
          'Skip heavy tests (sets _skip_heavy = true). Enabled by default; use --no-skip-heavy to include heavy tests.',
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
    )
    ..addFlag(
      'compile-runner',
      negatable: false,
      help: 'Compile the test runner itself into a standalone executable',
    )
    ..addOption(
      'dart-path',
      help: 'Path to the Dart executable (defaults to "dart" in PATH)',
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

  final dartPath = r['dart-path'] as String? ?? defaultDartPath;

  // Handle compile-runner flag
  if (r['compile-runner'] as bool) {
    await _compileTestRunner(dartPath);
    exit(0);
  }

  final binaryExists = File(getExecutableName('lualike')).existsSync();
  final shouldSkipCompile = (r['skip-compile'] as bool) && binaryExists;
  final forceCompile = r['force-compile'] as bool;

  if (!shouldSkipCompile) {
    await compile(force: forceCompile, dartPath: dartPath);
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

  // Auto-skip known heavy tests on CI or when skip-heavy flag is set
  final isCI =
      (Platform.environment['CI']?.toLowerCase() == 'true') ||
      (Platform.environment['GITHUB_ACTIONS']?.toLowerCase() == 'true');
  final skipHeavy = r['skip-heavy'] as bool;
  const heavyTests = {'heavy.lua'};

  if (combinedTests.isEmpty && (isCI || skipHeavy)) {
    final skipped = testsToRun.where((t) => heavyTests.contains(t)).toList();
    if (skipped.isNotEmpty) {
      testsToRun = testsToRun.where((t) => !heavyTests.contains(t)).toList();

      console.setForegroundColor(ConsoleColor.yellow);
      console.setTextStyle(bold: true);
      console.write('Auto-skip');
      console.resetColorAttributes();
      if (isCI) {
        console.write(' on CI');
      } else {
        console.write(' (--skip-heavy enabled)');
      }
      console.write(': ');
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
    final lualikeBinary = getExecutableName('lualike');
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
