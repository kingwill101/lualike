import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:lualike/src/parse.dart' as parse_api;
import 'package:lualike/src/parsers/lua.dart' as lua_parser;
import 'package:path/path.dart' as path;
import 'package:petitparser/debug.dart' as pp_debug;
import 'package:petitparser/petitparser.dart';
import 'package:petitparser/reflection.dart' as pp_reflection;
import 'package:source_span/source_span.dart';

const _defaultCorpusDirectory = 'luascripts/parser_profiles';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'corpus',
      help: 'Corpus directory, relative to the lualike package root.',
      defaultsTo: _defaultCorpusDirectory,
    )
    ..addMultiOption(
      'case',
      abbr: 'c',
      help: 'Corpus case name without .lua. Repeat to run several cases.',
    )
    ..addMultiOption(
      'path',
      abbr: 'p',
      help: 'Additional Lua file or directory to include.',
    )
    ..addOption(
      'warmup',
      help: 'Warmup parses before measured runs.',
      defaultsTo: '5',
    )
    ..addOption('repeat', help: 'Measured parses per script.', defaultsTo: '30')
    ..addOption(
      'top',
      help: 'Profile rows to print for elapsed time and activation counts.',
      defaultsTo: '15',
    )
    ..addOption('label', help: 'Optional label written to JSON snapshots.')
    ..addOption('json-out', help: 'Write timing results as JSON to this file.')
    ..addFlag(
      'profile',
      help: 'Run petitparser profile() for each script.',
      defaultsTo: false,
    )
    ..addFlag(
      'trace',
      help: 'Run petitparser trace() for each script.',
      defaultsTo: false,
    )
    ..addOption(
      'trace-limit',
      help: 'Maximum trace events to print per script.',
      defaultsTo: '120',
    )
    ..addFlag(
      'progress',
      help: 'Run petitparser progress() and summarize parser movement.',
      defaultsTo: false,
    )
    ..addOption(
      'progress-limit',
      help: 'Maximum progress events to print per script.',
      defaultsTo: '80',
    )
    ..addFlag(
      'lint',
      help: 'Run the petitparser reflection linter against the Lua grammar.',
      defaultsTo: false,
    )
    ..addFlag(
      'fail-fast',
      help: 'Stop after the first parse failure.',
      defaultsTo: true,
    )
    ..addFlag('help', abbr: 'h', help: 'Print usage.', negatable: false);

  final options = parser.parse(args);
  if (options.flag('help')) {
    stdout.writeln('Lua grammar parser profiling harness');
    stdout.writeln(parser.usage);
    return;
  }

  final packageRoot = _findPackageRoot();
  final corpusDirectory = path.normalize(
    path.join(packageRoot, options.option('corpus')!),
  );
  final scripts = _loadScripts(
    corpusDirectory: corpusDirectory,
    packageRoot: packageRoot,
    caseNames: options.multiOption('case'),
    extraPaths: options.multiOption('path'),
  );

  if (scripts.isEmpty) {
    stderr.writeln('No parser profile scripts found.');
    exitCode = 64;
    return;
  }

  final config = _ProfileConfig(
    warmup: _parsePositiveInt(options.option('warmup')!, 'warmup'),
    repeat: _parsePositiveInt(options.option('repeat')!, 'repeat'),
    top: _parsePositiveInt(options.option('top')!, 'top'),
    profile: options.flag('profile'),
    trace: options.flag('trace'),
    traceLimit: _parsePositiveInt(
      options.option('trace-limit')!,
      'trace-limit',
    ),
    progress: options.flag('progress'),
    progressLimit: _parsePositiveInt(
      options.option('progress-limit')!,
      'progress-limit',
    ),
    lint: options.flag('lint'),
    failFast: options.flag('fail-fast'),
  );

  stdout.writeln('Lua parser profile corpus: $corpusDirectory');
  stdout.writeln(
    'scripts=${scripts.length} warmup=${config.warmup} '
    'repeat=${config.repeat}',
  );
  stdout.writeln('');

  if (config.lint) {
    _runLinter(scripts.first);
    stdout.writeln('');
  }

  final stats = <_ParseStats>[];
  for (final script in scripts) {
    try {
      final result = _timeScript(script, config);
      stats.add(result);
      _printStats(result);

      if (config.profile) {
        _runProfile(script, top: config.top);
      }
      if (config.progress) {
        _runProgress(script, limit: config.progressLimit);
      }
      if (config.trace) {
        _runTrace(script, limit: config.traceLimit);
      }
    } catch (error, stackTrace) {
      stderr.writeln('Failed while parsing ${script.name}: $error');
      if (config.failFast) {
        stderr.writeln(stackTrace);
        exitCode = 1;
        return;
      }
    }
  }

  _printSummary(stats);

  final jsonOut = options.option('json-out');
  if (jsonOut != null) {
    _writeJsonSnapshot(
      packageRoot: packageRoot,
      corpusDirectory: corpusDirectory,
      arguments: args,
      label: options.option('label'),
      config: config,
      stats: stats,
      outputPath: jsonOut,
    );
  }
}

