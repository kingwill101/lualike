import 'dart:ui' as ui;

import '../love_runtime.dart';
import '../flame/love_flame_harness_renderer.dart';
import 'love_render_backend.dart';

/// Renders LOVE draw commands onto a Flutter [ui.Canvas] using the standard
/// Canvas 2D API (the default LOVE2D rendering path).
///
/// This backend delegates to the existing Canvas-based rendering functions
/// in [love_flame_harness_renderer.dart]. It supports all draw command types
/// with software fallbacks for unsupported blend modes and stencil operations.
final class LoveCanvasRenderBackend implements LoveRenderBackend {
  LoveCanvasRenderBackend();

  @override
  String get name => 'Canvas';

  @override
  bool get isAvailable => true;

  @override
  void renderSurface(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {
    renderSurfaceSnapshot(
      canvas,
      surface,
      viewportSize,
      stats: stats,
    );
  }
}
