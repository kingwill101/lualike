import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('harness forwards LOVE window metrics to aware render backends', () {
    final backend = _WindowMetricsRecordingBackend();
    final game = LoveFlameHarnessGame(renderBackend: backend);

    expect(backend.metrics, hasLength(1));
    expect(backend.metrics.single.msaa, 0);

    game.host.windowMetrics = const LoveWindowMetrics(
      width: 960,
      height: 540,
      msaa: 4,
    );

    expect(backend.metrics.last.width, 960);
    expect(backend.metrics.last.height, 540);
    expect(backend.metrics.last.msaa, 4);
  });

  test('harness forwards current metrics when the backend changes', () {
    final first = _WindowMetricsRecordingBackend();
    final second = _WindowMetricsRecordingBackend();
    final game = LoveFlameHarnessGame(renderBackend: first);
    game.host.windowMetrics = const LoveWindowMetrics(
      width: 960,
      height: 540,
      msaa: 4,
    );

    game.setRenderBackend(second);

    expect(game.renderBackend, same(second));
    expect(second.metrics, hasLength(1));
    expect(second.metrics.single.width, 960);
    expect(second.metrics.single.height, 540);
    expect(second.metrics.single.msaa, 4);
  });
}

final class _WindowMetricsRecordingBackend
    implements LoveRenderBackend, LoveWindowMetricsAwareRenderBackend {
  final List<LoveWindowMetrics> metrics = <LoveWindowMetrics>[];

  @override
  bool get isAvailable => true;

  @override
  String get name => 'window-metrics-recorder';

  @override
  void updateLoveWindowMetrics(LoveWindowMetrics metrics) {
    this.metrics.add(metrics);
  }

  @override
  void renderSurface(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {}
}
