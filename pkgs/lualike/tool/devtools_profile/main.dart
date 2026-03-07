import 'dart:developer' as developer;
import 'dart:io';

import 'package:args/args.dart';
import 'package:lualike/lualike.dart';
import 'package:path/path.dart' as path;

const _scenarioNames = <String>{
  'constructs',
  'constructs-short-circuit',
  'calls',
  'gc',
  'math',
  'sort',
  'all',
};

const _engineNames = <String>{'ast', 'ir'};

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'scenario',
      abbr: 's',
      help: 'Scenario to run for profiling.',
      allowed: _scenarioNames.toList()..sort(),
      defaultsTo: 'constructs-short-circuit',
    )
    ..addOption(
      'engine',
      abbr: 'e',
      help: 'Execution engine.',
      allowed: _engineNames.toList(),
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
      defaultsTo: '1',
    )
    ..addOption(
      'wait-seconds',
      help: 'Optional delay before running to let DevTools attach.',
      defaultsTo: '5',
    )
    ..addOption(
      'keep-alive-seconds',
      help: 'Optional delay after running so DevTools can inspect state.',
      defaultsTo: '0',
    )
    ..addOption(
      'construct-level',
      help: 'Level used by constructs-short-circuit scenario.',
      defaultsTo: '3',
    )
    ..addFlag(
      'soft',
      help: 'Enable _soft mode for Lua test scenarios.',
      defaultsTo: true,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Print usage.',
      negatable: false,
    );

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('DevTools profiling harness for lualike');
    stdout.writeln(parser.usage);
    return;
  }

  final scenarioName = parsed['scenario'] as String;
  final engineName = parsed['engine'] as String;
  final warmup = int.parse(parsed['warmup'] as String);
  final repeat = int.parse(parsed['repeat'] as String);
  final waitSeconds = int.parse(parsed['wait-seconds'] as String);
  final keepAliveSeconds = int.parse(parsed['keep-alive-seconds'] as String);
  final constructLevel = int.parse(parsed['construct-level'] as String);
  final soft = parsed['soft'] as bool;

  final packageRoot = _findPackageRoot();
  final engineMode = switch (engineName) {
    'ir' => EngineMode.ir,
    _ => EngineMode.ast,
  };

  LuaLikeConfig().defaultEngineMode = engineMode;
  LuaLikeConfig().dumpIr = false;

  final profileTask = developer.TimelineTask(filterKey: 'lualike.profile');
  profileTask.start('lualike-profile', arguments: {
    'scenario': scenarioName,
    'engine': engineName,
    'warmup': warmup,
    'repeat': repeat,
    'soft': soft,
  });

  try {
    await _printServiceInfo(waitSeconds);

    final scenarios = switch (scenarioName) {
      'all' => [
        _makeScriptScenario(packageRoot, 'calls', soft: soft),
        _makeScriptScenario(packageRoot, 'sort', soft: soft),
        _makeScriptScenario(packageRoot, 'math', soft: soft),
        _makeScriptScenario(packageRoot, 'constructs', soft: soft),
      ],
      'constructs-short-circuit' => [
        _constructsShortCircuitScenario(level: constructLevel),
      ],
      _ => [_makeScriptScenario(packageRoot, scenarioName, soft: soft)],
    };

    stdout.writeln(
      'Profiling ${scenarios.map((scenario) => scenario.name).join(', ')} '
      'on $engineName engine',
    );

    final runTask = developer.TimelineTask(filterKey: 'lualike.profile');
    runTask.start('profile-runs');
    try {
      for (var i = 0; i < warmup; i++) {
        await _runScenarioSet(
          scenarios,
          iterationLabel: 'warmup-${i + 1}',
          measured: false,
        );
      }

      for (var i = 0; i < repeat; i++) {
        await _runScenarioSet(
          scenarios,
          iterationLabel: 'run-${i + 1}',
          measured: true,
        );
      }
    } finally {
      runTask.finish();
    }

    if (keepAliveSeconds > 0) {
      stdout.writeln(
        'Keeping process alive for $keepAliveSeconds seconds for inspection...',
      );
      await Future<void>.delayed(Duration(seconds: keepAliveSeconds));
    }
  } finally {
    profileTask.finish(arguments: {'rss': ProcessInfo.currentRss});
  }
}

Future<void> _printServiceInfo(int waitSeconds) async {
  final info = await developer.Service.getInfo();
  final serviceUri = info.serverUri;
  if (serviceUri != null) {
    stdout.writeln('VM service: $serviceUri');
  } else {
    stdout.writeln(
      'VM service not active. Run with `dart run --observe tool/devtools_profile/main.dart ...`.',
    );
  }

  if (waitSeconds > 0) {
    stdout.writeln('Waiting $waitSeconds seconds before starting...');
    await Future<void>.delayed(Duration(seconds: waitSeconds));
  }
}

