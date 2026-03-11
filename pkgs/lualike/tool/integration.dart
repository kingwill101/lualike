import 'dart:async';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:lualike/integration.dart';
import 'package:yaml/yaml.dart';

// Configuration file constants
const String defaultConfigFile = 'tool/integration.yaml';

// Default configuration (will be overridden by config file if it exists)
String testSuitePath = '.lua-tests';
String logBaseDir = 'test-logs';
String logDirPath = ''; // Will be set during setup
String downloadUrl = 'https://www.lua.org/tests/lua-5.5.0-tests.tar.gz';
bool verbose = false;
bool parallel = false;
int parallelJobs = 4;
String? filterPattern;
List<String> categories = [];
bool keepOnlyLatest = false;
bool useInternalTests = true;

// Skip list for known failing tests
List<String> skipList = [];

void _setupLogging() {
  // Create base log directory if it doesn't exist
  final baseDir = Directory(logBaseDir);
  if (!baseDir.existsSync()) {
    baseDir.createSync(recursive: true);
  }
  // Create timestamped directory for this run
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  logDirPath = '$logBaseDir/run-$timestamp';
  final logDir = Directory(logDirPath);

  if (!keepOnlyLatest) {
    // Create new directory
    logDir.createSync(recursive: true);

    // Create or update 'latest' symlink
    final latestSymlink = Link('$logBaseDir/latest');
    if (latestSymlink.existsSync()) {
      latestSymlink.updateSync(logDirPath);
    } else {
      latestSymlink.createSync(logDirPath);
    }
  } else {
    // If keeping only latest, clear the base directory and use it directly
    if (baseDir.existsSync()) {
      for (final entity in baseDir.listSync()) {
        if (entity is File) {
          entity.deleteSync();
        } else if (entity is Directory) {
          entity.deleteSync(recursive: true);
        }
      }
    }
    logDirPath = logBaseDir;
  }

  print('Logs will be saved to: $logDirPath');
}

class IntegrationCommandRunner extends CommandRunner<void> {
  IntegrationCommandRunner()
    : super('lualike_test_runner', 'Run lualike integration tests.') {
    argParser
      ..addOption(
        'config',
        defaultsTo: defaultConfigFile,
        help: 'Path to integration config YAML file.',
      )
      ..addFlag(
        'internal',
        negatable: false,
        help: 'Enable internal tests (requires specific build).',
      )
      ..addOption('url', help: 'Override test suite download URL.')
      ..addOption('log-path', help: 'Base directory for log output.')
      ..addOption('path', help: 'Path to test suite (default: .lua-tests).')
      ..addFlag(
        'parallel',
        abbr: 'p',
        negatable: false,
        help: 'Run tests in parallel.',
      )
      ..addOption('jobs', abbr: 'j', help: 'Number of parallel jobs.')
      ..addOption(
        'filter',
        abbr: 'f',
        help: 'Filter tests by name using regex.',
      )
      ..addMultiOption(
        'category',
        abbr: 'c',
        splitCommas: true,
        help: 'Run tests from specific category.',
      )
      ..addFlag(
        'list-categories',
        negatable: false,
        help: 'List available test categories and exit.',
      )
      ..addFlag(
        'keep-only-latest',
        negatable: false,
        help: 'Keep only latest run log artifacts.',
      );
  }

  @override
  String get invocation => '$executableName [options]';