final class _ProfileConfig {
  const _ProfileConfig({
    required this.warmup,
    required this.repeat,
    required this.top,
    required this.profile,
    required this.trace,
    required this.traceLimit,
    required this.progress,
    required this.progressLimit,
    required this.lint,
    required this.failFast,
  });

  final int warmup;
  final int repeat;
  final int top;
  final bool profile;
  final bool trace;
  final int traceLimit;
  final bool progress;
  final int progressLimit;
  final bool lint;
  final bool failFast;
}

final class _LuaScript {
  const _LuaScript({
    required this.name,
    required this.path,
    required this.source,
    required this.sourceEncoding,
  });

  final String name;
  final String path;
  final String source;
  final String sourceEncoding;

  int get charCount => source.length;

  int get lineCount => '\n'.allMatches(source).length + 1;
}

final class _ParseStats {
  const _ParseStats({required this.script, required this.samplesMicros});

  final _LuaScript script;
  final List<int> samplesMicros;

  int get minMicros => samplesMicros.reduce(math.min);

  int get maxMicros => samplesMicros.reduce(math.max);

  double get meanMicros =>
      samplesMicros.reduce((left, right) => left + right) /
      samplesMicros.length;

  double get medianMicros {
    final sorted = List<int>.from(samplesMicros)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle].toDouble();
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double get charsPerSecond => script.charCount / (meanMicros / 1000000.0);
}

final class _ProfileFrame {
  const _ProfileFrame({
    required this.parserName,
    required this.count,
    required this.elapsedMicros,
  });

  final String parserName;
  final int count;
  final int elapsedMicros;
}

final class _AggregatedProfileFrame {
  _AggregatedProfileFrame(this.parserName);

  final String parserName;
  var count = 0;
  var elapsedMicros = 0;

  void add(_ProfileFrame frame) {
    count += frame.count;
    elapsedMicros += frame.elapsedMicros;
  }
}

final class _ProgressEvent {
  const _ProgressEvent({required this.position, required this.parserName});

  final int position;
  final String parserName;
}

_ParseStats _timeScript(_LuaScript script, _ProfileConfig config) {
  for (var i = 0; i < config.warmup; i++) {
    parse_api.parse(script.source, url: script.path);
  }

  final samples = <int>[];
  for (var i = 0; i < config.repeat; i++) {
    final stopwatch = Stopwatch()..start();
    parse_api.parse(script.source, url: script.path);
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }

  return _ParseStats(script: script, samplesMicros: samples);
}

void _runLinter(_LuaScript script) {
  final parser = _buildLuaParser(script);
  final issues = pp_reflection.linter(parser);

  stdout.writeln('PetitParser linter');
  if (issues.isEmpty) {
    stdout.writeln('  No issues found.');
    return;
  }

  for (final issue in issues) {
    stdout.writeln(
      '  ${issue.type.name.padRight(7)} ${issue.title}: '
      '${issue.parser}',
    );
    stdout.writeln('    ${issue.description}');
  }
}

