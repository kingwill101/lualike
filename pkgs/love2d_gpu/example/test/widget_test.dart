import 'package:flutter/services.dart';
import 'package:flutter_lualike/flutter_lualike.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d_gpu_demo/love2d_demo_diagnostics.dart';
import 'package:lualike/lualike.dart' show Box, LuaBytecodeVm;

void main() {
  test('binding diagnostics are compile-time disabled by default', () {
    expect(Box.bindingDiagnostics(), <String, Object>{
      'enabled': false,
      'created': 0,
      'reused': 0,
      'localBindingClones': 0,
      'sharedScalarClones': 0,
      'unsharedScalarClones': 0,
      'stringPrimitiveClones': 0,
      'decoratedPrimitiveClones': 0,
      'otherLocalClones': 0,
    });
  });

  test('capture presentation state is deterministic and observable', () {
    final diagnostics = Love2dDemoDiagnostics(
      entryAsset: 'assets/main.lua',
      gpuBackend: null,
      engineMode: 'ast',
      gcPolicy: 'luaCompatible',
      recreateHarnessOnModeSwitch: false,
      gpuInitializationDisabled: true,
      initialMode: 'canvas',
    );

    expect(diagnostics.state()['capturePresentation'], isFalse);
    expect(diagnostics.state()['gcPolicy'], 'luaCompatible');
    expect(diagnostics.state()['recreateHarnessOnModeSwitch'], isFalse);
    expect(diagnostics.state()['gpuInitializationDisabled'], isTrue);
    expect(diagnostics.state()['workload'], <String, Object?>{
      'name': null,
      'tick': null,
      'checksum': null,
    });
    diagnostics.setCapturePresentation(enabled: true);
    expect(diagnostics.capturePresentation.value, isTrue);
    expect(diagnostics.state()['capturePresentation'], isTrue);
    expect(diagnostics.state()['canvasStraightAlphaTextures'], isFalse);
    expect(
      diagnostics.state()['canvasRuntimeStraightAlphaTextureTuning'],
      isFalse,
    );
    expect(diagnostics.state()['canvasStraightAlphaTextureBindings'], 0);
    expect(diagnostics.state()['canvasStraightAlphaTextureEstimatedBytes'], 0);
    expect(
      diagnostics.setCanvasStraightAlphaTextures(enabled: true),
      'runtime Canvas straight-alpha tuning is not enabled in this build',
    );
    expect(diagnostics.state()['gpuTypedGeneratedStrokes'], isFalse);
    expect(diagnostics.state()['gpuRuntimeStrokeTuning'], isFalse);
    expect(diagnostics.state()['gpuRoughLineShader'], isFalse);
    expect(diagnostics.state()['gpuRuntimeRoughLineShaderTuning'], isFalse);
    expect(diagnostics.state()['gpuDirectSpriteGeometry'], isFalse);
    expect(diagnostics.state()['gpuRuntimeSpriteGeometryTuning'], isFalse);
    expect(
      diagnostics.state()['lualikeSyncPlainTableOpcodes'],
      LuaBytecodeVm.usesSyncPlainTableOpcodes,
    );
    expect(diagnostics.state()['lualikeRuntimeSyncPlainTableTuning'], isFalse);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('flutter_lualike indexes the complete Neon Relay asset pack', () async {
    final backend = AssetBundleFileSystemBackend(
      rootBundle,
      assetRoot: 'assets',
    );
    await backend.prewarm();

    final artAssets = await backend.listDirectory('art')
      ..sort();
    expect(artAssets, <String>[
      'assets/art/neon_relay_arena.png',
      'assets/art/neon_relay_beacon.png',
      'assets/art/neon_relay_bolt.png',
      'assets/art/neon_relay_cell.png',
      'assets/art/neon_relay_core.png',
      'assets/art/neon_relay_core_damaged.png',
      'assets/art/neon_relay_drone.png',
      'assets/art/neon_relay_impact.png',
      'assets/art/neon_relay_overdrive.png',
      'assets/art/neon_relay_player.png',
      'assets/art/neon_relay_sentinel.png',
      'assets/art/neon_relay_shield.png',
    ]);

    for (final asset in artAssets) {
      final relativePath = asset.substring('assets/'.length);
      expect(await backend.fileExists(relativePath), isTrue);
      expect(await backend.fileSize(relativePath), greaterThan(0));
    }

    final mainSource = await backend.readFileAsString('main.lua');
    expect(await backend.fileExists('parity_probe/main.lua'), isTrue);
    expect(await backend.fileExists('parity_probe/conf.lua'), isTrue);
    expect(await backend.fileExists('shared/signal_lattice.lua'), isTrue);
    expect(await backend.fileExists('signal_lattice_benchmark.lua'), isTrue);
    expect(mainSource, contains('art/neon_relay_sentinel.png'));
    expect(mainSource, contains('art/neon_relay_bolt.png'));
    expect(mainSource, contains('art/neon_relay_shield.png'));
    expect(mainSource, contains('art/neon_relay_impact.png'));
    expect(mainSource, contains('art/neon_relay_overdrive.png'));
    expect(mainSource, contains('art/neon_relay_core.png'));
    expect(mainSource, contains('art/neon_relay_core_damaged.png'));
    expect(mainSource, contains('local function set_relay_integrity(value)'));
    expect(mainSource, contains('local function freeze_parity_scene()'));
    expect(mainSource, contains('local function activate_signal_lab()'));
    expect(mainSource, contains('shared/signal_lattice.lua'));
    expect(mainSource, contains('elseif key == "c"'));
    expect(mainSource, contains('args[i] == "--parity-freeze"'));
    expect(mainSource, contains('boss_attack_relay_hit = true'));
    expect(mainSource, contains('love.graphics.newSpriteBatch(bolt_image'));
    expect(mainSource, contains('love.graphics.newSpriteBatch(shield_image'));
    expect(mainSource, contains('local function update_shields(dt)'));
    expect(mainSource, contains('elseif key == "b"'));
    expect(mainSource, contains('elseif key == "v"'));
    expect(
      mainSource,
      contains('enemy_x[i], enemy_y[i], enemy_phase[i],'),
      reason: 'the frozen reset must reseed mutable SpriteBatch transforms',
    );
  });
}
