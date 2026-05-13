import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_test_bed/game_center/game_center.dart';

Future<LoveAudioSourceBackend> _noopAudioBackendFactory(
  String source, {
  required String sourceType,
  Uint8List? bytes,
  String? mimeType,
}) async {
  return const LoveNoopAudioSourceBackend();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'captures cold and warm benchmark smoke metrics for Modern Pong',
    (tester) async {
      final report = await _runHarnessBenchmark(
        tester,
        title: 'Modern Pong',
        entryAsset: modernPongEntryAsset,
      );

      expect(
        report.cold.frameTimingStats.sampleCount,
        greaterThanOrEqualTo(12),
      );
      expect(
        report.warm.frameTimingStats.sampleCount,
        greaterThanOrEqualTo(12),
      );
      expect(_hasRenderActivity(report.cold.frameTimingStats), isTrue);
      expect(_hasRenderActivity(report.warm.frameTimingStats), isTrue);
    },
  );

  testWidgets(
    'captures cold and warm benchmark smoke metrics for LOVE Example Browser',
    (tester) async {
      final report = await _runHarnessBenchmark(
        tester,
        title: 'LOVE Example Browser',
        entryAsset: loveExampleBrowserEntryAsset,
      );

      expect(
        report.cold.frameTimingStats.sampleCount,
        greaterThanOrEqualTo(12),
      );
      expect(
        report.warm.frameTimingStats.sampleCount,
        greaterThanOrEqualTo(12),
      );
      expect(_hasRenderActivity(report.cold.frameTimingStats), isTrue);
      expect(_hasRenderActivity(report.warm.frameTimingStats), isTrue);
    },
  );
}

Future<_HarnessBenchmarkReport> _runHarnessBenchmark(
  WidgetTester tester, {
  required String title,
  required String entryAsset,
  Size surfaceSize = const Size(960, 640),
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(surfaceSize);

  final cold = await _runHarnessBenchmarkSession(
    tester,
    title: title,
    entryAsset: entryAsset,
    instanceKey: const ValueKey<String>('cold'),
  );

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 16));

  final warm = await _runHarnessBenchmarkSession(
    tester,
    title: title,
    entryAsset: entryAsset,
    instanceKey: const ValueKey<String>('warm'),
  );

  final report = _HarnessBenchmarkReport(
    title: title,
    entryAsset: entryAsset,
    cold: cold,
    warm: warm,
  );
  debugPrint(report.format());
  return report;
}

Future<_HarnessBenchmarkSessionReport> _runHarnessBenchmarkSession(
  WidgetTester tester, {
  required String title,
  required String entryAsset,
  required Key instanceKey,
  int measuredFrames = 24,
  Duration startupStep = const Duration(milliseconds: 100),
  Duration frameStep = const Duration(milliseconds: 16),
}) async {
  LoveFlameHarnessGame? game;
  final filesystemAdapter = await LoveAssetBundleFilesystemAdapter.load(
    bundle: rootBundle,
    fallback: LoveLualikeFilesystemAdapter(),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: LoveFlameHarness(
            key: instanceKey,
            title: title,
            entryAsset: entryAsset,
            bundle: rootBundle,
            filesystemAdapter: filesystemAdapter,
            audioBackendFactory: _noopAudioBackendFactory,
            debugOnGameCreated: (value) => game = value,
          ),
        ),
      ),
    ),
  );

  final startupPumpCount = await _pumpUntilRunning(tester, step: startupStep);
  final harnessGame = game;
  expect(harnessGame, isNotNull);

  harnessGame!.resetFrameTimingStats();
  await _pumpFrames(tester, count: measuredFrames, step: frameStep);

  expect(find.text(title), findsOneWidget);
  expect(tester.takeException(), isNull);

  return _HarnessBenchmarkSessionReport(
    startupPumpCount: startupPumpCount,
    startupSimulatedDuration: startupStep * startupPumpCount,
    frameTimingStats: harnessGame.frameTimingStats,
    lastRenderStats: harnessGame.lastRenderStats,
  );
}

