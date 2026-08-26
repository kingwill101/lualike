import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _serviceExtension = 'ext.lualike.runWorkload';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final outputFile = File(options.outputPath);
  await outputFile.parent.create(recursive: true);
  final flutterVersion = await _flutterVersion(options.flutterExecutable);

  final process = await Process.start(options.flutterExecutable, <String>[
    'run',
    '--profile',
    '--no-pub',
    '--disable-service-auth-codes',
    '--vm-service-port=0',
    '-d',
    options.device,
    '-t',
    options.target,
  ], workingDirectory: options.appDirectory);

  final serviceUri = Completer<Uri>();
  final outputSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        stdout.writeln(line);
        final match = RegExp(r'(http://127\.0\.0\.1:\d+/)').firstMatch(line);
        if (match != null && !serviceUri.isCompleted) {
          serviceUri.complete(Uri.parse(match.group(1)!));
        }
      });
  final errorSubscription = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stderr.writeln);

  VmService? service;
  try {
    final uri = await Future.any(<Future<Uri>>[
      serviceUri.future,
      process.exitCode.then<Uri>(
        (code) =>
            throw StateError(
              'Flutter exited with code $code before publishing a VM service URI',
            ),
      ),
    ]).timeout(const Duration(minutes: 3));
    service = await vmServiceConnectUri(_webSocketUri(uri).toString());
    final isolate = await _waitForExtension(service);
    final isolateId = isolate.id!;

    final measurements = <String, List<Map<String, Object?>>>{};
    for (final scenario in options.scenarios) {
      for (var index = 0; index < options.warmupRuns; index++) {
        await _runWorkload(service, isolateId, options.iterations, scenario);
      }
      final samples = <Map<String, Object?>>[];
      for (var index = 0; index < options.samples; index++) {
        await service.getAllocationProfile(isolateId, gc: true);
        final before = await service.getAllocationProfile(
          isolateId,
          reset: true,
        );
        final workload = await _runWorkload(
          service,
          isolateId,
          options.iterations,
          scenario,
        );
        final profile = await service.getAllocationProfile(isolateId);
        samples.add(<String, Object?>{
          'sample': index + 1,
          'workload': workload,
          'memory': profile.memoryUsage?.toJson(),
          'classes': _classDeltaRows(before, profile),
        });
      }
      measurements[scenario] = samples;
    }

    final report = <String, Object?>{
      'schemaVersion': 1,
      'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'flutterExecutable': options.flutterExecutable,
      'flutterVersion': flutterVersion,
      'device': options.device,
      'target': options.target,
      'profileMode': true,
      'warmupRuns': options.warmupRuns,
      'samples': options.samples,
      'iterationsPerSample': options.iterations,
      'scenarios': options.scenarios,
      'measurements': measurements,
      'summary': <String, Object?>{
        for (final entry in measurements.entries)
          entry.key: _summarize(entry.value),
      },
    };
    await outputFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln('Allocation report: ${outputFile.absolute.path}');
  } finally {
    await service?.dispose();
    process.kill(ProcessSignal.sigterm);
    await outputSubscription.cancel();
    await errorSubscription.cancel();
  }
}

Uri _webSocketUri(Uri serviceUri) =>
    serviceUri.replace(scheme: 'ws', path: '${serviceUri.path}ws');

