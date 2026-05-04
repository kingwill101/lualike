import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

const _defaultBaselineRef = 'origin/ir';
const _defaultOutputDirectory = 'benchmarks/parser_profiles';

const _hotSuiteCases = [
  'strings',
  'test/api',
  'test/files',
  'test/math',
  'test/db',
  'test/locals',
  'test/code',
  'test/pm',
  'test/strings',
];

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'baseline-ref',
      help: 'Git ref used for the clean baseline worktree.',
      defaultsTo: _defaultBaselineRef,
    )
    ..addOption(
      'output-dir',
      help: 'Directory for generated local snapshots.',
      defaultsTo: _defaultOutputDirectory,
    )
    ..addOption(
      'warmup',
      help: 'Warmup parses before measured runs.',
      defaultsTo: '5',
    )
    ..addOption('repeat', help: 'Measured parses per script.', defaultsTo: '10')
    ..addFlag(
      'pub-get',
      help: 'Run dart pub get in the temporary baseline worktree.',
      defaultsTo: true,
    )
    ..addFlag(
      'keep-baseline-worktree',
      help: 'Leave the temporary baseline worktree on disk.',
      defaultsTo: false,
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage.');

  final options = parser.parse(args);
  if (options.flag('help')) {
    stdout.writeln('Generate baseline/current parser profile snapshots.');
    stdout.writeln(parser.usage);
    return;
  }

  final packageRoot = _findPackageRoot();
  final repoRoot = _gitOutput(packageRoot, ['rev-parse', '--show-toplevel']);
  if (repoRoot == null) {
    stderr.writeln('Could not find git repository root.');
    exitCode = 1;
    return;
  }

  final baselineRef = options.option('baseline-ref')!;
  final warmup = _positiveInt(options.option('warmup')!, 'warmup');
  final repeat = _positiveInt(options.option('repeat')!, 'repeat');
  final outputDirectory = _resolvePackagePath(
    packageRoot,
    options.option('output-dir')!,
  );
  Directory(outputDirectory).createSync(recursive: true);

  final stamp = _timestampForFile(DateTime.now());
  final baselineWorktree = Directory.systemTemp.createTempSync(
    'lualike-parser-baseline.',
  );
  final baselinePackageRoot = path.join(
    baselineWorktree.path,
    path.relative(packageRoot, from: repoRoot),
  );

  try {
    _run('git', [
      'worktree',
      'add',
      '--detach',
      baselineWorktree.path,
      baselineRef,
    ], workingDirectory: repoRoot);
    _copyProfilingTools(
      currentPackageRoot: packageRoot,
      baselinePackageRoot: baselinePackageRoot,
    );

    if (options.flag('pub-get')) {
      _run('dart', ['pub', 'get'], workingDirectory: baselinePackageRoot);
    }

    final small = _ProfileSet(
      name: 'small-parser-corpus',
      title: 'Small Parser Corpus',
      baselineJson: path.join(outputDirectory, '$stamp-baseline-small.json'),
      latestJson: path.join(outputDirectory, '$stamp-latest-small.json'),
      comparisonJson: path.join(
        outputDirectory,
        '$stamp-comparison-small.json',
      ),
      comparisonMarkdown: path.join(
        outputDirectory,
        '$stamp-comparison-small.md',
      ),
      profileArguments: const [],
    );
    final hot = _ProfileSet(
      name: 'hot-lua-suite',
      title: 'Hot Lua Suite',
      baselineJson: path.join(outputDirectory, '$stamp-baseline-hot.json'),
      latestJson: path.join(outputDirectory, '$stamp-latest-hot.json'),
      comparisonJson: path.join(outputDirectory, '$stamp-comparison-hot.json'),
      comparisonMarkdown: path.join(
        outputDirectory,
        '$stamp-comparison-hot.md',
      ),
      profileArguments: [
        for (final caseName in _hotSuiteCases) ...['-c', caseName],
        '--corpus=luascripts',
      ],
    );

    for (final set in [small, hot]) {
      _runProfileSet(
        set: set,
        baselinePackageRoot: baselinePackageRoot,
        currentPackageRoot: packageRoot,
        baselineRef: baselineRef,
        warmup: warmup,
        repeat: repeat,
      );
    }

    stdout.writeln('');
    stdout.writeln('Generated parser profile snapshots:');
    for (final set in [small, hot]) {
      stdout.writeln('  ${set.name}');
      stdout.writeln('    baseline: ${set.baselineJson}');
      stdout.writeln('    latest:   ${set.latestJson}');
      stdout.writeln('    summary:  ${set.comparisonMarkdown}');
      stdout.writeln('    json:     ${set.comparisonJson}');
    }
  } finally {
    if (options.flag('keep-baseline-worktree')) {
      stdout.writeln('Kept baseline worktree: ${baselineWorktree.path}');
    } else {
      _run('git', [
        'worktree',
        'remove',
        '--force',
        baselineWorktree.path,
      ], workingDirectory: repoRoot);
    }
  }
}

