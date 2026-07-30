// Headless multi-frame smoke for every Game Center demo.
//
// Run from the love2d package root:
//   cd pkgs/love2d
//   dart run tool/smoke_game_center_demos.dart
//   dart run tool/smoke_game_center_demos.dart --frames=30 --only=Snake
//   dart run tool/smoke_game_center_demos.dart --mode=ast
//
// Exits non-zero if any demo fails to load or throws during update/draw.
// Does not require Flutter asset-bundle packaging (reads example/assets/ on disk).

import 'dart:io';

import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:path/path.dart' as p;

/// Mirrors [kDemoEntries] entry assets without pulling Flutter widgets.
const _demos = <({String title, String entryAsset})>[
  (title: 'Modern Pong', entryAsset: 'assets/modern_pong/main.lua'),
  (
    title: 'LOVE Example Browser',
    entryAsset: 'assets/love_example_browser/main.lua',
  ),
  (title: 'Pocket Bomber', entryAsset: 'assets/pocket_bomber/main.lua'),
  (title: 'Shader Explorer', entryAsset: 'assets/shader_explorer/main.lua'),
  (title: 'Snake 3310', entryAsset: 'assets/snake/main.lua'),
  (title: 'Space Invaders', entryAsset: 'assets/space_invaders/main.lua'),
  (title: 'Relic Breach', entryAsset: 'assets/relic_breach/main.lua'),
];

Future<void> main(List<String> args) async {
  var frames = 12;
  var mode = EngineMode.luaBytecode;
  String? only;
  for (final arg in args) {
    if (arg.startsWith('--frames=')) {
      frames = int.parse(arg.substring('--frames='.length));
    } else if (arg.startsWith('--mode=')) {
      final raw = arg.substring('--mode='.length);
      mode = switch (raw) {
        'ast' => EngineMode.ast,
        'ir' => EngineMode.ir,
        'bytecode' || 'luaBytecode' => EngineMode.luaBytecode,
        _ => throw FormatException('Unknown --mode=$raw (ast|bytecode|ir)'),
      };
    } else if (arg.startsWith('--only=')) {
      only = arg.substring('--only='.length).toLowerCase();
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'Usage: dart run tool/smoke_game_center_demos.dart '
        '[--frames=N] [--mode=bytecode|ast|ir] [--only=name]',
      );
      return;
    }
  }

  final packageRoot = _love2dPackageRoot();
  final exampleAssets = p.join(packageRoot, 'example', 'assets');
  if (!Directory(exampleAssets).existsSync()) {
    stderr.writeln('Missing $exampleAssets — run from monorepo checkout.');
    exitCode = 2;
    return;
  }

  // Resolve relative setSource paths from the love2d package root.
  Directory.current = packageRoot;

  stdout.writeln(
    'Smoke demos mode=$mode frames=$frames root=$packageRoot',
  );

  var failed = 0;
  for (final demo in _demos) {
    if (only != null && !demo.title.toLowerCase().contains(only)) {
      continue;
    }
    final diskEntry = 'example/${demo.entryAsset}';
    final sw = Stopwatch()..start();
    stdout.write('• ${demo.title.padRight(22)} ... ');
    try {
      await _bootDemo(
        title: demo.title,
        diskEntry: diskEntry,
        mode: mode,
        frames: frames,
      ).timeout(const Duration(minutes: 2));
      stdout.writeln('OK (${sw.elapsedMilliseconds}ms)');
    } catch (e, st) {
      failed++;
      stdout.writeln('FAIL (${sw.elapsedMilliseconds}ms)');
      stderr.writeln('  $e');
      final lines = st.toString().split('\n').take(8).join('\n');
      stderr.writeln(lines);
    }
  }

  if (failed > 0) {
    stderr.writeln('\n$failed demo(s) failed.');
    exitCode = 1;
  } else {
    stdout.writeln('\nAll selected demos passed.');
  }
}

Future<void> _bootDemo({
  required String title,
  required String diskEntry,
  required EngineMode mode,
  required int frames,
}) async {
  final host = LoveHeadlessHost();
  final runtime = LoveScriptRuntime(
    engineMode: mode,
    host: host,
    filesystemAdapter: LoveLualikeFilesystemAdapter(),
  );
  final filesystem = LoveFilesystemState.of(runtime.runtime);
  if (!filesystem.setSource(diskEntry)) {
    throw StateError('setSource failed for $diskEntry');
  }
  await runtime.loadConfIfPresent();
  await runtime.execute(
    'assert(love.filesystem.load("main.lua"))()',
    scriptPath: '=[$title bootstrap]',
  );
  await runtime.callLoadIfDefined();
  for (var i = 0; i < frames; i++) {
    await runtime.callUpdateIfDefined(1 / 60);
    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    await runtime.callDrawIfDefined();
  }
}

String _love2dPackageRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: love2d')) {
      return dir.path;
    }
    final nested = Directory(p.join(dir.path, 'pkgs', 'love2d'));
    final nestedPubspec = File(p.join(nested.path, 'pubspec.yaml'));
    if (nestedPubspec.existsSync() &&
        nestedPubspec.readAsStringSync().contains('name: love2d')) {
      return nested.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'Could not find pkgs/love2d from ${Directory.current.path}',
  );
}
