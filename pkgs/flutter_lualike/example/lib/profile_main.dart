import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:lualike/lualike.dart';

const _workloadSource = r'''
function profile_workload(iterations)
  local total = 0
  local retained = {}

  local function accumulate(value)
    local boxed = {value = value, doubled = value * 2}
    return boxed.value + boxed.doubled
  end

  for i = 1, iterations do
    total = total + accumulate(i)
    retained[(i % 64) + 1] = {i, total, label = "item-" .. i}
  end

  return total + #retained
end
''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final harness = await _ProfileHarness.create();
  registerExtension('ext.lualike.runWorkload', harness.runExtension);
  runApp(_ProfileApp(harness: harness));
}

class _ProfileHarness {
  _ProfileHarness(this._lua);

  final LuaLike _lua;
  int completedRuns = 0;

  static Future<_ProfileHarness> create() async {
    final lua = await LuaLike.compile(
      _workloadSource,
      moduleName: 'profile_workload.lua',
    );
    return _ProfileHarness(lua);
  }

  Future<Map<String, Object?>> run({
    required int iterations,
    String scenario = 'steady-bytecode',
  }) async {
    final stopwatch = Stopwatch()..start();
    final result = switch (scenario) {
      'steady-bytecode' => await _lua.call('profile_workload', <Object?>[
        iterations,
      ]),
      'fresh-ast' => await executeCode(
        '$_workloadSource\nreturn profile_workload($iterations)',
        mode: EngineMode.ast,
        url: 'profile_workload_fresh_ast.lua',
      ),
      _ => throw ArgumentError.value(scenario, 'scenario'),
    };
    stopwatch.stop();
    completedRuns++;
    return <String, Object?>{
      'completedRuns': completedRuns,
      'elapsedMicros': stopwatch.elapsedMicroseconds,
      'iterations': iterations,
      'scenario': scenario,
      'result': result is Value ? result.unwrap() : result,
    };
  }

  Future<ServiceExtensionResponse> runExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    try {
      final iterations = int.parse(parameters['iterations'] ?? '10000');
      final scenario = parameters['scenario'] ?? 'steady-bytecode';
      if (iterations <= 0) {
        throw const FormatException('iterations must be positive');
      }
      return ServiceExtensionResponse.result(
        jsonEncode(await run(iterations: iterations, scenario: scenario)),
      );
    } catch (error, stackTrace) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        '$error\n$stackTrace',
      );
    }
  }
}

class _ProfileApp extends StatefulWidget {
  const _ProfileApp({required this.harness});

  final _ProfileHarness harness;

  @override
  State<_ProfileApp> createState() => _ProfileAppState();
}

class _ProfileAppState extends State<_ProfileApp> {
  String _status = 'Ready for an automated capture or a DevTools session.';
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _status = 'Running fixed workload…';
    });
    final result = await widget.harness.run(iterations: 10000);
    if (!mounted) return;
    setState(() {
      _running = false;
      _status =
          'Run ${result['completedRuns']} finished in '
          '${result['elapsedMicros']} µs.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LuaLike allocation profiler',
      home: Scaffold(
        appBar: AppBar(title: const Text('LuaLike allocation profiler')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _running ? null : _run,
                    child: const Text('Run 10,000 iterations'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
