import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_console/dart_console.dart';

/// List of Lua test files to run
final testFiles = [
  'attrib.lua',
  'bitwise.lua',
  'constructs.lua',
  'events.lua',
  'strings.lua',
  'tpack.lua',
  'utf8.lua',
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

/// Compile the lualike binary
Future<void> compile() async {
  console.setForegroundColor(ConsoleColor.cyan);
  console.write("Compiling lualike...");
  console.resetColorAttributes();
  console.writeLine();

  final stopwatch = Stopwatch()..start();

  final process = await Process.start('dart', [
    'compile',
    'exe',
    '--output',
    'lualike',
    'bin/main.dart',
  ]);

  // Handle process output
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => console.writeLine(line));

  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      console.setForegroundColor(ConsoleColor.red);
      console.writeLine(line);
      console.resetColorAttributes();
    },
  );

  final exitCode = await process.exitCode;
  stopwatch.stop();

  if (exitCode != 0) {
    console.setForegroundColor(ConsoleColor.red);
    console.setTextStyle(bold: true);
    console.write("Compilation failed");
    console.resetColorAttributes();
    console.writeLine();
    exit(exitCode);
  } else {
    console.setForegroundColor(ConsoleColor.green);
    console.write(
      "Compilation successful in ${stopwatch.elapsed.inMilliseconds}ms",
    );
    console.resetColorAttributes();
    console.writeLine();
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
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show verbose output for each test',
    )
    ..addFlag(
      'no-soft',
      negatable: false,
      help: 'Disable soft mode (_soft = true) for full test execution',
    )
    ..addMultiOption(
      'test',
      abbr: 't',
      help: 'Run specific test(s) by name (e.g., --test=bitwise.lua,math.lua)',
      splitCommas: true,
    );

  final r = parser.parse(args);

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

  if (!shouldSkipCompile) {
    await compile();
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

  final testsToRun = (r['test'] as List<String>).isNotEmpty
      ? (r['test'] as List<String>)
      : testFiles;

  final results = await runTests(
    tests: testsToRun,
    verbose: r['verbose'] as bool,
    noSoft: r['no-soft'] as bool,
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
  bool noSoft = false,
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

    final environment = noSoft ? null : {'LUA_INIT': '_soft = true'};
    final process = await Process.start(
      '${Directory.current.path}/lualike',
      [file],
      environment: environment,
      workingDirectory: 'luascripts/test',
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
