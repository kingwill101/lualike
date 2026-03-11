import 'dart:math' as math;
import 'dart:typed_data';

import 'package:artisanal/args.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/legacy_ast_chunk_transport.dart';
import 'package:lualike/src/parse.dart' as parse_api;
import 'package:lualike/src/parsers/lua.dart' as lua_parser;
import 'package:lualike/src/utils/file_system_utils.dart' as fs;
import 'package:lualike/src/utils/io_abstractions.dart' as io_abs;
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:path/path.dart' as path;
import 'package:petitparser/debug.dart' as pp_debug;
import 'package:petitparser/reflection.dart' as pp_reflection;
import 'package:source_span/source_span.dart';

const _defaultScenario = 'all';

const _groupScenarios = <String, List<String>>{
  'all': <String>[
    'calls',
    'sort',
    'math',
    'constructs',
    'nextvar',
    'parse-calls',
    'parse-math',
    'legacy-deserialize-calls',
    'string-sub',
    'string-unpack',
    'lua-string-latin1',
    'binary-format-mixed',
  ],
  'interpreter-all': <String>[
    'calls',
    'sort',
    'math',
    'constructs',
    'nextvar',
  ],
  'parse-all': <String>[
    'parse-calls',
    'parse-sort',
    'parse-math',
    'parse-constructs',
    'parse-nextvar',
  ],
  'legacy-all': <String>[
    'legacy-deserialize-calls',
    'legacy-deserialize-math',
  ],
  'string-all': <String>[
    'lua-string-latin1',
    'lua-string-slice',
    'string-sub',
    'string-byte',
    'string-unpack',
  ],
  'binary-format-all': <String>[
    'binary-format-pack',
    'binary-format-unpack',
    'binary-format-mixed',
  ],
};

final _leafScenarios = <String>{
  'calls',
  'sort',
  'math',
  'constructs',
  'nextvar',
  'parse-calls',
  'parse-sort',
  'parse-math',
  'parse-constructs',
  'parse-nextvar',
  'legacy-deserialize-calls',
  'legacy-deserialize-math',
  'lua-string-latin1',
  'lua-string-slice',
  'string-sub',
  'string-byte',
  'string-unpack',
  'binary-format-pack',
  'binary-format-unpack',
  'binary-format-mixed',
};

final List<String> _scenarioNames =
    (<String>{..._groupScenarios.keys, ..._leafScenarios}).toList()..sort();

final class _BenchOptions {
  const _BenchOptions({
    required this.scenarioName,
    required this.engineMode,
    required this.warmup,
    required this.repeat,
    required this.soft,
    required this.port,
    required this.parserProfile,
    required this.parserLint,
    required this.profileTop,
  });

  final String scenarioName;
  final EngineMode engineMode;
  final int warmup;
  final int repeat;
  final bool soft;
  final bool port;
  final bool parserProfile;
  final bool parserLint;
  final int profileTop;
}

typedef _ScenarioRunner = Future<void> Function(_BenchContext context);

final class _ParserProfileSpec {
  const _ParserProfileSpec({
    required this.name,
    required this.input,
    required this.sourceName,
  });

  final String name;
  final String input;
  final String sourceName;
}

final class _BenchScenario {
  const _BenchScenario({
    required this.name,
    required this.run,
    this.workUnits,
    this.workLabel,
    this.parserProfile,
  });

  final String name;
  final _ScenarioRunner run;
  final int? workUnits;
  final String? workLabel;
  final _ParserProfileSpec? parserProfile;
}

final class _BenchContext {
  _BenchContext({
    required this.options,
    required this.packageRoot,
  });

  final _BenchOptions options;
  final String packageRoot;
  final Map<String, _LoadedScript> _scripts = <String, _LoadedScript>{};

  Future<_LoadedScript> script(String name) async {
    final existing = _scripts[name];
    if (existing != null) {
      return existing;
    }
    final scriptPath = path.join(packageRoot, 'luascripts', 'test', '$name.lua');
    if (!await fs.fileExists(scriptPath)) {
      throw ArgumentError.value(name, 'scenario', 'Unknown script scenario');
    }
    final source = await fs.readFileAsString(scriptPath);
    if (source == null) {
      throw StateError('Could not read script scenario at $scriptPath');
    }
    final loaded = _LoadedScript(name: name, path: scriptPath, source: source);
    _scripts[name] = loaded;
    return loaded;
  }
}

