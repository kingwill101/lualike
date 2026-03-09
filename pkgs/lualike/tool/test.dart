import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:dart_console/dart_console.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'compiler.dart';
import 'utils.dart';

/// List of Lua test files to run
final testFiles = [
  'attrib.lua',
  'goto.lua',
  'bitwise.lua',
  'strings.lua',
  'literals.lua',
  'tpack.lua',
  'utf8.lua',
  'files.lua',
  'vararg.lua',
  'events.lua',
  'calls.lua',
  'gc.lua',
  'constructs.lua',
  'sort.lua',
  'math.lua',
  'nextvar.lua',
  'code.lua',
  'coroutine.lua',
  'pm.lua',
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
/// If streaming is enabled, output will be printed in real-time
Future<List<String>> collectProcessOutput(
  Stream<List<int>> stream, {
  bool streaming = false,
  ConsoleColor? color,
  String prefix = "  ", // Prefix for each line when streaming
}) async {
  final output = <String>[];
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    output.add(line);

    // If streaming is enabled, print the line immediately
    if (streaming) {
      if (color != null) {
        console.setForegroundColor(color);
      }
      console.write(prefix);
      console.writeLine(line);
      if (color != null) {
        console.resetColorAttributes();
      }
    }
  }
  return output;
}

/// Download and extract the Lua test suite
Future<void> downloadLuaTestSuite({
  String downloadUrl = 'https://www.lua.org/tests/lua-5.4.7-tests.tar.gz',
  String testSuitePath = '.lua-tests',
  bool force = false,
}) async {
  final url = Uri.parse(downloadUrl);
  final destinationPath = Directory(testSuitePath);

  if (destinationPath.existsSync() && !force) {
    console.setForegroundColor(ConsoleColor.yellow);
    console.write('Test suite already exists at ');
    console.setTextStyle(bold: true);
    console.write(destinationPath.path);
    console.resetColorAttributes();
    console.write(' (use --force to override)');
    console.writeLine();
    return;
  }

  if (force && destinationPath.existsSync()) {
    console.setForegroundColor(ConsoleColor.yellow);
    console.write('Removing existing test suite at ');
    console.setTextStyle(bold: true);
    console.write(destinationPath.path);
    console.resetColorAttributes();
    console.writeLine();
    destinationPath.deleteSync(recursive: true);
  }

  console.setForegroundColor(ConsoleColor.cyan);
  console.write('Downloading test suite from ');
  console.setTextStyle(bold: true);
  console.write(url.toString());
  console.resetColorAttributes();
  console.write(' to ');
  console.setTextStyle(bold: true);
  console.write(destinationPath.path);
  console.resetColorAttributes();
  console.writeLine();

  try {
    final request = http.Request('GET', url);
    final streamedResponse = await http.Client().send(request);
    if (streamedResponse.statusCode == 200) {
      final bytes = await streamedResponse.stream.toBytes();
      console.setForegroundColor(ConsoleColor.green);
      console.write('✓ Download complete. ');
      console.resetColorAttributes();
      console.write('Extracting...');
      console.writeLine();

      // Create the destination directory if it doesn't exist
      if (!destinationPath.existsSync()) {
        destinationPath.createSync(recursive: true);
      }

      // Extract the archive
      final archive = TarDecoder().decodeBytes(gzip.decode(bytes));
      for (final file in archive) {
        final filename = file.name;
        // Extract only files from the tests folder
        if (!filename.startsWith('lua-5.4.7-tests/')) {
          continue;
        }
        final relativePath = filename.replaceFirst('lua-5.4.7-tests/', '');
        if (file.isFile) {
          final filePath = path.join(destinationPath.path, relativePath);
          final outFile = File(filePath);
          final parent = Directory(path.dirname(filePath));
          if (!parent.existsSync()) {
            parent.createSync(recursive: true);
          }
          outFile.writeAsBytesSync(file.content as List<int>);
        } else {
          final dirPath = path.join(destinationPath.path, relativePath);
          final dir = Directory(dirPath);
          dir.createSync(recursive: true);
        }
      }

      console.setForegroundColor(ConsoleColor.green);
      console.write('✓ Extraction complete.');
      console.resetColorAttributes();
      console.writeLine();
    } else {
      console.setForegroundColor(ConsoleColor.red);
      console.write('✗ Error downloading test suite. Status code: ');
      console.write(streamedResponse.statusCode.toString());
      console.resetColorAttributes();
      console.writeLine();
      exit(1);
    }
  } catch (e, stackTrace) {
    console.setForegroundColor(ConsoleColor.red);
    console.write('✗ Error downloading or extracting test suite: ');
    console.write(e.toString());
    console.resetColorAttributes();
    console.writeLine();
    console.writeLine('Stack trace: $stackTrace');
    exit(1);
  }
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
  final executable = Platform.executable;
  if (path.basename(executable).startsWith('test_runner')) {
    return getExecutableName('dart');
  }
  return executable;
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
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Force operations (compile, download) ignoring existing files',
    )
    ..addFlag(
      'download-suite',
      abbr: 'd',
      negatable: false,
      help: 'Download the Lua test suite',
    )
    ..addOption(
      'suite-url',
      help: 'URL to download the Lua test suite from',
      defaultsTo: 'https://www.lua.org/tests/lua-5.4.7-tests.tar.gz',
    )
    ..addOption(
      'suite-path',
      help: 'Path where the test suite will be stored',
      defaultsTo: '.lua-tests',
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
    ..addOption(
      'exec',
      abbr: 'e',
      help: 'Execute inline Lua code (bypasses test list).',
    )
    ..addFlag(
      'compile-runner',
      negatable: false,
      help: 'Compile the test runner itself into a standalone executable',
    )
    ..addOption(
      'dart-path',
      help: 'Path to the Dart executable (defaults to "dart" in PATH)',
    )
    ..addFlag(
      'debug',
      negatable: false,
      help: 'Pass --debug flag to the lualike binary when running tests.',
    )
    ..addFlag(
      'ir',
      negatable: false,
      help: 'Run tests using the IR engine (passes --ir).',
    )
    ..addFlag(
      'lua-bytecode',
      negatable: false,
      help: 'Run tests using the lua_bytecode engine (passes --lua-bytecode).',
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

  var dartPath = r['dart-path'] as String? ?? defaultDartPath;
  if (path.basename(dartPath).startsWith('test_runner')) {
    dartPath = _getDartExecutablePath();
  }
  final force = r['force'] as bool;
  // Handle download-suite flag
  if (r['download-suite'] as bool) {
    await downloadLuaTestSuite(
      downloadUrl: r['suite-url'] as String,
      testSuitePath: r['suite-path'] as String,
      force: force,
    );
    exit(0);
  }

  // Handle compile-runner flag
  if (r['compile-runner'] as bool) {
    await _compileTestRunner(dartPath);
    exit(0);
  }

  final binaryExists = File(getExecutableName('lualike')).existsSync();
  final shouldSkipCompile = (r['skip-compile'] as bool) && binaryExists;

  if (!shouldSkipCompile) {
    await compile(force: force, dartPath: dartPath);
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

  final execCode = r['exec'] as String?;

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

  if (execCode == null && combinedTests.isEmpty && (isCI || skipHeavy)) {
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

  bool verboseEnabled = r['verbose'] as bool;
  final debugEnabled = r['debug'] as bool;

  // If --debug flag is set, --verbose must also be enabled.
  if (debugEnabled && !verboseEnabled) {
    verboseEnabled = true;
    console.setForegroundColor(ConsoleColor.yellow);
    console.writeLine(
      "Note: --debug implies --verbose. Live output streaming enabled.",
    );
    console.resetColorAttributes();
  }

  final results = await runTests(
    tests: execCode == null ? testsToRun : const <String>[],
    inlineCode: execCode,
    verbose: verboseEnabled,
    soft: r['soft'] as bool, // default true  => _soft = true
    port: r['port'] as bool, // default true  => _port = true
    debug: debugEnabled, // new debug flag
    ir: r['ir'] as bool,
    luaBytecode: r['lua-bytecode'] as bool,
  );

  printTestSummary(results);

  // Exit with non-zero code if any test failed
  if (results.any((result) => !result.passed)) {
    exit(1);
  }
}

/// Resolve a test entry to an absolute file path.
/// Supports:
/// - Known suite files (from [testFiles]) located under `luascripts/test/`
/// - Arbitrary file paths (relative or absolute) anywhere in the repo
String _resolveTestPath(String entry) {
  // If entry is a known suite file, look under default scripts dir
  if (testFiles.contains(entry)) {
    final p = path.normalize(path.join('luascripts', 'test', entry));
    if (File(p).existsSync()) return path.normalize(path.absolute(p));
  }

  // Otherwise, treat entry as a path. Try as-is (relative to CWD)
  if (File(entry).existsSync()) return path.normalize(path.absolute(entry));

  // Try relative to default scripts dir
  final underDefault = path.normalize(path.join('luascripts', 'test', entry));
  if (File(underDefault).existsSync()) {
    return path.normalize(path.absolute(underDefault));
  }

  // Try under pkg path (common when calling from repo root)
  final underPkg = path.normalize(
    path.join('pkgs', 'lualike', 'luascripts', 'test', entry),
  );
  if (File(underPkg).existsSync()) {
    return path.normalize(path.absolute(underPkg));
  }

  throw ArgumentError('Test not found: $entry');
}

/// Run the specified tests and return results.
/// If a provided item in `tests` is not a known test name, it will be
/// validated as a file path and executed directly.
Future<List<TestResult>> runTests({
  List<String> tests = const [],
  String? inlineCode,
  bool verbose = false,
  bool soft = true,
  bool port = true,
  bool debug = false, // new debug parameter
  bool ir = false,
  bool luaBytecode = false,
}) async {
  final results = <TestResult>[];
  final testsToRun = inlineCode == null
      ? (tests.isEmpty ? testFiles : tests)
      : const <String>['<inline>'];

  for (final file in testsToRun) {
    console.setForegroundColor(ConsoleColor.cyan);
    console.write("Testing ");
    console.setTextStyle(bold: true);
    console.write(file);
    console.resetColorAttributes();
    console.writeLine();
    console.write('  Start time: ');
    console.writeLine(DateTime.now().toIso8601String());

    final stopwatch = Stopwatch()..start();

    // Build init code to set flags in the Lua environment
    final initParts = <String>[];
    initParts.add(port ? '_port = true' : '_port = false');
    initParts.add(soft ? '_soft = true' : '_soft = false');
    initParts.add("package.path = 'luascripts/test/?.lua;' .. package.path");
    final initCode = initParts.join('; ');

    // Resolve lualike binary and target test path
    final lualikeBinary = getExecutableName('lualike');
    final binaryPath = path.join(Directory.current.path, lualikeBinary);
    String? targetPath;
    if (inlineCode == null) {
      try {
        targetPath = _resolveTestPath(file);
      } catch (e) {
        console.setForegroundColor(ConsoleColor.red);
        console.write('✗ ');
        console.setTextStyle(bold: true);
        console.write('Test not found');
        console.resetColorAttributes();
        console.write(': ');
        console.writeLine(file);
        // Fail fast for missing files
        results.add(
          TestResult(
            fileName: file,
            exitCode: 1,
            duration: Duration.zero,
            output: const [],
            errors: ['Test not found: $file'],
          ),
        );
        continue;
      }
    }

    final environment = {'LUALIKE_BIN': binaryPath, ...Platform.environment};
    // Always run from repo root and pass absolute path to the script. This
    // avoids duplicating the working directory prefix when tests are given
    // as relative paths under luascripts/test/.
    final workingDir = Directory.current.path;

    final processArgs = <String>[];
    if (debug) {
      processArgs.add('--debug');
    }
    if (ir) {
      processArgs.add('--ir');
    }
    if (luaBytecode) {
      processArgs.add('--lua-bytecode');
    }
    final initSnippet = inlineCode == null
        ? "$initCode; dofile('$targetPath')"
        : initCode;
    processArgs.add('-e');
    processArgs.add(initSnippet);
    if (inlineCode != null) {
      processArgs.add('-e');
      processArgs.add(inlineCode);
    }

    final process = await Process.start(
      binaryPath,
      processArgs, // Pass built arguments
      environment: environment,
      workingDirectory: workingDir,
    );

    // Set up streaming for verbose mode
    final streamOutput = verbose;

    // Print header for streamed output if verbose is enabled
    if (streamOutput) {
      console.writeLine();
      console.setForegroundColor(ConsoleColor.cyan);
      console.setTextStyle(bold: true);
      console.write("Live output:");
      console.resetColorAttributes();
      console.writeLine();
    }

    // Collect stdout and stderr
    final stdoutFuture = collectProcessOutput(
      process.stdout,
      streaming: streamOutput,
      color: ConsoleColor.white,
    );
    final stderrFuture = collectProcessOutput(
      process.stderr,
      streaming: streamOutput,
      color: ConsoleColor.red,
    );

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

    // Only print the collected output at the end if we weren't already streaming it
    if (verbose && !streamOutput) {
      if (result.output.isNotEmpty) {
        console.writeLine();
        console.setForegroundColor(ConsoleColor.white);
        console.write("Output:");
        console.resetColorAttributes();
        console.writeLine();
        for (final line in result.output) {
          console.writeLine(line);
        }
      }

      if (result.errors.isNotEmpty) {
        console.writeLine();
        console.setForegroundColor(ConsoleColor.red);
        console.write("Errors:");
        console.resetColorAttributes();
        console.writeLine();
        for (final line in result.errors) {
          console.writeLine(line);
        }
      }
    }

    // Add an empty line for spacing between tests
    if (verbose) {
      console.writeLine();
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