Future<int> _pumpUntilRunning(
  WidgetTester tester, {
  int maxPumps = 180,
  Duration step = const Duration(milliseconds: 100),
  Duration asyncYield = const Duration(milliseconds: 10),
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(asyncYield);
    });
    await tester.pump(step);
    if (_statusLabel(tester) == 'Running') {
      return index + 1;
    }
  }

  fail(
    'LoveFlameHarness did not reach Running. '
    'Last status: ${_statusLabel(tester) ?? 'missing status label'}',
  );
}

Future<void> _pumpFrames(
  WidgetTester tester, {
  required int count,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(step);
  }
}

String? _statusLabel(WidgetTester tester) {
  final statusFinder = find.byKey(const Key('status-label'));
  if (statusFinder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<Text>(statusFinder).data;
}

bool _hasRenderActivity(LoveFlameFrameTimingStats stats) {
  return stats.maxRenderedCommands > 0 || stats.maxSoftwareSurfaceFallbacks > 0;
}

final class _HarnessBenchmarkReport {
  const _HarnessBenchmarkReport({
    required this.title,
    required this.entryAsset,
    required this.cold,
    required this.warm,
  });

  final String title;
  final String entryAsset;
  final _HarnessBenchmarkSessionReport cold;
  final _HarnessBenchmarkSessionReport warm;

  String format() {
    return [
      'Benchmark smoke: $title ($entryAsset)',
      cold.format(label: 'cold'),
      warm.format(label: 'warm'),
    ].join('\n');
  }
}

final class _HarnessBenchmarkSessionReport {
  const _HarnessBenchmarkSessionReport({
    required this.startupPumpCount,
    required this.startupSimulatedDuration,
    required this.frameTimingStats,
    required this.lastRenderStats,
  });

  final int startupPumpCount;
  final Duration startupSimulatedDuration;
  final LoveFlameFrameTimingStats frameTimingStats;
  final LoveFlameRenderStats lastRenderStats;

  String format({required String label}) {
    return [
      '  $label: startup_pumps=$startupPumpCount',
      'startup_simulated_ms=${startupSimulatedDuration.inMilliseconds}',
      'samples=${frameTimingStats.sampleCount}',
      'avg_cpu_ms=${_milliseconds(frameTimingStats.averageCpuFrameDuration)}',
      'p95_cpu_ms=${_milliseconds(frameTimingStats.p95CpuFrameDuration)}',
      'max_cpu_ms=${_milliseconds(frameTimingStats.maxCpuFrameDuration)}',
      'avg_render_ms=${_milliseconds(frameTimingStats.averageRenderDuration)}',
      'p95_render_ms=${_milliseconds(frameTimingStats.p95RenderDuration)}',
      'avg_update_ms=${_milliseconds(frameTimingStats.averageUpdateDuration)}',
      'avg_commands=${frameTimingStats.averageRenderedCommands.toStringAsFixed(1)}',
      'avg_atlas_batches='
          '${frameTimingStats.averageAtlasBatchCommands.toStringAsFixed(1)}',
      'avg_atlas_items='
          '${frameTimingStats.averageAtlasBatchItems.toStringAsFixed(1)}',
      'avg_text_hits='
          '${frameTimingStats.averageTextPainterCacheHits.toStringAsFixed(1)}',
      'avg_text_misses='
          '${frameTimingStats.averageTextPainterCacheMisses.toStringAsFixed(1)}',
      'avg_text_layout_ms='
          '${_milliseconds(frameTimingStats.averageTextLayoutDuration)}',
      'avg_layers=${frameTimingStats.averageSaveLayers.toStringAsFixed(1)}',
      'avg_fallbacks='
          '${frameTimingStats.averageSoftwareSurfaceFallbacks.toStringAsFixed(1)}',
      'last_atlas_batches=${lastRenderStats.atlasBatchCommands}',
      'last_atlas_items=${lastRenderStats.atlasBatchItems}',
      'last_layers=${lastRenderStats.totalSaveLayers}',
      'last_fallbacks=${lastRenderStats.softwareSurfaceFallbacks}',
    ].join(', ');
  }
}

String _milliseconds(Duration duration) {
  return (duration.inMicroseconds / Duration.microsecondsPerMillisecond)
      .toStringAsFixed(3);
}