final class _LoadedScript {
  const _LoadedScript({
    required this.name,
    required this.path,
    required this.source,
  });

  final String name;
  final String path;
  final String source;
}

final class _ScenarioStats {
  const _ScenarioStats({
    required this.name,
    required this.samplesMs,
    required this.rssBytes,
    this.workUnits,
    this.workLabel,
  });

  final String name;
  final List<double> samplesMs;
  final int rssBytes;
  final int? workUnits;
  final String? workLabel;

  double get minMs => samplesMs.reduce(math.min);

  double get maxMs => samplesMs.reduce(math.max);

  double get meanMs =>
      samplesMs.reduce((left, right) => left + right) / samplesMs.length;

  double get medianMs {
    final sorted = List<double>.from(samplesMs)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double? get unitsPerSecond {
    final units = workUnits;
    if (units == null || meanMs <= 0) {
      return null;
    }
    return units / (meanMs / 1000.0);
  }
}

final class _PetitParserFrame {
  const _PetitParserFrame({
    required this.parserName,
    required this.count,
    required this.elapsedMicros,
  });

  final String parserName;
  final int count;
  final int elapsedMicros;
}

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'scenario',
      abbr: 's',
      help: 'Scenario or scenario group to benchmark.',
      allowed: _scenarioNames,
      defaultsTo: _defaultScenario,
    )
    ..addOption(
      'engine',
      abbr: 'e',
      help: 'Execution engine for interpreter scenarios.',
      allowed: const <String>['ast', 'ir'],
      defaultsTo: 'ast',
    )
    ..addOption(
      'warmup',
      help: 'Warmup iterations before measured runs.',
      defaultsTo: '1',
    )
    ..addOption(
      'repeat',
      help: 'Measured iterations to run.',
      defaultsTo: '5',
    )
    ..addFlag(
      'soft',
      help: 'Enable _soft mode for Lua script scenarios.',
      defaultsTo: true,
    )
    ..addFlag(
      'port',
      help: 'Enable _port mode for Lua script scenarios.',
      defaultsTo: true,
    )
    ..addFlag(
      'parser-profile',
      help: 'Run petitparser profile() after timing parse scenarios.',
      defaultsTo: false,
    )
    ..addFlag(
      'parser-lint',
      help: 'Run petitparser linter() after timing parse scenarios.',
      defaultsTo: false,
    )
    ..addOption(
      'profile-top',
      help: 'Top parser frames to print for parser profiling.',
      defaultsTo: '15',
    )
    ..addFlag('help', abbr: 'h', help: 'Print usage.', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    io_abs.stdout.writeln('Standalone benchmark harness for lualike');
    io_abs.stdout.writeln(parser.usage);
    return;
  }

  final options = _BenchOptions(
    scenarioName: parsed['scenario'] as String,
    engineMode: switch (parsed['engine'] as String) {
      'ir' => EngineMode.ir,
      _ => EngineMode.ast,
    },
    warmup: int.parse(parsed['warmup'] as String),
    repeat: int.parse(parsed['repeat'] as String),
    soft: parsed['soft'] as bool,
    port: parsed['port'] as bool,
    parserProfile: parsed['parser-profile'] as bool,
    parserLint: parsed['parser-lint'] as bool,
    profileTop: int.parse(parsed['profile-top'] as String),
  );

  LuaLikeConfig().defaultEngineMode = options.engineMode;
  LuaLikeConfig().dumpIr = false;

  final packageRoot = await _findPackageRoot();
  final context = _BenchContext(options: options, packageRoot: packageRoot);
  final scenarios = await _resolveScenarios(context, options.scenarioName);

  io_abs.stdout.writeln(
    'Benchmarking ${scenarios.map((scenario) => scenario.name).join(', ')} '
    'on ${options.engineMode.name} engine',
  );
  io_abs.stdout.writeln(
    'warmup=${options.warmup} repeat=${options.repeat} '
    'soft=${options.soft} port=${options.port}',
  );
  io_abs.stdout.writeln('');

  final stats = <_ScenarioStats>[];
  for (final scenario in scenarios) {
    final result = await _runScenario(context, scenario);
    stats.add(result);
    _printScenarioStats(result);
    if (options.parserProfile && scenario.parserProfile != null) {
      _runPetitParserProfile(scenario.parserProfile!, top: options.profileTop);
    }
    if (options.parserLint && scenario.parserProfile != null) {
      _runPetitParserLint(scenario.parserProfile!);
    }
  }

  _printSummary(stats);
}