  @override
  Future<void> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['help'] as bool) {
      printUsage();
      return;
    }
    if (topLevelResults.rest.isNotEmpty) {
      usageException('Unexpected arguments: ${topLevelResults.rest.join(' ')}');
    }

    await _loadConfigFile(topLevelResults['config'] as String);

    if (topLevelResults['internal'] as bool) {
      useInternalTests = true;
    }

    if (topLevelResults.wasParsed('url')) {
      downloadUrl = topLevelResults['url'] as String;
    }
    if (topLevelResults.wasParsed('log-path')) {
      logBaseDir = topLevelResults['log-path'] as String;
    }
    if (topLevelResults.wasParsed('path')) {
      testSuitePath = topLevelResults['path'] as String;
    }
    if (topLevelResults.wasParsed('verbose')) {
      verbose = topLevelResults['verbose'] as bool;
    }
    if (topLevelResults.wasParsed('parallel')) {
      parallel = topLevelResults['parallel'] as bool;
    }
    if (topLevelResults.wasParsed('jobs')) {
      final parsedJobs = int.tryParse(topLevelResults['jobs'] as String);
      if (parsedJobs == null || parsedJobs <= 0) {
        usageException('--jobs must be a positive integer.');
      }
      parallelJobs = parsedJobs;
      parallel = true;
    }
    if (topLevelResults.wasParsed('filter')) {
      filterPattern = topLevelResults['filter'] as String;
    }
    if (topLevelResults.wasParsed('keep-only-latest')) {
      keepOnlyLatest = topLevelResults['keep-only-latest'] as bool;
    }

    if (topLevelResults['list-categories'] as bool) {
      print('Available test categories:');
      for (final entry in testCategories.entries) {
        print('  ${entry.key}: ${entry.value.join(', ')}');
      }
      return;
    }

    if (topLevelResults.wasParsed('category')) {
      final selectedCategories =
          topLevelResults['category'] as List<String>? ?? const <String>[];
      for (final category in selectedCategories) {
        if (testCategories.containsKey(category)) {
          categories.add(category);
        } else {
          print('Warning: Unknown category: $category');
          print('Available categories: ${testCategories.keys.join(', ')}');
        }
      }
    }

    _setupLogging();
    await checkAndDownloadTestSuite(downloadUrl, testSuitePath);

    final runner = TestRunner(
      testSuitePath: testSuitePath,
      useInternalTests: useInternalTests,
      logDirPath: logDirPath,
      verbose: verbose,
      parallel: parallel,
      parallelJobs: parallelJobs,
      filterPattern: filterPattern,
      categories: categories,
      skipList: skipList,
    );

    io.info('Running tests');
    await runner.runTestSuite();
    io.info('Tests finished');
    io.info('\nLog files are available at:');
    io.info('  Current run: $logDirPath');
    if (!keepOnlyLatest) {
      io.info('  Latest run symlink: $logBaseDir/latest');
    }
  }
}

Future<void> main(List<String> args) async {
  final runner = IntegrationCommandRunner();
  await runner.run(args);
}

Future<void> _loadConfigFile(String configPath) async {
  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    print(
      'Configuration file not found at $configPath, using default settings',
    );
    return;
  }

  try {
    print('Loading configuration from $configPath');
    final yamlContent = await configFile.readAsString();
    final yaml = loadYaml(yamlContent) as YamlMap;

    // Load test suite configuration
    if (yaml.containsKey('test_suite')) {
      final testSuite = yaml['test_suite'] as YamlMap;
      if (testSuite.containsKey('path')) {
        testSuitePath = testSuite['path'].toString();
      }
      if (testSuite.containsKey('download_url')) {
        downloadUrl = testSuite['download_url'].toString();
      }
    }

    // Load execution settings
    if (yaml.containsKey('execution')) {
      final execution = yaml['execution'] as YamlMap;

      if (execution.containsKey('use_internal_tests')) {
        useInternalTests = execution['use_internal_tests'] == true;
      }
      if (execution.containsKey('parallel')) {
        parallel = execution['parallel'] == true;
      }
      if (execution.containsKey('jobs')) {
        parallelJobs = int.tryParse(execution['jobs'].toString()) ?? 4;
      }
    }

    // Load logging configuration
    if (yaml.containsKey('logging')) {
      final logging = yaml['logging'] as YamlMap;
      if (logging.containsKey('base_dir')) {
        logBaseDir = logging['base_dir'].toString();
      }
      if (logging.containsKey('keep_only_latest')) {
        keepOnlyLatest = logging['keep_only_latest'] == true;
      }
      if (logging.containsKey('verbose')) {
        verbose = logging['verbose'] == true;
      }
    }

    // Load test selection
    if (yaml.containsKey('filter')) {
      final filter = yaml['filter'] as YamlMap;
      if (filter.containsKey('pattern') &&
          filter['pattern'] != null &&
          filter['pattern'] != 'null') {
        filterPattern = filter['pattern'].toString();
      }
      if (filter.containsKey('categories') &&
          filter['categories'] is YamlList) {
        categories = (filter['categories'] as YamlList)
            .map((item) => item.toString())
            .toList();
      }
    }

    // Load skip tests
    if (yaml.containsKey('skip_tests') && yaml['skip_tests'] is YamlList) {
      skipList = (yaml['skip_tests'] as YamlList)
          .map((item) => item.toString())
          .toList();
      print('Loaded ${skipList.length} tests to skip from config file');
    }

    print('Configuration loaded successfully');
  } catch (e) {
    print('Warning: Failed to load configuration: $e');
  }
}