Future<void> _runScenarioSet(
  List<_ProfileScenario> scenarios, {
  required String iterationLabel,
  required bool measured,
}) async {
  stdout.writeln('');
  stdout.writeln('[$iterationLabel] ${measured ? 'measured' : 'warmup'}');

  for (final scenario in scenarios) {
    final task = developer.TimelineTask(filterKey: 'lualike.profile');
    final stopwatch = Stopwatch()..start();
    task.start('scenario:${scenario.name}', arguments: {
      'iteration': iterationLabel,
      'measured': measured,
    });
    try {
      stdout.writeln('  -> ${scenario.name}');
      await scenario.run();
    } finally {
      stopwatch.stop();
      final elapsedMs =
          stopwatch.elapsedMicroseconds / Duration.microsecondsPerMillisecond;
      stdout.writeln(
        '     ${elapsedMs.toStringAsFixed(2)} ms '
        '(rss ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1)} MiB)',
      );
      task.finish(arguments: {
        'iteration': iterationLabel,
        'measured': measured,
        'elapsed_ms': elapsedMs,
        'rss': ProcessInfo.currentRss,
      });
    }
  }
}

Directory _findPackageRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(path.join(current.path, 'pubspec.yaml'));
    final luascripts = Directory(path.join(current.path, 'luascripts', 'test'));
    if (pubspec.existsSync() && luascripts.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not find pkgs/lualike package root from ${Directory.current.path}');
    }
    current = parent;
  }
}

_ProfileScenario _makeScriptScenario(
  Directory packageRoot,
  String name, {
  required bool soft,
}) {
  final scriptPath = path.join(packageRoot.path, 'luascripts', 'test', '$name.lua');
  final scriptFile = File(scriptPath);
  if (!scriptFile.existsSync()) {
    throw ArgumentError.value(name, 'scenario', 'Unknown script scenario');
  }

  return _ProfileScenario(
    name,
    () async {
      final lua = LuaLike();
      _installTimelineHelpers(lua);
      final source = StringBuffer();
      if (soft) {
        source.writeln('_soft = true');
      }
      source.write(await scriptFile.readAsString());
      await lua.execute(source.toString(), scriptPath: scriptPath);
    },
  );
}

_ProfileScenario _constructsShortCircuitScenario({required int level}) {
  final source = '''
_soft = true
_ENV.GLOB1 = 0

local basiccases = {
  {"nil", nil},
  {"F", false},
  {"true", true},
  {"10", 10},
  {"(0==_ENV.GLOB1)", 0 == _ENV.GLOB1},
}

local prog = [[
  local F <const> = false
  if %s then IX = true end
  return %s
]]

local binops <const> = {
  {" and ", function (a,b) if not a then return a else return b end end},
  {" or ", function (a,b) if a then return a else return b end end},
}

local cases <const> = {}

local function createcases (n)
  local res = {}
  for i = 1, n - 1 do
    for _, v1 in ipairs(cases[i]) do
      for _, v2 in ipairs(cases[n - i]) do
        for _, op in ipairs(binops) do
            local t = {
              "(" .. v1[1] .. op[1] .. v2[1] .. ")",
              op[2](v1[2], v2[2])
            }
            res[#res + 1] = t
            res[#res + 1] = {"not" .. t[1], not t[2]}
        end
      end
    end
  end
  return res
end

cases[1] = basiccases
dart_mark("constructs:createcases:start")
for i = 2, $level do
  cases[i] = createcases(i)
end
dart_mark("constructs:createcases:end")

local i = 0
dart_mark("constructs:loadloop:start")
for n = 1, $level do
  for _, v in pairs(cases[n]) do
    local s = v[1]
    local p = load(string.format(prog, s, s), "")
    IX = false
    assert(p() == v[2] and IX == not not v[2])
    i = i + 1
  end
end
dart_mark("constructs:loadloop:end")
''';

  return _ProfileScenario(
    'constructs-short-circuit',
    () async {
      final lua = LuaLike();
      _installTimelineHelpers(lua);
      await lua.execute(source, scriptPath: '<profile:constructs-short-circuit>');
    },
  );
}

void _installTimelineHelpers(LuaLike lua) {
  lua.expose('dart_mark', (List<Object?> args) {
    final rawLabel = args.isEmpty
        ? null
        : (args.first is Value ? (args.first as Value).raw : args.first);
    final label = rawLabel?.toString() ?? 'unnamed';
    developer.Timeline.instantSync(
      label,
      arguments: {'rss': ProcessInfo.currentRss},
    );
    return null;
  });
}

final class _ProfileScenario {
  _ProfileScenario(this.name, this.run);

  final String name;
  final Future<void> Function() run;
}