Future<_ScenarioStats> _runScenario(
  _BenchContext context,
  _BenchScenario scenario,
) async {
  for (var i = 0; i < context.options.warmup; i++) {
    await scenario.run(context);
  }

  final samplesMs = <double>[];
  for (var i = 0; i < context.options.repeat; i++) {
    final stopwatch = Stopwatch()..start();
    await scenario.run(context);
    stopwatch.stop();
    samplesMs.add(
      stopwatch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    );
  }

  return _ScenarioStats(
    name: scenario.name,
    samplesMs: samplesMs,
    rssBytes: platform.currentRssBytes,
    workUnits: scenario.workUnits,
    workLabel: scenario.workLabel,
  );
}

void _printScenarioStats(_ScenarioStats stats) {
  final throughput = stats.unitsPerSecond;
  io_abs.stdout.writeln(
    '${stats.name}: '
    'mean ${stats.meanMs.toStringAsFixed(2)} ms, '
    'median ${stats.medianMs.toStringAsFixed(2)} ms, '
    'min ${stats.minMs.toStringAsFixed(2)} ms, '
    'max ${stats.maxMs.toStringAsFixed(2)} ms '
    '(rss ${(stats.rssBytes / (1024 * 1024)).toStringAsFixed(1)} MiB)',
  );
  if (throughput != null) {
    io_abs.stdout.writeln(
      '  throughput: ${throughput.toStringAsFixed(0)} '
      '${stats.workLabel ?? 'units'}/s',
    );
  }
}

void _printSummary(List<_ScenarioStats> stats) {
  if (stats.isEmpty) {
    return;
  }
  final sorted = List<_ScenarioStats>.from(stats)
    ..sort((left, right) => right.meanMs.compareTo(left.meanMs));
  io_abs.stdout.writeln('');
  io_abs.stdout.writeln('Summary (slowest first)');
  for (final entry in sorted) {
    io_abs.stdout.writeln(
      '  ${entry.name.padRight(26)} '
      'mean ${entry.meanMs.toStringAsFixed(2).padLeft(8)} ms  '
      'median ${entry.medianMs.toStringAsFixed(2).padLeft(8)} ms',
    );
  }
}

Future<List<_BenchScenario>> _resolveScenarios(
  _BenchContext context,
  String requested,
) async {
  final names = _groupScenarios[requested] ?? <String>[requested];
  final scenarios = <_BenchScenario>[];
  for (final name in names) {
    scenarios.add(await _buildScenario(context, name));
  }
  return scenarios;
}