void _runProfile(_LuaScript script, {required int top}) {
  final frames = <_ProfileFrame>[];
  final profiled = pp_debug.profile(
    _buildLuaParser(script),
    output: (frame) {
      frames.add(
        _ProfileFrame(
          parserName: frame.parser.toString(),
          count: frame.count,
          elapsedMicros: frame.elapsed.inMicroseconds,
        ),
      );
    },
  );

  final result = profiled.parse(script.source);
  _requireSuccess(script, result);

  if (frames.isEmpty) {
    stdout.writeln('  No PetitParser profile frames captured.');
    return;
  }

  final aggregated = <String, _AggregatedProfileFrame>{};
  for (final frame in frames) {
    aggregated
        .putIfAbsent(
          frame.parserName,
          () => _AggregatedProfileFrame(frame.parserName),
        )
        .add(frame);
  }

  final byTime = aggregated.values.toList()
    ..sort((left, right) => right.elapsedMicros.compareTo(left.elapsedMicros));
  final byCount = aggregated.values.toList()
    ..sort((left, right) => right.count.compareTo(left.count));

  stdout.writeln('  PetitParser profile: ${script.name}');
  stdout.writeln('  Top $top by inclusive elapsed time');
  for (final frame in byTime.take(top)) {
    stdout.writeln(
      '    ${_formatMicros(frame.elapsedMicros).padLeft(10)}  '
      '${frame.count.toString().padLeft(8)}  ${frame.parserName}',
    );
  }

  stdout.writeln('  Top $top by activation count');
  for (final frame in byCount.take(top)) {
    stdout.writeln(
      '    ${frame.count.toString().padLeft(8)}  '
      '${_formatMicros(frame.elapsedMicros).padLeft(10)}  '
      '${frame.parserName}',
    );
  }
}

void _runProgress(_LuaScript script, {required int limit}) {
  final events = <_ProgressEvent>[];
  final progressed = pp_debug.progress(
    _buildLuaParser(script),
    output: (frame) {
      events.add(
        _ProgressEvent(
          position: frame.position,
          parserName: frame.parser.toString(),
        ),
      );
    },
  );

  final result = progressed.parse(script.source);
  _requireSuccess(script, result);

  var backtracks = 0;
  var maxBacktrack = 0;
  var previous = 0;
  for (final event in events) {
    if (event.position < previous) {
      backtracks++;
      maxBacktrack = math.max(maxBacktrack, previous - event.position);
    }
    previous = event.position;
  }

  stdout.writeln('  PetitParser progress: ${script.name}');
  stdout.writeln(
    '    events=${events.length} backtracks=$backtracks '
    'maxBacktrack=$maxBacktrack chars',
  );

  for (final (index, event) in events.take(limit).indexed) {
    stdout.writeln(
      '    ${index.toString().padLeft(4)} '
      'pos=${event.position.toString().padLeft(4)} ${event.parserName}',
    );
  }
  if (events.length > limit) {
    stdout.writeln('    ... ${events.length - limit} progress events omitted');
  }
}

void _runTrace(_LuaScript script, {required int limit}) {
  final events = <pp_debug.TraceEvent>[];
  var omitted = 0;
  final traced = pp_debug.trace(
    _buildLuaParser(script),
    output: (event) {
      if (events.length < limit) {
        events.add(event);
      } else {
        omitted++;
      }
    },
  );

  final result = traced.parse(script.source);
  _requireSuccess(script, result);

  stdout.writeln('  PetitParser trace: ${script.name}');
  for (final event in events) {
    stdout.writeln('    ${_formatTraceEvent(event)}');
  }
  if (omitted > 0) {
    stdout.writeln('    ... $omitted trace events omitted');
  }
}

Parser _buildLuaParser(_LuaScript script) {
  final sourceFile = SourceFile.fromString(
    script.source,
    url: Uri.file(script.path),
  );
  final definition = lua_parser.LuaGrammarDefinition(sourceFile);
  return definition.build();
}

void _requireSuccess(_LuaScript script, Result result) {
  if (result is Failure) {
    throw FormatException(
      '${script.name}: ${result.message} at ${result.position}',
    );
  }
}

String _formatTraceEvent(pp_debug.TraceEvent event) {
  final indent = '  ' * event.level;
  final result = event.result;
  if (result == null) {
    return '$indent> pos=${event.context.position} ${event.parser}';
  }

  final status = switch (result) {
    Success(position: final position) => 'ok@$position',
    Failure(message: final message, position: final position) =>
      'fail@$position $message',
  };
  return '$indent< $status';
}