void _runProfileSet({
  required _ProfileSet set,
  required String baselinePackageRoot,
  required String currentPackageRoot,
  required String baselineRef,
  required int warmup,
  required int repeat,
}) {
  _run('dart', [
    'run',
    'tool/parser_profile.dart',
    '--warmup=$warmup',
    '--repeat=$repeat',
    '--label=$baselineRef ${set.name}',
    '--json-out=${set.baselineJson}',
    '--no-fail-fast',
    ...set.profileArguments,
  ], workingDirectory: baselinePackageRoot);
  _run('dart', [
    'run',
    'tool/parser_profile.dart',
    '--warmup=$warmup',
    '--repeat=$repeat',
    '--label=current ${set.name}',
    '--json-out=${set.latestJson}',
    '--no-fail-fast',
    ...set.profileArguments,
  ], workingDirectory: currentPackageRoot);
  _run('dart', [
    'run',
    'tool/parser_profile_compare.dart',
    '--baseline=${set.baselineJson}',
    '--latest=${set.latestJson}',
    '--title=${set.title}',
    '--json-out=${set.comparisonJson}',
    '--markdown-out=${set.comparisonMarkdown}',
  ], workingDirectory: currentPackageRoot);
}

void _copyProfilingTools({
  required String currentPackageRoot,
  required String baselinePackageRoot,
}) {
  for (final relativePath in [
    'tool/parser_profile.dart',
    'tool/parser_profile_compare.dart',
  ]) {
    final source = File(path.join(currentPackageRoot, relativePath));
    final destination = File(path.join(baselinePackageRoot, relativePath));
    destination.parent.createSync(recursive: true);
    source.copySync(destination.path);
  }

  final sourceCorpus = Directory(
    path.join(currentPackageRoot, 'luascripts/parser_profiles'),
  );
  final destinationCorpus = Directory(
    path.join(baselinePackageRoot, 'luascripts/parser_profiles'),
  );
  destinationCorpus.createSync(recursive: true);
  for (final entry in sourceCorpus.listSync(recursive: true)) {
    if (entry is! File || !entry.path.endsWith('.lua')) {
      continue;
    }
    final relativePath = path.relative(entry.path, from: sourceCorpus.path);
    final destination = File(path.join(destinationCorpus.path, relativePath));
    destination.parent.createSync(recursive: true);
    entry.copySync(destination.path);
  }
}

String _findPackageRoot() {
  var current = path.normalize(Directory.current.absolute.path);
  while (true) {
    final pubspec = File(path.join(current, 'pubspec.yaml'));
    final tool = File(path.join(current, 'tool', 'parser_profile.dart'));
    if (pubspec.existsSync() && tool.existsSync()) {
      return current;
    }

    final nestedPackage = path.join(current, 'pkgs', 'lualike');
    final nestedPubspec = File(path.join(nestedPackage, 'pubspec.yaml'));
    final nestedTool = File(
      path.join(nestedPackage, 'tool', 'parser_profile.dart'),
    );
    if (nestedPubspec.existsSync() && nestedTool.existsSync()) {
      return nestedPackage;
    }

    final parent = path.dirname(current);
    if (parent == current) {
      throw StateError('Could not find the lualike package root.');
    }
    current = parent;
  }
}

String _resolvePackagePath(String packageRoot, String filePath) {
  return path.normalize(
    path.isAbsolute(filePath) ? filePath : path.join(packageRoot, filePath),
  );
}

String _timestampForFile(DateTime dateTime) {
  final local = dateTime.toIso8601String().split('.').first;
  return local.replaceAll(':', '-');
}

int _positiveInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw ArgumentError.value(value, name, 'Expected a positive integer');
  }
  return parsed;
}

String? _gitOutput(String workingDirectory, List<String> arguments) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    return null;
  }
  return (result.stdout as String).trim();
}

void _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) {
  stdout.writeln(
    '[${path.basename(workingDirectory)}] '
    '$executable ${arguments.join(' ')}',
  );
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command failed with exit code ${result.exitCode}',
      result.exitCode,
    );
  }
}

final class _ProfileSet {
  const _ProfileSet({
    required this.name,
    required this.title,
    required this.baselineJson,
    required this.latestJson,
    required this.comparisonJson,
    required this.comparisonMarkdown,
    required this.profileArguments,
  });

  final String name;
  final String title;
  final String baselineJson;
  final String latestJson;
  final String comparisonJson;
  final String comparisonMarkdown;
  final List<String> profileArguments;
}
