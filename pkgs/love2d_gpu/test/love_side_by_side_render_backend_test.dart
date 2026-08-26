import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/love2d_gpu.dart';

void main() {
  test('replays the same snapshot and viewport through both backends', () {
    final left = _RecordingBackend('left');
    final right = _RecordingBackend('right');
    final comparison = LoveSideBySideRenderBackend(left: left, right: right);
    const snapshot = LoveGraphicsSurfaceSnapshot(
      clearColor: LoveColor(0, 0, 0, 1),
      clearColorMask: LoveGraphicsColorMask.all,
      clearStencil: 0,
      clearScissor: null,
      commands: <LoveDrawCommand>[],
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const viewportSize = ui.Size(800, 600);
    final stats = LoveRenderStatsAccumulator();

    comparison.renderSurface(canvas, snapshot, viewportSize, stats: stats);
    recorder.endRecording().dispose();

    expect(left.calls, 1);
    expect(right.calls, 1);
    expect(identical(left.snapshot, snapshot), isTrue);
    expect(identical(right.snapshot, snapshot), isTrue);
    expect(left.viewportSize, viewportSize);
    expect(right.viewportSize, viewportSize);
    expect(comparison.lastLeftStats.renderedCommands, 1);
    expect(comparison.lastRightStats.renderedCommands, 2);
    expect(stats.snapshot().renderedCommands, 3);
  });

  test('maps pointer coordinates from either pane to shared LOVE space', () {
    final comparison = LoveSideBySideRenderBackend(
      left: _RecordingBackend('left'),
      right: _RecordingBackend('right'),
    );
    const viewportSize = ui.Size(800, 600);

    final leftPoint = comparison.mapInputPoint(
      const ui.Offset(100, 202),
      viewportSize,
    );
    final rightPoint = comparison.mapInputPoint(
      const ui.Offset(508, 202),
      viewportSize,
    );

    expect(leftPoint.dx, closeTo(rightPoint.dx, 0.001));
    expect(leftPoint.dy, closeTo(rightPoint.dy, 0.001));
    expect(leftPoint.dx, closeTo(204.0816, 0.001));
    expect(leftPoint.dy, closeTo(100.0, 0.001));
    final delta = comparison.mapInputDelta(
      const ui.Offset(4.9, 9.8),
      leftPoint,
      viewportSize,
    );
    expect(delta.dx, closeTo(10, 0.001));
    expect(delta.dy, closeTo(20, 0.001));
  });
}

final class _RecordingBackend implements LoveRenderBackend {
  _RecordingBackend(this.name);

  @override
  final String name;

  int calls = 0;
  LoveGraphicsSurfaceSnapshot? snapshot;
  ui.Size? viewportSize;

  @override
  bool get isAvailable => true;

  @override
  void renderSurface(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {
    calls++;
    snapshot = surface;
    this.viewportSize = viewportSize;
    stats?.renderedCommands += name == 'left' ? 1 : 2;
  }
}
