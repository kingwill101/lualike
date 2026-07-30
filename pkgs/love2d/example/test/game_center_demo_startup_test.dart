import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:love2d_test_bed/game_center/game_center.dart';
import 'package:path/path.dart' as p;

/// Update+draw frames after load — enough to hit step/draw paths (snake, etc.).
const _kSmokeUpdateFrames = 12;

/// Resolves a Game Center asset key to an on-disk path for setSource.
///
/// Supports CWD at `pkgs/love2d/example` or `pkgs/love2d`.
String _diskEntryFor(GameEntry entry) {
  final asset = entry.entryAsset; // e.g. assets/snake/main.lua
  final candidates = <String>[
    asset,
    p.join('example', asset),
    p.join('assets', p.basename(p.dirname(asset)), 'main.lua'),
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  // Prefer package-relative layout when invoked from monorepo root.
  return p.join('pkgs', 'love2d', 'example', asset);
}

/// Boots a Game Center entry from the on-disk example assets (no full asset
/// bundle catalog) and runs several game-loop frames under [engineMode].
///
/// Surfaces bytecode/optimizer regressions that only appear after `love.load`
/// once `love.update` / `love.draw` run.
Future<void> _bootEntry(
  GameEntry entry, {
  required EngineMode engineMode,
  int updateFrames = _kSmokeUpdateFrames,
}) async {
  final diskEntry = _diskEntryFor(entry);

  final host = LoveHeadlessHost();
  final runtime = LoveScriptRuntime(
    engineMode: engineMode,
    host: host,
    filesystemAdapter: LoveLualikeFilesystemAdapter(),
  );
  final filesystem = LoveFilesystemState.of(runtime.runtime);

  expect(
    filesystem.setSource(diskEntry),
    isTrue,
    reason: '${entry.title}: setSource($diskEntry) from ${Directory.current.path}',
  );
  await runtime.loadConfIfPresent().timeout(const Duration(seconds: 15));
  await runtime
      .execute(
        'assert(love.filesystem.load("main.lua"))()',
        scriptPath: '=[${entry.title} bootstrap]',
      )
      .timeout(const Duration(seconds: 45));
  await runtime.callLoadIfDefined().timeout(const Duration(seconds: 30));

  for (var frame = 0; frame < updateFrames; frame++) {
    await runtime
        .callUpdateIfDefined(1 / 60)
        .timeout(const Duration(seconds: 10));
    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    await runtime.callDrawIfDefined().timeout(const Duration(seconds: 10));
  }
}

void main() {
  // Runs from pkgs/love2d when invoked via `flutter test` in example/ or
  // from the monorepo; LoveLualikeFilesystemAdapter resolves relative paths
  // against the process CWD. Prefer invoking from pkgs/love2d:
  //   cd pkgs/love2d && flutter test example/test/game_center_demo_startup_test.dart
  //
  // Or from example/ with cwd parent — setSource uses example/assets/...

  group('game center demos (luaBytecode, multi-frame smoke)', () {
    for (final entry in kDemoEntries) {
      test(
        '${entry.title} boots and survives $_kSmokeUpdateFrames frames',
        () async {
          await _bootEntry(entry, engineMode: EngineMode.luaBytecode);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}