Future<Map<String, Object?>> _flutterVersion(String executable) async {
  final result = await Process.run(executable, const <String>[
    '--version',
    '--machine',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Could not read Flutter version: ${result.stderr}');
  }
  return (jsonDecode(result.stdout as String) as Map).cast<String, Object?>();
}

Future<IsolateRef> _waitForExtension(VmService service) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final vm = await service.getVM();
    for (final isolateRef in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(isolateRef.id!);
      if (isolate.extensionRPCs?.contains(_serviceExtension) ?? false) {
        return isolateRef;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException('$_serviceExtension was not registered');
}

Future<Map<String, Object?>> _runWorkload(
  VmService service,
  String isolateId,
  int iterations,
  String scenario,
) async {
  final response = await service.callServiceExtension(
    _serviceExtension,
    isolateId: isolateId,
    args: <String, String>{'iterations': '$iterations', 'scenario': scenario},
  );
  return (response.json ?? const <String, Object?>{}).cast<String, Object?>();
}

List<Map<String, Object?>> _classDeltaRows(
  AllocationProfile before,
  AllocationProfile after,
) {
  String key(ClassHeapStats member) =>
      '${member.classRef?.library?.uri}::${member.classRef?.name}';

  final starting = <String, ClassHeapStats>{
    for (final member in before.members ?? const <ClassHeapStats>[])
      key(member): member,
  };
  final rows =
      (after.members ?? const <ClassHeapStats>[])
          .map((member) {
            final initial = starting[key(member)];
            return <String, Object?>{
              'name': member.classRef?.name,
              'library': member.classRef?.library?.uri,
              'instancesAllocated':
                  (member.instancesAccumulated ?? 0) -
                  (initial?.instancesAccumulated ?? 0),
              'bytesAllocated':
                  (member.accumulatedSize ?? 0) -
                  (initial?.accumulatedSize ?? 0),
              'instancesCurrent': member.instancesCurrent,
              'bytesCurrent': member.bytesCurrent,
            };
          })
          .where((row) => (row['instancesAllocated']! as int) > 0)
          .toList()
        ..sort(
          (a, b) => (b['bytesAllocated'] as int).compareTo(
            a['bytesAllocated'] as int,
          ),
        );
  return rows;
}

Map<String, Object?> _summarize(List<Map<String, Object?>> samples) {
  final names = <String>{'Value', 'Environment'};
  final summary = <String, Object?>{};
  for (final name in names) {
    final counts = <int>[];
    final bytes = <int>[];
    for (final sample in samples) {
      final classes = sample['classes']! as List<Map<String, Object?>>;
      final matches = classes.where((row) => row['name'] == name);
      counts.add(
        matches.fold(
          0,
          (sum, row) => sum + (row['instancesAllocated']! as int),
        ),
      );
      bytes.add(
        matches.fold(0, (sum, row) => sum + (row['bytesAllocated']! as int)),
      );
    }
    counts.sort();
    bytes.sort();
    summary[name] = <String, Object?>{
      'instancesPerSample': counts,
      'medianInstances': counts[counts.length ~/ 2],
      'bytesPerSample': bytes,
      'medianBytes': bytes[bytes.length ~/ 2],
    };
  }
  return summary;
}

class _Options {
  const _Options({
    required this.flutterExecutable,
    required this.appDirectory,
    required this.target,
    required this.device,
    required this.outputPath,
    required this.warmupRuns,
    required this.samples,
    required this.iterations,
    required this.scenarios,
  });

  final String flutterExecutable;
  final String appDirectory;
  final String target;
  final String device;
  final String outputPath;
  final int warmupRuns;
  final int samples;
  final int iterations;
  final List<String> scenarios;

  static _Options parse(List<String> arguments) {
    String read(String name, String fallback) {
      final prefix = '--$name=';
      final match = arguments.where((argument) => argument.startsWith(prefix));
      return match.isEmpty ? fallback : match.last.substring(prefix.length);
    }

    final options = _Options(
      flutterExecutable: read('flutter', 'flutter'),
      appDirectory: read('app-dir', '.'),
      target: read('target', 'lib/profile_main.dart'),
      device: read('device', 'macos'),
      outputPath: read('output', 'benchmark/flutter_allocations/latest.json'),
      warmupRuns: int.parse(read('warmup-runs', '2')),
      samples: int.parse(read('samples', '5')),
      iterations: int.parse(read('iterations', '10000')),
      scenarios: read('scenarios', 'steady-bytecode,fresh-ast').split(','),
    );
    if (options.warmupRuns < 0 ||
        options.samples <= 0 ||
        options.iterations <= 0 ||
        options.scenarios.any(
          (scenario) =>
              !const <String>{
                'steady-bytecode',
                'fresh-ast',
              }.contains(scenario),
        )) {
      throw const FormatException('run counts and iterations are invalid');
    }
    return options;
  }
}
