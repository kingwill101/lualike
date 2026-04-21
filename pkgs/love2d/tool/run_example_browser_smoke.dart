import 'dart:io';

import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _browserRoot = 'example/assets/love_example_browser';
const String _browserEntry = '$_browserRoot/main.lua';
const String _examplesDir = '$_browserRoot/examples';

Future<void> main(List<String> args) async {
  final parsed = _SmokeRunnerArgs.parse(args);
  final files = _resolveExampleFiles(parsed.selection);

  if (files.isEmpty) {
    stderr.writeln('No matching example files found.');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Running ${files.length} example browser smoke test(s) '
    'with ${parsed.frames} frame(s) at dt=${parsed.dt}.',
  );

  final results = <_SmokeResult>[];
  for (final file in files) {
    final result = await _runExampleSmoke(
      file,
      frames: parsed.frames,
      dt: parsed.dt,
    );
    results.add(result);
    final status = result.passed ? 'PASS' : 'FAIL';
    stdout.writeln('$status ${result.exampleName}');
    if (!result.passed) {
      stdout.writeln(result.summary);
      if (parsed.verbose && result.details != null) {
        stdout.writeln(result.details);
      }
    }
  }

  final passed = results.where((result) => result.passed).length;
  final failed = results.length - passed;
  stdout.writeln('');
  stdout.writeln('Summary: $passed passed, $failed failed.');

  if (failed > 0 && !parsed.verbose) {
    stdout.writeln('');
    stdout.writeln('Failing examples:');
    for (final result in results.where((result) => !result.passed)) {
      stdout.writeln('${result.exampleName}: ${result.summary}');
    }
  }

  exitCode = failed == 0 ? 0 : 1;
}

List<FileSystemEntity> _resolveExampleFiles(List<String> selection) {
  final directory = Directory(_examplesDir);
  if (!directory.existsSync()) {
    throw StateError('Examples directory not found: $_examplesDir');
  }

  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.lua'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (selection.isEmpty) {
    return files;
  }

  final wanted = selection.map((item) => item.replaceAll('\\', '/')).toList();
  return files.where((file) {
    final basename = file.uri.pathSegments.last;
    final relative = file.path.replaceAll('\\', '/');
    return wanted.any((item) => basename == item || relative.endsWith(item));
  }).toList();
}

Future<_SmokeResult> _runExampleSmoke(
  FileSystemEntity file, {
  required int frames,
  required double dt,
}) async {
  final path = file.path.replaceAll('\\', '/');
  final exampleName = path.split('/').last;
  final runtime = LoveScriptRuntime(
    host: LoveHeadlessHost(),
    filesystemAdapter: LoveLualikeFilesystemAdapter(),
  );
  final filesystem = LoveFilesystemState.of(runtime.runtime);

  if (!filesystem.setSource(_browserEntry)) {
    return _SmokeResult.failed(
      exampleName: exampleName,
      summary: 'failed to set source root to $_browserEntry',
    );
  }

  final relative = 'examples/$exampleName';
  try {
    await runtime.execute('''
local loaded = assert(love.filesystem.load("$relative"))
loaded()
''', scriptPath: '=[example smoke bootstrap]');

    await runtime.callLoadIfDefined();

    for (var frame = 0; frame < frames; frame++) {
      await runtime.callUpdateIfDefined(dt);
      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined();
    }

    return _SmokeResult.passed(exampleName: exampleName);
  } catch (error, stackTrace) {
    final text = '$error';
    final summary = text.trim().split('\n').first;
    return _SmokeResult.failed(
      exampleName: exampleName,
      summary: summary,
      details: '$text\n$stackTrace',
    );
  }
}

final class _SmokeRunnerArgs {
  _SmokeRunnerArgs({
    required this.frames,
    required this.dt,
    required this.verbose,
    required this.selection,
  });

  final int frames;
  final double dt;
  final bool verbose;
  final List<String> selection;

  static _SmokeRunnerArgs parse(List<String> args) {
    var frames = 3;
    var dt = 1 / 60;
    var verbose = false;
    final selection = <String>[];

    for (final arg in args) {
      if (arg == '--verbose') {
        verbose = true;
        continue;
      }
      if (arg.startsWith('--frames=')) {
        frames = int.parse(arg.substring('--frames='.length));
        continue;
      }
      if (arg.startsWith('--dt=')) {
        dt = double.parse(arg.substring('--dt='.length));
        continue;
      }
      selection.add(arg);
    }

    return _SmokeRunnerArgs(
      frames: frames,
      dt: dt,
      verbose: verbose,
      selection: selection,
    );
  }
}

final class _SmokeResult {
  const _SmokeResult._({
    required this.exampleName,
    required this.passed,
    required this.summary,
    this.details,
  });

  final String exampleName;
  final bool passed;
  final String summary;
  final String? details;

  factory _SmokeResult.passed({required String exampleName}) {
    return _SmokeResult._(
      exampleName: exampleName,
      passed: true,
      summary: 'ok',
    );
  }

  factory _SmokeResult.failed({
    required String exampleName,
    required String summary,
    String? details,
  }) {
    return _SmokeResult._(
      exampleName: exampleName,
      passed: false,
      summary: summary,
      details: details,
    );
  }
}
