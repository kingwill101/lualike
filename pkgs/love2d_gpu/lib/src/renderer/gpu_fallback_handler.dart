import 'dart:ui' as ui;

import 'package:love2d/love2d.dart';

/// Handles hybrid fallback rendering.
///
/// When the GPU path cannot render a command (e.g., unsupported shader, blend
/// mode, or stencil operation), the fallback handler re-renders those commands
/// via the standard Canvas path through [LoveCanvasRenderBackend].
///
/// ## Toggle
///
/// The [enabled] flag controls whether fallback is active:
/// - `true` — skipped commands are silently re-rendered via Canvas.
/// - `false` — skipped commands are left as visual gaps (useful for
///   discovering unsupported command types during development).
///
/// ## Compositing
///
/// The GPU-rendered image is already drawn on the canvas by
/// [GpuCommandRenderer]. The fallback handler then overlays only the
/// unsupported commands on top, using `Canvas.saveLayer` when necessary to
/// preserve the GPU output beneath.
class GpuFallbackHandler {
  /// Creates a fallback handler that wraps [canvasBackend].
  GpuFallbackHandler({
    required LoveCanvasRenderBackend canvasBackend,
  }) : _canvasBackend = canvasBackend;

  final LoveCanvasRenderBackend _canvasBackend;

  /// When `false`, unsupported commands are left as gaps (development mode).
  bool enabled = true;

  /// Returns the subset of [commands] at the given [unsortedIndices] indices.
  ///
  /// This is a helper to extract only the commands that the GPU path could
  /// not handle.
  List<LoveDrawCommand> extractUnsupported(
    List<LoveDrawCommand> commands,
    List<int> unsortedIndices,
  ) {
    return unsortedIndices.map((i) => commands[i]).toList();
  }

  /// Renders a list of LOVE draw commands onto [canvas] using the Canvas path.
  ///
  /// The canvas should already contain the GPU-rendered frame. This method
  /// composes the fallback commands on top without clearing.
  ///
  /// Returns the number of commands that were actually rendered.
  int renderFallback(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize,
    List<int> unsupportedIndices, {
    LoveRenderStatsAccumulator? stats,
  }) {
    if (!enabled || unsupportedIndices.isEmpty) return 0;

    // Build a snapshot containing only the unsupported commands.
    final fallbackCommands = unsupportedIndices
        .map((i) => surface.commands[i])
        .toList();

    final fallbackSnapshot = LoveGraphicsSurfaceSnapshot(
      clearColor: const LoveColor(0, 0, 0, 0), // transparent clear
      clearColorMask: LoveGraphicsColorMask.all,
      clearStencil: 0,
      clearScissor: null,
      commands: fallbackCommands,
    );

    canvas.saveLayer(ui.Offset.zero & viewportSize, ui.Paint());
    try {
      _canvasBackend.renderSurface(
        canvas,
        fallbackSnapshot,
        viewportSize,
        stats: stats,
      );
    } finally {
      canvas.restore();
    }

    return fallbackCommands.length;
  }

  /// Renders the entire frame through the Canvas path.
  ///
  /// Use this when mixed GPU/Canvas composition would otherwise change draw
  /// order.
  void renderFullFrame(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {
    if (!enabled) return;
    _canvasBackend.renderSurface(canvas, surface, viewportSize, stats: stats);
  }
}
