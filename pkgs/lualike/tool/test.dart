#!/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:artisanal/args.dart';
import 'package:artisanal/artisanal.dart' show Console;
import 'package:artisanal/style.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'compiler.dart';
import 'utils.dart';

/// List of Lua test files to run
final testFiles = [
  'api.lua',
  'attrib.lua',
  'goto.lua',
  'bitwise.lua',
  'bwcoercion.lua',
  'big.lua',
  'strings.lua',
  'literals.lua',
  'tpack.lua',
  'utf8.lua',
  'files.lua',
  'vararg.lua',
  'events.lua',
  'calls.lua',
  'gc.lua',
  'gengc.lua',
  'tracegc.lua',
  'constructs.lua',
  'sort.lua',
  'verybig.lua',
  'math.lua',
  'nextvar.lua',
  'code.lua',
  'coroutine.lua',
  'pm.lua',
  'locals.lua',
  'db.lua',
  'errors.lua',
  'cstack.lua',
  'closure.lua',
  'heavy.lua',
];

/// Console instance for colored output
Console console = Console();

/// Test result class to store information about each test run
class TestResult {
  final String fileName;
  final int exitCode;
  final Duration duration;
  final List<String> output;
  final List<String> errors;
  final bool timedOut;

  TestResult({
    required this.fileName,
    required this.exitCode,
    required this.duration,
    required this.output,
    required this.errors,
    this.timedOut = false,
  });

  bool get passed => exitCode == 0;
}

