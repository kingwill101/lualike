import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love2d/love2d.dart';

const String relicBreachEntryAsset = 'assets/relic_breach/main.lua';
const bool _printFrameStats = bool.fromEnvironment('LOVE2D_PRINT_FRAME_STATS');
const bool _disableLightTextures = bool.fromEnvironment(
  'LOVE2D_RELIC_DISABLE_LIGHT_TEXTURES',
);
const List<String> _relicBreachStartupImages = <String>[
  'assets/relic_breach/art/kenney_roguelike_rpg_pack/Spritesheet/roguelikeSheet_runtime.png',
  'assets/relic_breach/art/kenney_roguelike_characters/Spritesheet/roguelikeChar_runtime.png',
  'assets/relic_breach/art/kenney_input_prompts_pixel/Tiles/tile_0294.png',
  'assets/relic_breach/art/kenney_input_prompts_pixel/Tiles/tile_0612.png',
  'assets/relic_breach/art/kenney_input_prompts_pixel/Tiles/tile_0620.png',
  if (!_disableLightTextures)
    'assets/relic_breach/art/kenney_light_masks/Default/circle_a_streaks_runtime.png',
  if (!_disableLightTextures)
    'assets/relic_breach/art/kenney_light_masks/Default/cone_a_blur_runtime.png',
  if (!_disableLightTextures)
    'assets/relic_breach/art/kenney_light_masks/Default/water_caustics_a_runtime.png',
];

void main() {
  runApp(const RelicBreachExampleApp());
}

void _installFrameStatsPrinter(LoveFlameHarnessGame game) {
  if (!_printFrameStats) {
    return;
  }

  game.resetFrameTimingStats();
  var ticks = 0;
  Timer.periodic(const Duration(seconds: 1), (timer) {
    final stats = game.frameTimingStats;
    if (stats.sampleCount == 0) {
      return;
    }

    ticks += 1;
    debugPrint(
      'love2d-frame-stats '
      'samples=${stats.sampleCount} '
      'avgDeltaMs=${(stats.averageDeltaSeconds * 1000).toStringAsFixed(2)} '
      'p95DeltaMs=${(stats.p95DeltaSeconds * 1000).toStringAsFixed(2)} '
      'avgUpdateMs=${stats.averageUpdateDuration.inMicroseconds / 1000} '
      'p95UpdateMs=${stats.p95UpdateDuration.inMicroseconds / 1000} '
      'avgRenderMs=${stats.averageRenderDuration.inMicroseconds / 1000} '
      'p95RenderMs=${stats.p95RenderDuration.inMicroseconds / 1000} '
      'avgCpuMs=${stats.averageCpuFrameDuration.inMicroseconds / 1000} '
      'p95CpuMs=${stats.p95CpuFrameDuration.inMicroseconds / 1000} '
      'avgCommands=${stats.averageRenderedCommands.toStringAsFixed(1)} '
      'maxCommands=${stats.maxRenderedCommands} '
      'avgAtlasBatchItems=${stats.averageAtlasBatchItems.toStringAsFixed(1)} '
      'maxAtlasBatchItems=${stats.maxAtlasBatchItems} '
      'avgSoftwareFallbacks='
      '${stats.averageSoftwareSurfaceFallbacks.toStringAsFixed(1)} '
      'maxSoftwareFallbacks=${stats.maxSoftwareSurfaceFallbacks}',
    );

    if (ticks >= 20) {
      timer.cancel();
    }
  });
}

class RelicBreachExampleApp extends StatelessWidget {
  const RelicBreachExampleApp({
    super.key,
    this.bundle,
    this.filesystemAdapter,
    this.audioBackendFactory,
    this.onQuitRequested,
  });

  final AssetBundle? bundle;
  final LoveFilesystemAdapter? filesystemAdapter;
  final LoveAudioBackendFactory? audioBackendFactory;
  final Future<void> Function()? onQuitRequested;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relic Breach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF050816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF86EFAC),
          secondary: Color(0xFFF59E0B),
          surface: Color(0xFF111827),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: LoveFlameHarness(
            entryAsset: relicBreachEntryAsset,
            bundle: bundle ?? rootBundle,
            filesystemAdapter: filesystemAdapter,
            audioBackendFactory: audioBackendFactory,
            automaticGc: true,
            imageWarmupAssetKeys: _relicBreachStartupImages,
            debugOnGameCreated: _installFrameStatsPrinter,
            onQuitRequested: onQuitRequested,
          ),
        ),
      ),
    );
  }
}
