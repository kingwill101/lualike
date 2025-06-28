import 'dart:convert';
import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/integration/const.dart';
import 'package:lualike/src/integration/result.dart';
import 'package:lualike/src/stdlib/lib_test.dart';
import 'package:path/path.dart' as p;

class TestRunner {
  final String testSuitePath;
  final ExecutionMode mode;
  final bool useInternalTests;
  final String logDirPath;
  final bool verbose;
  final bool parallel;
  final int parallelJobs;
  final String? filterPattern;
  final List<String> categories;
  final Map<String, TestResult> results = {};
  late ProgressBar progressBar;
  final List<String> skipList;

  TestRunner({
    required this.testSuitePath,
    required this.mode,
    this.useInternalTests = false,
    this.logDirPath = 'test-logs',
    this.verbose = false,
    this.parallel = false,
    this.parallelJobs = 4,
    this.filterPattern,
    this.categories = const [],
    this.skipList = const [],
  });

  Future<void> runTestSuite() async {
    try {
      print('Running LuaLike test suite in $mode mode...');
      print("Files in test suite: $testSuitePath");
      final testDir = Directory(testSuitePath);
      if (!testDir.existsSync()) {
        print('Error: Test suite directory not found: $testSuitePath');
        exit(1);
      }

      // Create logs directory
      final logDir = Directory(logDirPath);
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }

      print("Finding test files in $testSuitePath");
      final allTestFiles = await _getTestFiles(testDir);

      // Filter test files based on categories and pattern
      final testFiles = _filterTestFiles(allTestFiles);

      if (testFiles.isEmpty) {
        print('No test files found matching the specified criteria.');
        exit(0);
      }

      print('Found ${testFiles.length} test files to run.');
      progressBar = ProgressBar(total: testFiles.length);

      final suiteStartTime = DateTime.now();
      int passedCount = 0;
      int failedCount = 0;
      int skippedCount = 0;

      if (parallel) {
        print('Running tests in parallel with $parallelJobs jobs...');
        final chunks = _chunkList(testFiles, parallelJobs);
        final futures = chunks.map((chunk) => _runTestChunk(chunk, testDir));

        final results = await Future.wait(futures);

        for (final result in results) {
          passedCount += result['passed'] as int;
          failedCount += result['failed'] as int;
          skippedCount += result['skipped'] as int;
        }
      } else {
        for (final testFile in testFiles) {
          final relativePath = testFile.path.replaceFirst(
            testDir.path + Platform.pathSeparator,
            '',
          );

          // Check if test should be skipped
          if (skipList.contains(relativePath)) {
            if (verbose) {
              print('\n--- Skipping test: $relativePath (in skip list) ---');
            }
            skippedCount++;
            await progressBar.increment();

            results[relativePath] = TestResult(
              name: relativePath,
              passed: true,
              skipped: true,
              duration: Duration.zero,
              category: _getCategoryForTest(relativePath),
            );
            continue;
          }

          if (verbose) {
            print('\n--- Running test: $relativePath ---');
            Logger.setEnabled(true);
          }

          final testStartTime = DateTime.now();
          final logBuffer = StringBuffer();
          logBuffer.writeln('=== Test: $relativePath ===');
          logBuffer.writeln('Start time: $testStartTime');
          logBuffer.writeln('Mode: $mode');
          logBuffer.writeln(
            'Category: ${_getCategoryForTest(relativePath) ?? "uncategorized"}',
          );

          try {
            final sourceCode = await testFile.readAsString();
            logBuffer.writeln('\n--- Source Code ---');
            logBuffer.writeln(sourceCode);
            logBuffer.writeln('\n--- Execution ---');

            final _ = await executeCode(sourceCode, mode, onInterpreterSetup: (interpreter) {
              if (useInternalTests) {
                _injectInternalTestFunctions(interpreter.globals);
              }
            });

            final testEndTime = DateTime.now();
            final testDuration = testEndTime.difference(testStartTime);

            logBuffer.writeln('\n--- Result ---');
            logBuffer.writeln('Status: PASSED');
            logBuffer.writeln('Duration: ${testDuration.inMilliseconds} ms');

            if (verbose) {
              print(
                'Test passed: $relativePath (${testDuration.inMilliseconds} ms)',
              );
            }
            passedCount++;

            results[relativePath] = TestResult(
              name: relativePath,
              passed: true,
              duration: testDuration,
              category: _getCategoryForTest(relativePath),
            );
          } catch (e, stackTrace) {
            final testEndTime = DateTime.now();
            final testDuration = testEndTime.difference(testStartTime);

            logBuffer.writeln('\n--- Result ---');
            logBuffer.writeln('Status: FAILED');
            logBuffer.writeln('Error: $e');
            logBuffer.writeln('Stack trace:');
            logBuffer.writeln(stackTrace);
            logBuffer.writeln('Duration: ${testDuration.inMilliseconds} ms');

            if (verbose) {
              print('Test failed: $relativePath');
              print('Error: $e');
            }
            failedCount++;

            results[relativePath] = TestResult(
              name: relativePath,
              passed: false,
              errorMessage: e.toString(),
              duration: testDuration,
              category: _getCategoryForTest(relativePath),
            );
          }

          // Write test log
          final sanitizedName = relativePath.replaceAll(RegExp(r'[\/\\]'), '_');
          final logFile = File('$logDirPath/$sanitizedName.log');
          logFile.writeAsStringSync(logBuffer.toString());

          progressBar.increment();
        }
      }

      final suiteEndTime = DateTime.now();
      final suiteDuration = suiteEndTime.difference(suiteStartTime);

      // Create summary report
      final reportBuffer = StringBuffer();
      reportBuffer.writeln('=== LuaLike Test Suite Summary ===');
      reportBuffer.writeln('Date: $suiteStartTime');
      reportBuffer.writeln('Mode: $mode');
      reportBuffer.writeln('Total tests: ${testFiles.length}');
      reportBuffer.writeln('Passed: $passedCount');
      reportBuffer.writeln('Failed: $failedCount');
      reportBuffer.writeln('Skipped: $skippedCount');
      reportBuffer.writeln('Duration: ${suiteDuration.inSeconds} seconds');

      // Add category statistics
      reportBuffer.writeln('\n=== Category Statistics ===');
      final categoryStats = _getCategoryStatistics();
      for (final entry in categoryStats.entries) {
        final category = entry.key;
        final stats = entry.value;
        reportBuffer.writeln(
          '$category: ${stats['total']} tests, ${stats['passed']} passed, ${stats['failed']} failed, ${stats['skipped']} skipped',
        );
      }

      reportBuffer.writeln('\n=== Detailed Results ===');

      for (final entry
          in results.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
        final result = entry.value;
        if (result.skipped) {
          reportBuffer.writeln('${result.name}: SKIPPED');
        } else {
          reportBuffer.writeln(
            '${result.name}: ${result.passed ? "PASSED" : "FAILED"} (${result.duration.inMilliseconds} ms)',
          );
          if (!result.passed) {
            reportBuffer.writeln('  Error: ${result.errorMessage}');
          }
        }
      }

      // Write summary report
      final reportFile = File('$logDirPath/summary_report.txt');
      reportFile.writeAsStringSync(reportBuffer.toString());

      // Write JSON report for programmatic consumption
      final jsonReport = {
        'timestamp': suiteStartTime.toIso8601String(),
        'mode': mode.toString(),
        'totalTests': testFiles.length,
        'passed': passedCount,
        'failed': failedCount,
        'skipped': skippedCount,
        'durationMs': suiteDuration.inMilliseconds,
        'categoryStats': categoryStats,
        'results': results.values.map((r) => r.toJson()).toList(),
      };

      final jsonReportFile = File('$logDirPath/report.json');
      jsonReportFile.writeAsStringSync(jsonEncode(jsonReport));

      print('\n--- Test Results ---');
      print('Total tests: ${testFiles.length}');
      print('Passed: $passedCount');
      print('Failed: $failedCount');
      print('Skipped: $skippedCount');
      print('Duration: ${suiteDuration.inSeconds} seconds');

      // Print category statistics
      print('\n--- Category Statistics ---');
      for (final entry in categoryStats.entries) {
        final category = entry.key;
        final stats = entry.value;
        print(
          '$category: ${stats['total']} tests, ${stats['passed']} passed, ${stats['failed']} failed, ${stats['skipped']} skipped',
        );
      }

      print('\nLog files written to: $logDirPath');
      print('Summary report: ${reportFile.path}');

      if (failedCount > 0) {
        exit(1); // Indicate test failure
      }
    } catch (e, stackTrace) {
      print('\nError running test suite: $e');
      print(stackTrace);
      exit(2);
    }
  }

  Future<Map<String, int>> _runTestChunk(
    List<File> testFiles,
    Directory testDir,
  ) async {
    int passedCount = 0;
    int failedCount = 0;
    int skippedCount = 0;

    for (final testFile in testFiles) {
      final relativePath = testFile.path.replaceFirst(
        testDir.path + Platform.pathSeparator,
        '',
      );

      // Check if test should be skipped
      if (skipList.contains(relativePath)) {
        if (verbose) {
          print('\n--- Skipping test: $relativePath (in skip list) ---');
        }
        skippedCount++;

        results[relativePath] = TestResult(
          name: relativePath,
          passed: true,
          skipped: true,
          duration: Duration.zero,
          category: _getCategoryForTest(relativePath),
        );
        continue;
      }

      if (verbose) {
        print('\n--- Running test: $relativePath ---');
      }

      final testStartTime = DateTime.now();
      final logBuffer = StringBuffer();
      logBuffer.writeln('=== Test: $relativePath ===');
      logBuffer.writeln('Start time: $testStartTime');
      logBuffer.writeln('Mode: $mode');
      logBuffer.writeln(
        'Category: ${_getCategoryForTest(relativePath) ?? "uncategorized"}',
      );

      try {
        final sourceCode = await testFile.readAsString();

        logBuffer.writeln('\n--- Source Code ---');
        logBuffer.writeln(sourceCode);
        logBuffer.writeln('\n--- Execution ---');

        final _ = await executeCode(sourceCode, mode, onInterpreterSetup: (interpreter) {
          if (useInternalTests) {
            _injectInternalTestFunctions(interpreter.globals);
          }
        });

        final testEndTime = DateTime.now();
        final testDuration = testEndTime.difference(testStartTime);

        logBuffer.writeln('\n--- Result ---');
        logBuffer.writeln('Status: PASSED');
        logBuffer.writeln('Duration: ${testDuration.inMilliseconds} ms');

        if (verbose) {
          print(
            'Test passed: $relativePath (${testDuration.inMilliseconds} ms)',
          );
        }
        passedCount++;

        results[relativePath] = TestResult(
          name: relativePath,
          passed: true,
          duration: testDuration,
          category: _getCategoryForTest(relativePath),
        );
      } catch (e, stackTrace) {
        final testEndTime = DateTime.now();
        final testDuration = testEndTime.difference(testStartTime);

        logBuffer.writeln('\n--- Result ---');
        logBuffer.writeln('Status: FAILED');
        logBuffer.writeln('Error: $e');
        logBuffer.writeln('Stack trace:');
        logBuffer.writeln(stackTrace);
        logBuffer.writeln('Duration: ${testDuration.inMilliseconds} ms');

        if (verbose) {
          print('Test failed: $relativePath');
          print('Error: $e');
        }
        failedCount++;

        results[relativePath] = TestResult(
          name: relativePath,
          passed: false,
          errorMessage: e.toString(),
          duration: testDuration,
          category: _getCategoryForTest(relativePath),
        );
      }

      // Write test log
      final sanitizedName = relativePath.replaceAll(RegExp(r'[\/\\]'), '_');
      final logFile = File('$logDirPath/$sanitizedName.log');
      logFile.writeAsStringSync(logBuffer.toString());

      // Update progress bar from main thread
      progressBar.increment();
    }

    return {
      'passed': passedCount,
      'failed': failedCount,
      'skipped': skippedCount,
    };
  }

  Future<List<File>> _getTestFiles(Directory testDir) async {
    print("getting test files in ${testDir.path}");
    final List<File> testFiles = [];

    final testStream = testDir.list(recursive: true, followLinks: false);

    await for (final entity in testStream) {
      if (entity is File && entity.path.endsWith('.lua')) {
        testFiles.add(entity);
      }
    }
    return testFiles;
  }

  List<File> _filterTestFiles(List<File> allFiles) {
    if (categories.isEmpty && filterPattern == null) {
      return allFiles;
    }

    return allFiles.where((file) {
      final relativePath = file.path.replaceFirst(
        Directory(testSuitePath).path + Platform.pathSeparator,
        '',
      );

      // Check category filter
      if (categories.isNotEmpty) {
        final fileCategory = _getCategoryForTest(relativePath);
        if (fileCategory == null || !categories.contains(fileCategory)) {
          return false;
        }
      }

      // Check pattern filter
      if (filterPattern != null) {
        final regex = RegExp(filterPattern!);
        if (!regex.hasMatch(relativePath)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  String? _getCategoryForTest(String testPath) {
    final filename = p.basename(testPath);
    for (final entry in testCategories.entries) {
      if (entry.value.any((pattern) => filename.contains(pattern))) {
        return entry.key;
      }
    }
    return null;
  }

  Map<String, Map<String, int>> _getCategoryStatistics() {
    final stats = <String, Map<String, int>>{};

    // Initialize categories
    for (final category in testCategories.keys) {
      stats[category] = {'total': 0, 'passed': 0, 'failed': 0, 'skipped': 0};
    }
    stats['uncategorized'] = {
      'total': 0,
      'passed': 0,
      'failed': 0,
      'skipped': 0,
    };

    // Collect statistics
    for (final result in results.values) {
      final category = result.category ?? 'uncategorized';
      stats.putIfAbsent(
        category,
        () => {'total': 0, 'passed': 0, 'failed': 0, 'skipped': 0},
      );

      stats[category]!['total'] = (stats[category]!['total'] ?? 0) + 1;

      if (result.skipped) {
        stats[category]!['skipped'] = (stats[category]!['skipped'] ?? 0) + 1;
      } else if (result.passed) {
        stats[category]!['passed'] = (stats[category]!['passed'] ?? 0) + 1;
      } else {
        stats[category]!['failed'] = (stats[category]!['failed'] ?? 0) + 1;
      }
    }

    return stats;
  }

  void _injectInternalTestFunctions(Environment env) {
    // Implement Dart versions of the C functions used in the Lua test suite.
    // This is a placeholder, and needs to be fleshed out with actual implementations
    // that mimic the behavior of the original C functions.
    env.define('T', <String, dynamic>{
      // for example
      'testC': (List<Object?> args) {
        print("testC");
        return null;
      },
      'totalmem': (List<Object?> args) {
        print("totalmem");
        return 0;
      },
    });
    env.define('T', TestLib.functions);
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    final chunkCount = (list.length / chunkSize).ceil();
    final chunkLength = (list.length / chunkCount).ceil();

    for (var i = 0; i < list.length; i += chunkLength) {
      final end =
          (i + chunkLength < list.length) ? i + chunkLength : list.length;
      chunks.add(list.sublist(i, end));
    }

    return chunks;
  }
}