void _printStats(_ParseStats stats) {
  stdout.writeln(
    '${stats.script.name.padRight(24)} '
    '${stats.script.charCount.toString().padLeft(5)} chars  '
    '${stats.script.lineCount.toString().padLeft(3)} lines  '
    '${stats.script.sourceEncoding.padRight(6)}  '
    'mean ${_formatMicros(stats.meanMicros).padLeft(10)}  '
    'median ${_formatMicros(stats.medianMicros).padLeft(10)}  '
    'min ${_formatMicros(stats.minMicros).padLeft(10)}  '
    'max ${_formatMicros(stats.maxMicros).padLeft(10)}  '
    '${stats.charsPerSecond.toStringAsFixed(0).padLeft(9)} chars/s',
  );
}

void _printSummary(List<_ParseStats> stats) {
  if (stats.isEmpty) {
    return;
  }

  final sorted = List<_ParseStats>.from(stats)
    ..sort((left, right) => right.meanMicros.compareTo(left.meanMicros));

  stdout.writeln('');
  stdout.writeln('Slowest parser corpus cases');
  for (final stats in sorted) {
    stdout.writeln(
      '  ${stats.script.name.padRight(24)} '
      'mean ${_formatMicros(stats.meanMicros).padLeft(10)}  '
      '${stats.charsPerSecond.toStringAsFixed(0).padLeft(9)} chars/s',
    );
  }
}

void _writeJsonSnapshot({
  required String packageRoot,
  required String corpusDirectory,
  required List<String> arguments,
  required String? label,
  required _ProfileConfig config,
  required List<_ParseStats> stats,
  required String outputPath,
}) {
  final outputFile = File(
    path.isAbsolute(outputPath)
        ? outputPath
        : path.join(packageRoot, outputPath),
  );
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(_snapshotJson(packageRoot: packageRoot, corpusDirectory: corpusDirectory, arguments: arguments, label: label, config: config, stats: stats))}\n',
  );

  stdout.writeln('');
  stdout.writeln('Wrote parser profile JSON: ${outputFile.path}');
}

Map<String, Object?> _snapshotJson({
  required String packageRoot,
  required String corpusDirectory,
  required List<String> arguments,
  required String? label,
  required _ProfileConfig config,
  required List<_ParseStats> stats,
}) {
  final totalMeanMicros = stats.fold<double>(
    0,
    (total, entry) => total + entry.meanMicros,
  );
  return {
    'schemaVersion': 1,
    'generatedBy': 'tool/parser_profile.dart',
    'capturedAt': DateTime.now().toIso8601String(),
    'label': label,
    'packageRoot': packageRoot,
    'git': _gitMetadata(packageRoot),
    'corpus': {
      'directory': corpusDirectory,
      'relativeDirectory': path.relative(corpusDirectory, from: packageRoot),
    },
    'config': {
      'warmup': config.warmup,
      'repeat': config.repeat,
      'profile': config.profile,
      'trace': config.trace,
      'progress': config.progress,
      'lint': config.lint,
      'failFast': config.failFast,
    },
    'arguments': arguments,
    'rows': [
      for (final entry in stats)
        {
          'case': entry.script.name,
          'path': path.relative(entry.script.path, from: packageRoot),
          'source': {
            'characters': entry.script.charCount,
            'lines': entry.script.lineCount,
            'encoding': entry.script.sourceEncoding,
          },
          'samplesMicros': entry.samplesMicros,
          'minMicros': entry.minMicros,
          'meanMicros': entry.meanMicros,
          'medianMicros': entry.medianMicros,
          'maxMicros': entry.maxMicros,
          'charsPerSecond': entry.charsPerSecond,
        },
    ],
    'total': {'meanMicros': totalMeanMicros, 'meanMs': totalMeanMicros / 1000},
  };
}

Map<String, Object?> _gitMetadata(String packageRoot) {
  final revision = _gitOutput(packageRoot, ['rev-parse', 'HEAD']);
  final branch = _gitOutput(packageRoot, ['branch', '--show-current']);
  final status = _gitOutput(packageRoot, ['status', '--short']);
  final statusLines = status == null || status.isEmpty
      ? const <String>[]
      : status.split('\n');
  return {
    'revision': revision,
    'branch': branch?.isEmpty ?? true ? null : branch,
    'dirty': statusLines.isNotEmpty,
    'statusShort': statusLines,
  };
}