/// Helper function to handle process output
/// If streaming is enabled, output will be printed in real-time
Future<List<String>> collectProcessOutput(
  Stream<List<int>> stream, {
  bool streaming = false,
  Color? color,
  String prefix = "  ", // Prefix for each line when streaming
}) async {
  final output = <String>[];
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    output.add(line);

    // If streaming is enabled, print the line immediately
    if (streaming) {
      if (color != null) {
        final style = Style().foreground(color);
        console.write(style.render(prefix));
        console.writeln(style.render(line));
      } else {
        console.write(prefix);
        console.writeln(line);
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
    console.write(
      Style().foreground(Colors.yellow).render('Test suite already exists at '),
    );
    console.write(Style().bold().render(destinationPath.path));
    console.write(' (use --force to override)');
    console.writeln('');
    return;
  }

  if (force && destinationPath.existsSync()) {
    console.write(
      Style()
          .foreground(Colors.yellow)
          .render('Removing existing test suite at '),
    );
    console.write(Style().bold().render(destinationPath.path));
    console.writeln('');
    destinationPath.deleteSync(recursive: true);
  }

  console.write(
    Style().foreground(Colors.cyan).render('Downloading test suite from '),
  );
  console.write(Style().bold().render(url.toString()));
  console.write(' to ');
  console.write(Style().bold().render(destinationPath.path));
  console.writeln('');

  try {
    final request = http.Request('GET', url);
    final streamedResponse = await http.Client().send(request);
    if (streamedResponse.statusCode == 200) {
      final bytes = await streamedResponse.stream.toBytes();
      console.write(
        Style().foreground(Colors.green).render('✓ Download complete. '),
      );
      console.write('Extracting...');
      console.writeln('');

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

      console.write(
        Style().foreground(Colors.green).render('✓ Extraction complete.'),
      );
      console.writeln('');
    } else {
      console.write(
        Style()
            .foreground(Colors.red)
            .render('✗ Error downloading test suite. Status code: '),
      );
      console.write(streamedResponse.statusCode.toString());
      console.writeln('');
      exit(1);
    }
  } catch (e, stackTrace) {
    console.write(
      Style()
          .foreground(Colors.red)
          .render('✗ Error downloading or extracting test suite: '),
    );
    console.write(e.toString());
    console.writeln('');
    console.writeln('Stack trace: $stackTrace');
    exit(1);
  }
}

/// Compile the lualike binary using smart compilation
Future<SmartCompileResult> compile({
  bool force = false,
  String? dartPath,
  String? binaryPath,
  String cacheDir = '.build_cache',
}) async {
  final compiler = SmartCompiler(
    projectRoot: '.',
    dartPath: dartPath ?? getExecutableName('dart'),
    cacheDir: cacheDir,
    binaryName: binaryPath ?? 'lualike',
  );

  final result = await compiler.smartCompile(force: force);
  if (!result.success) {
    console.write(
      Style().foreground(Colors.red).bold().render("Compilation failed"),
    );
    console.writeln('');
    exit(1);
  }
  return result;
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
  console.write(
    Style().foreground(Colors.cyan).bold().render("Compiling test runner..."),
  );
  console.writeln('');

  final currentDir = Directory.current.path;
  final outputPath = path.join(currentDir, getExecutableName('test_runner'));
  final bundleOutput = path.join(
    currentDir,
    '.build_cache',
    'test_runner_native',
  );
  final bundledExecutable = path.join(
    bundleOutput,
    'bundle',
    'bin',
    getExecutableName('test_runner'),
  );

  try {
    // Remove existing executable if it exists
    final outputType = FileSystemEntity.typeSync(
      outputPath,
      followLinks: false,
    );
    if (outputType == FileSystemEntityType.link) {
      Link(outputPath).deleteSync();
    } else if (outputType != FileSystemEntityType.notFound) {
      File(outputPath).deleteSync();
    }

    // Get the absolute path to the dart executable
    final dartExecutablePath = dartPath ?? _getDartExecutablePath();

    console.write(
      Style().foreground(Colors.blue).render("Using Dart executable: "),
    );
    console.writeln(dartExecutablePath);

    // Build a complete CLI bundle so native assets remain next to the runner.
    final result = await Process.run(dartExecutablePath, [
      '-DDART_EXECUTABLE_PATH=$dartExecutablePath',
      'build',
      'cli',
      '--output',
      bundleOutput,
      '--target',
      path.join('bin', 'test_runner.dart'),
      '--verbosity',
      'warning',
    ]);

    if (result.exitCode == 0) {
      if (Platform.isWindows) {
        File(bundledExecutable).copySync(outputPath);
      } else {
        Link(outputPath).createSync(path.absolute(bundledExecutable));
      }
      console.write(
        Style()
            .foreground(Colors.green)
            .render("✓ Test runner compiled successfully: "),
      );
      console.writeln(outputPath);
    } else {
      console.write(
        Style()
            .foreground(Colors.red)
            .render("✗ Failed to compile test runner"),
      );
      console.writeln('');
      console.writeln("Error output:");
      console.writeln(result.stderr);
      exit(1);
    }
  } catch (e) {
    console.write(
      Style()
          .foreground(Colors.red)
          .render("✗ Error compiling test runner: $e"),
    );
    console.writeln('');
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
  required String lualikeBinaryPath,
  bool verbose = false,
  bool soft = true,
  bool port = true,
  bool debug = false, // new debug parameter
  bool ir = false,
  bool luaBytecode = false,
  int? timeoutSeconds,
}) async {
  final results = <TestResult>[];
  final testsToRun = inlineCode == null
      ? (tests.isEmpty ? testFiles : tests)
      : const <String>['<inline>'];

  for (final file in testsToRun) {
    console.write(Style().foreground(Colors.cyan).render("Testing "));
    console.write(Style().bold().render(file));
    console.writeln('');
    console.write('  Start time: ');
    console.writeln(DateTime.now().toIso8601String());

    final stopwatch = Stopwatch()..start();

    // Build init code to set flags in the Lua environment
    final initParts = <String>[];
    initParts.add(port ? '_port = true' : '_port = false');
    initParts.add(soft ? '_soft = true' : '_soft = false');
    initParts.add("package.path = 'luascripts/test/?.lua;' .. package.path");
    final initCode = initParts.join('; ');

    // Resolve lualike binary and target test path
    final binaryPath = lualikeBinaryPath;
    String? targetPath;
    if (inlineCode == null) {
      try {
        targetPath = _resolveTestPath(file);
      } catch (e) {
        console.write(Style().foreground(Colors.red).render('✗ '));
        console.write(Style().bold().render('Test not found'));
        console.write(': ');
        console.writeln(file);
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
      console.writeln('');
      console.write(
        Style().foreground(Colors.cyan).bold().render("Live output:"),
      );
      console.writeln('');
    }

    // Collect stdout and stderr
    final stdoutFuture = collectProcessOutput(
      process.stdout,
      streaming: streamOutput,
      color: Colors.white,
    );
    final stderrFuture = collectProcessOutput(
      process.stderr,
      streaming: streamOutput,
      color: Colors.red,
    );

    // Wait for process to complete
    var timedOut = false;
    final exitCode = timeoutSeconds == null
        ? await process.exitCode
        : await process.exitCode.timeout(
            Duration(seconds: timeoutSeconds),
            onTimeout: () async {
              timedOut = true;
              process.kill();
              await Future<void>.delayed(const Duration(milliseconds: 200));
              if (process.kill(ProcessSignal.sigkill)) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
              return 124;
            },
          );
    stopwatch.stop();

    // Get collected output
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (timedOut) {
      stderr.add('Timed out after ${timeoutSeconds}s');
    }

    // Create test result
    final result = TestResult(
      fileName: file,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      output: stdout,
      errors: stderr,
      timedOut: timedOut,
    );

    results.add(result);

    // Print result status
    if (result.passed) {
      console.writeln(
        Style()
            .foreground(Colors.green)
            .render("✓ Test passed in ${result.duration.inMilliseconds}ms"),
      );
    } else {
      if (result.timedOut) {
        console.writeln(
          Style()
              .foreground(Colors.red)
              .render(
                "✗ Test timed out in ${result.duration.inMilliseconds}ms",
              ),
        );
      } else {
        console.writeln(
          Style()
              .foreground(Colors.red)
              .render("✗ Test failed in ${result.duration.inMilliseconds}ms"),
        );
      }
    }

    // Only print the collected output at the end if we weren't already streaming it
    if (verbose && !streamOutput) {
      if (result.output.isNotEmpty) {
        console.writeln('');
        console.write(Style().foreground(Colors.white).render("Output:"));
        console.writeln('');
        for (final line in result.output) {
          console.writeln(line);
        }
      }

      if (result.errors.isNotEmpty) {
        console.writeln('');
        console.write(Style().foreground(Colors.red).render("Errors:"));
        console.writeln('');
        for (final line in result.errors) {
          console.writeln(line);
        }
      }
    }

    // Add an empty line for spacing between tests
    if (verbose) {
      console.writeln('');
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

  console.writeln('');
  console.write(Style().bold().render("Test Summary:"));
  console.writeln('');

  console.writeln(
    Style().foreground(Colors.cyan).render("Total tests: $totalTests"),
  );

  console.writeln(
    Style().foreground(Colors.green).render("Passed: $passedTests"),
  );

  if (failedTests > 0) {
    console.writeln(
      Style().foreground(Colors.red).render("Failed: $failedTests"),
    );

    // List failed tests
    console.writeln('');
    console.write(
      Style().foreground(Colors.red).bold().render("Failed tests:"),
    );
    console.writeln('');

    for (final result in results.where((r) => !r.passed)) {
      console.writeln(
        Style().foreground(Colors.red).render("✗ ${result.fileName}"),
      );
    }
  }

  console.writeln('');
  console.writeln(
    Style()
        .foreground(Colors.cyan)
        .render("Total time: ${totalDuration.inMilliseconds}ms"),
  );
}

class TestRunner extends CommandRunner {
  @override
  String get invocation => '$executableName [options]';

  TestRunner() : super("test_runner", "lualike test suite") {
    argParser
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
      ..addOption(
        'timeout-seconds',
        help:
            'Per-test timeout in seconds. Defaults to 45 when reusing an existing binary; set to 0 to disable.',
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
        help:
            'Run specific test(s) by name (e.g., --test=bitwise.lua,math.lua)',
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
      ..addOption(
        'lualike-bin',
        help:
            'Path to the lualike executable to compile/use instead of ./lualike',
      )
      ..addOption(
        'lualike-cache-dir',
        help: 'Directory to store compiled lualike binary cache metadata',
        defaultsTo: '.build_cache',
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
        help:
            'Run tests using the lua_bytecode engine (passes --lua-bytecode).',
      )
      ..addFlag(
        'all-engines',
        negatable: false,
        help:
            'Run all tests under every engine in sequence: AST (default), IR, and lua-bytecode. '
            'Supersedes --ir and --lua-bytecode when present.',
      );
  }

  @override
  Future<void> run(Iterable<String> args) async {
    // Link the global console to the runner's io
    console = io;

    // Get the injected Dart executable path from compilation
    const injectedDartPath = String.fromEnvironment('DART_EXECUTABLE_PATH');
    final defaultDartPath = injectedDartPath.isNotEmpty
        ? injectedDartPath
        : _getDartExecutablePath();

    final r = argParser.parse(args);

    if (r['help'] as bool) {
      printUsage();
      return;
    }

    var dartPath = r['dart-path'] as String? ?? defaultDartPath;
    if (path.basename(dartPath).startsWith('test_runner')) {
      dartPath = _getDartExecutablePath();
    }
    final configuredBinary = r['lualike-bin'] as String?;
    var lualikeBinaryPath = configuredBinary == null
        ? path.join(Directory.current.path, getExecutableName('lualike'))
        : path.normalize(
            path.isAbsolute(configuredBinary)
                ? configuredBinary
                : path.join(Directory.current.path, configuredBinary),
          );
    final lualikeCacheDir = r['lualike-cache-dir'] as String;
    final force = r['force'] as bool;
    // Handle download-suite flag
    if (r['download-suite'] as bool) {
      await downloadLuaTestSuite(
        downloadUrl: r['suite-url'] as String,
        testSuitePath: r['suite-path'] as String,
        force: force,
      );
      return;
    }

    // Handle compile-runner flag
    if (r['compile-runner'] as bool) {
      await _compileTestRunner(dartPath);
      return;
    }

    final binaryExists = File(lualikeBinaryPath).existsSync();
    final shouldSkipCompile = (r['skip-compile'] as bool) && binaryExists;

    final compileResult = shouldSkipCompile
        ? SmartCompileResult(
            success: true,
            recompiled: false,
            executablePath: lualikeBinaryPath,
          )
        : await compile(
            force: force,
            dartPath: dartPath,
            binaryPath: lualikeBinaryPath,
            cacheDir: lualikeCacheDir,
          );
    lualikeBinaryPath = compileResult.executablePath ?? lualikeBinaryPath;
    if (shouldSkipCompile) {
      console.writeln(
        Style()
            .foreground(Colors.yellow)
            .render("Skip-compile flag specified, using existing binary"),
      );
    }

    int? timeoutSeconds;
    final timeoutOption = r['timeout-seconds'] as String?;
    if (timeoutOption != null) {
      final parsedTimeout = int.tryParse(timeoutOption);
      if (parsedTimeout == null || parsedTimeout < 0) {
        console.writeln(
          Style()
              .foreground(Colors.red)
              .render('Invalid --timeout-seconds value: $timeoutOption'),
        );
        exit(64);
      }
      timeoutSeconds = parsedTimeout == 0 ? null : parsedTimeout;
    } else {
      timeoutSeconds = compileResult.recompiled ? null : 45;
    }

    if (timeoutSeconds != null) {
      final style = Style().foreground(Colors.yellow);
      console.write(
        style.render('Per-test timeout enabled: ${timeoutSeconds}s'),
      );
      if (!compileResult.recompiled) {
        console.write(style.render(' (reused binary)'));
      }
      console.writeln('');
    }

    console.writeln('');
    console.writeln(
      Style().foreground(Colors.cyan).bold().render("Running tests..."),
    );

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

        final yellowStyle = Style().foreground(Colors.yellow);
        console.write(yellowStyle.bold().render('Auto-skip'));
        if (isCI) {
          console.write(' on CI');
        } else {
          console.write(' (--skip-heavy enabled)');
        }
        console.write(': ');
        console.writeln(yellowStyle.render(skipped.join(', ')));

        final cyanStyle = Style().foreground(Colors.cyan);
        console.write(cyanStyle.render('Tip: run explicitly with '));
        console.write(cyanStyle.bold().render("--test=${skipped.first}"));
        console.writeln(' to include it.');
      }
    }

    bool verboseEnabled = r['verbose'] as bool;
    final debugEnabled = r['debug'] as bool;

    // If --debug flag is set, --verbose must also be enabled.
    if (debugEnabled && !verboseEnabled) {
      verboseEnabled = true;
      console.writeln(
        Style()
            .foreground(Colors.yellow)
            .render(
              "Note: --debug implies --verbose. Live output streaming enabled.",
            ),
      );
    }

    final allEngines = r['all-engines'] as bool;

    if (allEngines) {
      // Run the full suite under each engine in turn and print a combined report.
      final engines = <(String, bool, bool)>[
        ('AST (default)', false, false),
        ('IR', true, false),
        ('lua-bytecode', false, true),
      ];

      final engineResults = <String, List<TestResult>>{};
      var anyFailed = false;

      for (final (label, ir, luaBytecode) in engines) {
        console.writeln('');
        console.writeln(
          Style()
              .foreground(Colors.cyan)
              .bold()
              .render('═══ Engine: $label ═══'),
        );

        final results = await runTests(
          tests: execCode == null ? testsToRun : const <String>[],
          inlineCode: execCode,
          lualikeBinaryPath: lualikeBinaryPath,
          verbose: verboseEnabled,
          soft: r['soft'] as bool,
          port: r['port'] as bool,
          debug: debugEnabled,
          ir: ir,
          luaBytecode: luaBytecode,
          timeoutSeconds: timeoutSeconds,
        );

        engineResults[label] = results;
        printTestSummary(results);

        if (results.any((result) => !result.passed)) {
          anyFailed = true;
        }
      }

      // Cross-engine summary table
      console.writeln('');
      console.writeln(Style().bold().render('Cross-engine Summary:'));

      for (final entry in engineResults.entries) {
        final passed = entry.value.where((r) => r.passed).length;
        final total = entry.value.length;
        final allPassed = passed == total;
        final style = Style().foreground(allPassed ? Colors.green : Colors.red);

        console.write(style.render('  ${entry.key}: $passed/$total passed'));
        if (!allPassed) {
          final failed = entry.value
              .where((r) => !r.passed)
              .map((r) => r.fileName);
          console.write(style.render('  [FAILED: ${failed.join(', ')}]'));
        }
        console.writeln('');
      }

      if (anyFailed) {
        exit(1);
      }
    } else {
      final results = await runTests(
        tests: execCode == null ? testsToRun : const <String>[],
        inlineCode: execCode,
        lualikeBinaryPath: lualikeBinaryPath,
        verbose: verboseEnabled,
        soft: r['soft'] as bool,
        // default true  => _soft = true
        port: r['port'] as bool,
        // default true  => _port = true
        debug: debugEnabled,
        ir: r['ir'] as bool,
        luaBytecode: r['lua-bytecode'] as bool,
        timeoutSeconds: timeoutSeconds,
      );

      printTestSummary(results);

      // Exit with non-zero code if any test failed
      if (results.any((result) => !result.passed)) {
        exit(1);
      }
    }
  }
}

Future<void> main(List<String> args) async {
  await TestRunner().run(args);
}
