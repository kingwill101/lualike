import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:love2d/love2d.dart';

/// Replays one frozen LOVE surface through two backends side by side.
///
/// This is intended for renderer diagnostics. The caller still advances the
/// LOVE runtime once and supplies one [LoveGraphicsSurfaceSnapshot], so both
/// panes see the same clear state, command list, transforms, and simulation
/// frame. Each backend receives its own canvas transform and can maintain its
/// own resources.
///
/// The panes preserve the LOVE viewport aspect ratio. If the available width
/// is too small, the comparison is letterboxed vertically rather than
/// stretching either renderer.
final class LoveSideBySideRenderBackend implements LoveRenderBackend {
  LoveSideBySideRenderBackend({
    required this.left,
    required this.right,
    this.gap = 16,
  }) : assert(gap >= 0);

  /// Backend rendered in the left pane.
  final LoveRenderBackend left;

  /// Backend rendered in the right pane.
  final LoveRenderBackend right;

  /// Gap between the two panes in LOVE logical pixels.
  final double gap;

  /// Statistics from the most recently rendered left pane.
  LoveRenderStats get lastLeftStats => _lastLeftStats;

  /// Statistics from the most recently rendered right pane.
  LoveRenderStats get lastRightStats => _lastRightStats;

  LoveRenderStats _lastLeftStats = const LoveRenderStats();
  LoveRenderStats _lastRightStats = const LoveRenderStats();

  @override
  String get name => '${left.name} vs ${right.name}';

  @override
  bool get isAvailable => left.isAvailable && right.isAvailable;

  /// Converts a point from either rendered pane to shared LOVE coordinates.
  ///
  /// Points in the inter-pane gap or letterbox are clamped to the nearest
  /// logical edge so dragging across the comparison remains deterministic.
  ui.Offset mapInputPoint(ui.Offset logicalPoint, ui.Size viewportSize) {
    final layout = _layoutFor(viewportSize);
    if (layout == null) {
      return logicalPoint;
    }

    final paneOffset = logicalPoint.dx >= layout.rightPaneStart - gap / 2
        ? layout.rightPaneStart
        : 0.0;
    return ui.Offset(
      ((logicalPoint.dx - paneOffset) / layout.scale)
          .clamp(0.0, viewportSize.width)
          .toDouble(),
      ((logicalPoint.dy - layout.top) / layout.scale)
          .clamp(0.0, viewportSize.height)
          .toDouble(),
    );
  }

  /// Converts a rendered-pane pointer delta to shared LOVE coordinates.
  ui.Offset mapInputDelta(
    ui.Offset logicalDelta,
    ui.Offset logicalPoint,
    ui.Size viewportSize,
  ) {
    final layout = _layoutFor(viewportSize);
    if (layout == null || layout.scale <= 0) {
      return logicalDelta;
    }
    return logicalDelta / layout.scale;
  }

  @override
  void renderSurface(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {
    final layout = _layoutFor(viewportSize);
    if (layout == null) {
      return;
    }

    final leftAccumulator = LoveRenderStatsAccumulator();
    final rightAccumulator = LoveRenderStatsAccumulator();
    _renderPane(
      canvas,
      left,
      surface,
      viewportSize,
      offsetX: 0,
      top: layout.top,
      scale: layout.scale,
      paneWidth: layout.renderedPaneWidth,
      paneHeight: layout.renderedPaneHeight,
      stats: leftAccumulator,
    );
    _renderPane(
      canvas,
      right,
      surface,
      viewportSize,
      offsetX: layout.rightPaneStart,
      top: layout.top,
      scale: layout.scale,
      paneWidth: layout.renderedPaneWidth,
      paneHeight: layout.renderedPaneHeight,
      stats: rightAccumulator,
    );

    _lastLeftStats = leftAccumulator.snapshot();
    _lastRightStats = rightAccumulator.snapshot();
    if (stats != null) {
      _addStats(stats, _lastLeftStats);
      _addStats(stats, _lastRightStats);
    }

    final borderPaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const ui.Color(0x8094A3B8);
    canvas.drawRect(
      ui.Rect.fromLTWH(
        0,
        layout.top,
        layout.renderedPaneWidth,
        layout.renderedPaneHeight,
      ),
      borderPaint,
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(
        layout.rightPaneStart,
        layout.top,
        layout.renderedPaneWidth,
        layout.renderedPaneHeight,
      ),
      borderPaint,
    );
  }

  ({
    double scale,
    double renderedPaneWidth,
    double renderedPaneHeight,
    double top,
    double rightPaneStart,
  })?
  _layoutFor(ui.Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return null;
    }

    final availableWidth = math.max(0.0, viewportSize.width - gap);
    final paneWidth = availableWidth / 2;
    if (paneWidth <= 0) {
      return null;
    }

    final scale = math.min(1.0, paneWidth / viewportSize.width);
    final renderedPaneWidth = viewportSize.width * scale;
    final renderedPaneHeight = viewportSize.height * scale;
    return (
      scale: scale,
      renderedPaneWidth: renderedPaneWidth,
      renderedPaneHeight: renderedPaneHeight,
      top: (viewportSize.height - renderedPaneHeight) / 2,
      rightPaneStart: renderedPaneWidth + gap,
    );
  }

  static void _addStats(
    LoveRenderStatsAccumulator target,
    LoveRenderStats source,
  ) {
    target.renderedCommands += source.renderedCommands;
    target.softwareSurfaceFallbacks += source.softwareSurfaceFallbacks;
    target.atlasBatchCommands += source.atlasBatchCommands;
    target.atlasBatchItems += source.atlasBatchItems;
    target.textPainterCacheHits += source.textPainterCacheHits;
    target.textPainterCacheMisses += source.textPainterCacheMisses;
    target.textLayoutDuration += source.textLayoutDuration;
    target.surfaceClearLayers += source.surfaceClearLayers;
    target.commandBlendLayers += source.commandBlendLayers;
    target.commandShaderLayers += source.commandShaderLayers;
    target.commandRadialMaskLayers += source.commandRadialMaskLayers;
    target.imageRadialOverlayLayers += source.imageRadialOverlayLayers;
    target.meshCompositeLayers += source.meshCompositeLayers;
    target.meshAlphaMaskLayers += source.meshAlphaMaskLayers;
  }

  void _renderPane(
    ui.Canvas canvas,
    LoveRenderBackend backend,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    required double offsetX,
    required double top,
    required double scale,
    required double paneWidth,
    required double paneHeight,
    required LoveRenderStatsAccumulator? stats,
  }) {
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(offsetX, top, paneWidth, paneHeight));
    canvas.translate(offsetX, top);
    canvas.scale(scale, scale);
    backend.renderSurface(canvas, surface, viewportSize, stats: stats);
    canvas.restore();
  }
}
