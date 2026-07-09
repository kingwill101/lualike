import 'dart:ui' as ui;

import '../love_runtime.dart';

/// Per-frame rendering statistics from any render backend.
class LoveRenderStats {
  const LoveRenderStats({
    this.renderedCommands = 0,
    this.softwareSurfaceFallbacks = 0,
    this.atlasBatchCommands = 0,
    this.atlasBatchItems = 0,
    this.textPainterCacheHits = 0,
    this.textPainterCacheMisses = 0,
    this.textLayoutDuration = Duration.zero,
    this.surfaceClearLayers = 0,
    this.commandBlendLayers = 0,
    this.commandShaderLayers = 0,
    this.commandRadialMaskLayers = 0,
    this.imageRadialOverlayLayers = 0,
    this.meshCompositeLayers = 0,
    this.meshAlphaMaskLayers = 0,
  });

  final int renderedCommands;
  final int softwareSurfaceFallbacks;
  final int atlasBatchCommands;
  final int atlasBatchItems;
  final int textPainterCacheHits;
  final int textPainterCacheMisses;
  final Duration textLayoutDuration;
  final int surfaceClearLayers;
  final int commandBlendLayers;
  final int commandShaderLayers;
  final int commandRadialMaskLayers;
  final int imageRadialOverlayLayers;
  final int meshCompositeLayers;
  final int meshAlphaMaskLayers;

  int get totalSaveLayers =>
      surfaceClearLayers +
      commandBlendLayers +
      commandShaderLayers +
      commandRadialMaskLayers +
      imageRadialOverlayLayers +
      meshCompositeLayers +
      meshAlphaMaskLayers;
}

/// Abstraction for LOVE2D rendering backends.
///
/// Each [LoveRenderBackend] replays a [LoveGraphicsSurfaceSnapshot] onto
/// Flutter's rendering pipeline. The [renderSurface] method receives a
/// [ui.Canvas] whose transform is already set to LOVE logical coordinates.
///
/// Backends are selected at runtime:
/// - [LoveCanvasRenderBackend] — uses Flutter Canvas API (default, stable)
/// - [LoveGpuRenderBackend] — uses [package:flutter_gpu] (experimental, master)
abstract class LoveRenderBackend {
  /// Human-readable backend identifier (e.g. "Canvas", "Flutter GPU").
  String get name;

  /// Whether this backend is available on the current platform.
  bool get isAvailable;

  /// Render a frame's worth of LOVE draw commands onto [canvas].
  ///
  /// [surface] contains the frozen command list and clear state for this
  /// frame. [viewportSize] is the logical size of the LOVE viewport in
  /// logical pixels (the canvas will already be clipped and scaled).
  ///
  /// When [stats] is provided, the backend populates it with counters
  /// collected during rendering.
  void renderSurface(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  });
}

/// Accumulator for building [LoveRenderStats] while rendering a frame.
class LoveRenderStatsAccumulator {
  int renderedCommands = 0;
  int softwareSurfaceFallbacks = 0;
  int atlasBatchCommands = 0;
  int atlasBatchItems = 0;
  int textPainterCacheHits = 0;
  int textPainterCacheMisses = 0;
  Duration textLayoutDuration = Duration.zero;
  int surfaceClearLayers = 0;
  int commandBlendLayers = 0;
  int commandShaderLayers = 0;
  int commandRadialMaskLayers = 0;
  int imageRadialOverlayLayers = 0;
  int meshCompositeLayers = 0;
  int meshAlphaMaskLayers = 0;

  LoveRenderStats snapshot() => LoveRenderStats(
        renderedCommands: renderedCommands,
        softwareSurfaceFallbacks: softwareSurfaceFallbacks,
        atlasBatchCommands: atlasBatchCommands,
        atlasBatchItems: atlasBatchItems,
        textPainterCacheHits: textPainterCacheHits,
        textPainterCacheMisses: textPainterCacheMisses,
        textLayoutDuration: textLayoutDuration,
        surfaceClearLayers: surfaceClearLayers,
        commandBlendLayers: commandBlendLayers,
        commandShaderLayers: commandShaderLayers,
        commandRadialMaskLayers: commandRadialMaskLayers,
        imageRadialOverlayLayers: imageRadialOverlayLayers,
        meshCompositeLayers: meshCompositeLayers,
        meshAlphaMaskLayers: meshAlphaMaskLayers,
      );
}
