import 'dart:io';
import 'dart:async';
import 'package:lualike/integration.dart';

import 'package:yaml/yaml.dart';

// Configuration file constants
const String defaultConfigFile = 'tools/integration.yaml';

// Default configuration (will be overridden by config file if it exists)
String testSuitePath = '.lua-tests';
String logBaseDir = 'test-logs';
String logDirPath = ''; // Will be set during setup
String downloadUrl = 'https://www.lua.org/tests/lua-5.4.7-tests.tar.gz';
bool verbose = false;
bool parallel = false;
int parallelJobs = 4;
String? filterPattern;
List<String> categories = [];
bool keepOnlyLatest = false;
ExecutionMode mode = ExecutionMode.astInterpreter;
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

Future<void> main(List<String> arguments) async {
  String configFile = defaultConfigFile;

  // First check if a specific config file is specified
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--config' && i + 1 < arguments.length) {
      configFile = arguments[++i];
      break;
    }
  }

  // Load configuration from file
  await _loadConfigFile(configFile);

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--config':
        // Already handled before the main argument parsing
        if (i + 1 < arguments.length) i++;
        break;
      case '--ast':
        mode = ExecutionMode.astInterpreter;
        break;
      case '--bytecode':
        mode = ExecutionMode.bytecodeVM;
        break;
      case '--internal':
        useInternalTests = true;
        break;
      case '--url':
        if (i + 1 < arguments.length) {
          downloadUrl = arguments[++i];
        }
        break;
      case '--log-path':
        if (i + 1 < arguments.length) {
          logBaseDir = arguments[++i];
        } else {
          print('Error: --log-path requires an argument');
          exit(1);
        }
        break;
      case '--path':
        if (i + 1 < arguments.length) {
          testSuitePath = arguments[++i];
        } else {
          print('Error: --path requires an argument');
          exit(1);
        }
        break;
      // skip-list is now handled in the config file
      case '--verbose':
      case '-v':
        verbose = true;
        break;
      case '--parallel':
      case '-p':
        parallel = true;
        break;
      case '--jobs':
      case '-j':
        if (i + 1 < arguments.length) {
          parallelJobs = int.tryParse(arguments[++i]) ?? 4;
          parallel = true;
        } else {
          print('Error: --jobs requires an argument');
          exit(1);
        }
        break;
      case '--filter':
      case '-f':
        if (i + 1 < arguments.length) {
          filterPattern = arguments[++i];
        } else {
          print('Error: --filter requires an argument');
          exit(1);
        }
        break;
      case '--category':
      case '-c':
        if (i + 1 < arguments.length) {
          final category = arguments[++i];
          if (testCategories.containsKey(category)) {
            categories.add(category);
          } else {
            print('Warning: Unknown category: $category');
            print('Available categories: ${testCategories.keys.join(', ')}');
          }
        } else {
          print('Error: --category requires an argument');
          exit(1);
        }
        break;
      case '--list-categories':
        print('Available test categories:');
        for (final entry in testCategories.entries) {
          print('  ${entry.key}: ${entry.value.join(', ')}');
        }
        exit(0);
      case '--keep-only-latest':
        keepOnlyLatest = true;
        break;
      default:
        print('Unknown option: ${arguments[i]}');
        printUsage();
        exit(1);
    }
  }

  // Set up logging directory
  _setupLogging();

  // Skip list is loaded from config file

  // Download test suite if needed
  await checkAndDownloadTestSuite(downloadUrl, testSuitePath);

  final runner = TestRunner(
    testSuitePath: testSuitePath,
    mode: mode,
    useInternalTests: true,
    logDirPath: logDirPath,
    verbose: verbose,
    parallel: parallel,
    parallelJobs: parallelJobs,
    filterPattern: filterPattern,
    categories: categories,
    skipList: skipList,
  );
  print("Running tests");
  await runner.runTestSuite();
  print("Tests finished");
  print("\nLog files are available at:");
  print("  Current run: $logDirPath");
  if (!keepOnlyLatest) {
    print("  Latest run symlink: $logBaseDir/latest");
  }
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
      if (execution.containsKey('mode')) {
        final modeStr = execution['mode'].toString().toLowerCase();
        if (modeStr == 'bytecode') {
          mode = ExecutionMode.bytecodeVM;
        } else {
          mode = ExecutionMode.astInterpreter;
        }
      }
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
        categories =
            (filter['categories'] as YamlList)
                .map((item) => item.toString())
                .toList();
      }
    }

    // Load skip tests
    if (yaml.containsKey('skip_tests') && yaml['skip_tests'] is YamlList) {
      skipList =
          (yaml['skip_tests'] as YamlList)
              .map((item) => item.toString())
              .toList();
      print('Loaded ${skipList.length} tests to skip from config file');
    }

    print('Configuration loaded successfully');
  } catch (e) {
    print('Warning: Failed to load configuration: $e');
  }
}

void printUsage() {
  print('''
Usage: lualike_test_runner [options]
Options:
  --ast                Run tests using AST interpreter (default)
  --bytecode           Run tests using bytecode VM
  --internal           Enable internal tests (requires specific build)
  --path <path>        Specify the path to the test suite (default: .lua-tests)
  --log-path <path>    Specify the path for log files
  --skip-list <path>   Specify the path to the skip list YAML file (default: tools/skip_tests.yaml)
  --verbose, -v        Enable verbose output
  --parallel, -p       Run tests in parallel
  --jobs, -j <n>       Number of parallel jobs (default: 4)
  --filter, -f <regex> Filter tests by name using regex
  --category, -c <cat> Run tests from specific category
  --list-categories    List available test categories
''');
}