Future<_BenchScenario> _buildScenario(
  _BenchContext context,
  String name,
) async {
  return switch (name) {
    'calls' || 'sort' || 'math' || 'constructs' || 'nextvar' =>
      _scriptExecuteScenario(name),
    'parse-calls' => _scriptParseScenario(await context.script('calls')),
    'parse-sort' => _scriptParseScenario(await context.script('sort')),
    'parse-math' => _scriptParseScenario(await context.script('math')),
    'parse-constructs' =>
      _scriptParseScenario(await context.script('constructs')),
    'parse-nextvar' => _scriptParseScenario(await context.script('nextvar')),
    'legacy-deserialize-calls' =>
      _legacyDeserializeScenario(await context.script('calls')),
    'legacy-deserialize-math' =>
      _legacyDeserializeScenario(await context.script('math')),
    'lua-string-latin1' => _luaStringLatin1Scenario(),
    'lua-string-slice' => _luaStringSliceScenario(),
    'string-sub' => _stringLuaScenario(
      name: 'string-sub',
      workUnits: 25000,
      workLabel: 'sub calls',
      source: '''
local s = string.rep("abcd", 1024)
local n = 0
for i = 1, 25000 do
  n = n + #string.sub(s, 2, 257)
end
assert(n > 0)
''',
    ),
    'string-byte' => _stringLuaScenario(
      name: 'string-byte',
      workUnits: 30000,
      workLabel: 'byte calls',
      source: '''
local s = string.rep("abcd", 1024)
local n = 0
for i = 1, 30000 do
  local a, b, c, d = string.byte(s, 1, 4)
  n = n + a + b + c + d
end
assert(n > 0)
''',
    ),
    'string-unpack' => _stringLuaScenario(
      name: 'string-unpack',
      workUnits: 25000,
      workLabel: 'unpack calls',
      source: '''
local fmt = "<I4I4I4I4"
local s = string.pack(fmt, 1, 2, 3, 4)
local n = 0
for i = 1, 25000 do
  local a, b, c, d = string.unpack(fmt, s)
  n = n + a + b + c + d
end
assert(n > 0)
''',
    ),
    'binary-format-pack' => _binaryFormatScenario(
      name: 'binary-format-pack',
      format: '<I4I4I4I4',
      workUnits: 40000,
    ),
    'binary-format-unpack' => _binaryFormatScenario(
      name: 'binary-format-unpack',
      format: '<i8I4c16z',
      workUnits: 40000,
    ),
    'binary-format-mixed' => _binaryFormatScenario(
      name: 'binary-format-mixed',
      format: '<!8I2I4I8c32zxxXf',
      workUnits: 40000,
    ),
    _ => throw ArgumentError.value(name, 'scenario', 'Unknown benchmark'),
  };
}

_BenchScenario _scriptExecuteScenario(String name) {
  return _BenchScenario(
    name: name,
    run: (context) async {
      final loaded = await context.script(name);
      final lua = LuaLike();
      final source = StringBuffer()
        ..writeln(context.options.port ? '_port = true' : '_port = false')
        ..writeln(context.options.soft ? '_soft = true' : '_soft = false')
        ..writeln("package.path = 'luascripts/test/?.lua;' .. package.path")
        ..write(loaded.source);
      await lua.execute(source.toString(), scriptPath: loaded.path);
    },
  );
}

_BenchScenario _scriptParseScenario(_LoadedScript script) {
  return _BenchScenario(
    name: 'parse-${script.name}',
    workUnits: script.source.length,
    workLabel: 'chars',
    parserProfile: _ParserProfileSpec(
      name: 'parse-${script.name}',
      input: script.source,
      sourceName: script.path,
    ),
    run: (_) async {
      parse_api.parse(script.source, url: script.path);
    },
  );
}

_BenchScenario _legacyDeserializeScenario(_LoadedScript script) {
  final chunk = LegacyAstChunkTransport.serializeSourceWithNameAsLuaString(
    script.source,
    sourceName: script.path,
  );
  return _BenchScenario(
    name: 'legacy-deserialize-${script.name}',
    workUnits: chunk.length,
    workLabel: 'bytes',
    run: (_) async {
      LegacyAstChunkTransport.deserializeChunkFromLuaString(chunk);
    },
  );
}

_BenchScenario _luaStringLatin1Scenario() {
  final bytes = Uint8List.fromList(
    List<int>.generate(4096, (index) => index & 0xFF),
  );
  final luaString = LuaString(bytes);
  return _BenchScenario(
    name: 'lua-string-latin1',
    workUnits: 2500 * luaString.length,
    workLabel: 'bytes',
    run: (_) async {
      var total = 0;
      for (var i = 0; i < 2500; i++) {
        total += luaString.toLatin1String().length;
      }
      if (total == 0) {
        throw StateError('unexpected zero total');
      }
    },
  );
}

_BenchScenario _luaStringSliceScenario() {
  final bytes = Uint8List.fromList(
    List<int>.generate(8192, (index) => index & 0xFF),
  );
  final luaString = LuaString(bytes);
  return _BenchScenario(
    name: 'lua-string-slice',
    workUnits: 20000,
    workLabel: 'slice calls',
    run: (_) async {
      var total = 0;
      for (var i = 0; i < 20000; i++) {
        total += luaString.slice(10, 266).length;
      }
      if (total == 0) {
        throw StateError('unexpected zero total');
      }
    },
  );
}