String? _gitOutput(String packageRoot, List<String> arguments) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: packageRoot,
  );
  if (result.exitCode != 0) {
    return null;
  }
  return (result.stdout as String).trim();
}

List<_LuaScript> _loadScripts({
  required String corpusDirectory,
  required String packageRoot,
  required List<String> caseNames,
  required List<String> extraPaths,
}) {
  final scriptsByPath = <String, _LuaScript>{};

  void addFile(File file) {
    if (!file.path.endsWith('.lua')) {
      return;
    }
    final normalizedPath = path.normalize(file.absolute.path);
    final decoded = _decodeLuaSourceBytes(file.readAsBytesSync());
    scriptsByPath[normalizedPath] = _LuaScript(
      name: _scriptName(
        corpusDirectory: corpusDirectory,
        packageRoot: packageRoot,
        normalizedPath: normalizedPath,
      ),
      path: normalizedPath,
      source: decoded.source,
      sourceEncoding: decoded.encoding,
    );
  }

  if (caseNames.isEmpty) {
    final directory = Directory(corpusDirectory);
    if (directory.existsSync()) {
      final entries =
          directory.listSync(recursive: true).whereType<File>().toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final entry in entries) {
        addFile(entry);
      }
    }
  } else {
    for (final caseName in caseNames) {
      final file = File(path.join(corpusDirectory, '$caseName.lua'));
      if (!file.existsSync()) {
        throw ArgumentError.value(
          caseName,
          'case',
          'No parser profile case at ${file.path}',
        );
      }
      addFile(file);
    }
  }

  for (final extraPath in extraPaths) {
    final resolved = path.isAbsolute(extraPath)
        ? extraPath
        : path.join(packageRoot, extraPath);
    final type = FileSystemEntity.typeSync(resolved);
    if (type == FileSystemEntityType.file) {
      addFile(File(resolved));
    } else if (type == FileSystemEntityType.directory) {
      final entries =
          Directory(
              resolved,
            ).listSync(recursive: true).whereType<File>().toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final entry in entries) {
        addFile(entry);
      }
    } else {
      throw ArgumentError.value(extraPath, 'path', 'No such file or directory');
    }
  }

  return scriptsByPath.values.toList()
    ..sort((left, right) => left.name.compareTo(right.name));
}

({String source, String encoding}) _decodeLuaSourceBytes(List<int> bytes) {
  try {
    return (source: utf8.decode(bytes), encoding: 'utf8');
  } on FormatException {
    return (
      source: latin1.decode(bytes, allowInvalid: true),
      encoding: 'latin1',
    );
  }
}

String _scriptName({
  required String corpusDirectory,
  required String packageRoot,
  required String normalizedPath,
}) {
  final relativeToCorpus = path.relative(normalizedPath, from: corpusDirectory);
  final relativePath =
      !relativeToCorpus.startsWith('..') && !path.isAbsolute(relativeToCorpus)
      ? relativeToCorpus
      : path.relative(normalizedPath, from: packageRoot);
  return path.withoutExtension(relativePath).replaceAll(path.separator, '/');
}

String _findPackageRoot() {
  var current = path.normalize(Directory.current.absolute.path);
  while (true) {
    final pubspec = File(path.join(current, 'pubspec.yaml'));
    final parserCorpus = Directory(path.join(current, _defaultCorpusDirectory));
    if (pubspec.existsSync() && parserCorpus.existsSync()) {
      return current;
    }

    final nestedPackage = path.join(current, 'pkgs', 'lualike');
    final nestedPubspec = File(path.join(nestedPackage, 'pubspec.yaml'));
    final nestedCorpus = Directory(
      path.join(nestedPackage, _defaultCorpusDirectory),
    );
    if (nestedPubspec.existsSync() && nestedCorpus.existsSync()) {
      return nestedPackage;
    }

    final parent = path.dirname(current);
    if (parent == current) {
      throw StateError('Could not find the lualike package root.');
    }
    current = parent;
  }
}

int _parsePositiveInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw ArgumentError.value(value, name, 'Expected a positive integer');
  }
  return parsed;
}

String _formatMicros(num micros) {
  if (micros >= 1000) {
    return '${(micros / 1000).toStringAsFixed(3)} ms';
  }
  return '${micros.toStringAsFixed(0)} us';
}