_BenchScenario _stringLuaScenario({
  required String name,
  required String source,
  required int workUnits,
  required String workLabel,
}) {
  return _BenchScenario(
    name: name,
    workUnits: workUnits,
    workLabel: workLabel,
    run: (_) async {
      final lua = LuaLike();
      await lua.execute(source, scriptPath: '<bench:$name>');
    },
  );
}

_BenchScenario _binaryFormatScenario({
  required String name,
  required String format,
  required int workUnits,
}) {
  return _BenchScenario(
    name: name,
    workUnits: workUnits,
    workLabel: 'format parses',
    run: (_) async {
      var total = 0;
      for (var i = 0; i < workUnits; i++) {
        total += BinaryFormatParser.parse(format).length;
      }
      if (total == 0) {
        throw StateError('unexpected zero total');
      }
    },
  );
}

void _runPetitParserProfile(_ParserProfileSpec spec, {required int top}) {
  final sourceFile = SourceFile.fromString(
    spec.input,
    url: Uri.file(spec.sourceName),
  );
  final definition = lua_parser.LuaGrammarDefinition(sourceFile);
  final parser = definition.build();
  final frames = <_PetitParserFrame>[];
  final profiled = pp_debug.profile(
    parser,
    output: (frame) {
      frames.add(
        _PetitParserFrame(
          parserName: frame.parser.toString(),
          count: frame.count,
          elapsedMicros: frame.elapsed.inMicroseconds,
        ),
      );
    },
  );

  profiled.parse(spec.input);
  if (frames.isEmpty) {
    io_abs.stdout.writeln('No petitparser profile frames captured.');
    return;
  }

  final byTime = List<_PetitParserFrame>.from(frames)
    ..sort((left, right) => right.elapsedMicros.compareTo(left.elapsedMicros));
  final byCount = List<_PetitParserFrame>.from(frames)
    ..sort((left, right) => right.count.compareTo(left.count));

  io_abs.stdout.writeln('');
  io_abs.stdout.writeln('PetitParser profile: ${spec.name}');
  io_abs.stdout.writeln('Top $top by time');
  for (var i = 0; i < top && i < byTime.length; i++) {
    final frame = byTime[i];
    io_abs.stdout.writeln(
      '  ${frame.elapsedMicros.toString().padLeft(10)} us  '
      '${frame.count.toString().padLeft(8)}  ${frame.parserName}',
    );
  }

  io_abs.stdout.writeln('Top $top by activation count');
  for (var i = 0; i < top && i < byCount.length; i++) {
    final frame = byCount[i];
    io_abs.stdout.writeln(
      '  ${frame.count.toString().padLeft(8)}  '
      '${frame.elapsedMicros.toString().padLeft(10)} us  ${frame.parserName}',
    );
  }
}

void _runPetitParserLint(_ParserProfileSpec spec) {
  final sourceFile = SourceFile.fromString(
    spec.input,
    url: Uri.file(spec.sourceName),
  );
  final definition = lua_parser.LuaGrammarDefinition(sourceFile);
  final parser = definition.build();
  final issues = pp_reflection.linter(parser);
  io_abs.stdout.writeln('');
  io_abs.stdout.writeln('PetitParser linter: ${spec.name}');
  if (issues.isEmpty) {
    io_abs.stdout.writeln('  No issues found.');
    return;
  }
  for (final issue in issues) {
    io_abs.stdout.writeln('  - $issue');
  }
}

Future<String> _findPackageRoot() async {
  final startPath = fs.getCurrentDirectory() ?? '.';
  var current = path.normalize(startPath);
  while (true) {
    final pubspec = path.join(current, 'pubspec.yaml');
    final luascripts = path.join(current, 'luascripts', 'test');
    if (await fs.fileExists(pubspec) && await fs.directoryExists(luascripts)) {
      return current;
    }

    final nestedPackage = path.join(current, 'pkgs', 'lualike');
    final nestedPubspec = path.join(nestedPackage, 'pubspec.yaml');
    final nestedLuascripts = path.join(nestedPackage, 'luascripts', 'test');
    if (await fs.fileExists(nestedPubspec) &&
        await fs.directoryExists(nestedLuascripts)) {
      return nestedPackage;
    }

    final parent = path.dirname(current);
    if (parent == current) {
      throw StateError(
        'Could not find pkgs/lualike package root from $startPath',
      );
    }
    current = parent;
  }
}
