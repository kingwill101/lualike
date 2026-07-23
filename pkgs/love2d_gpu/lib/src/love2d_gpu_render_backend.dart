import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

import 'renderer/renderer.dart';
import 'shader/love_shader_bundle.dart';

/// Renders LOVE2D draw commands through [package:flutter_gpu]'s low-level
/// GPU API instead of the standard Flutter Canvas 2D pipeline.
///
/// This backend creates a [gpu.GpuContext], builds render pipelines from
/// LOVE shaders, and issues draw calls directly to the GPU. The rendered
/// result is presented to the Flutter framework via [gpu.Texture.asImage].
///
/// ## Design
///
/// For each frame:
/// 1. Analyze the command list and determine which commands to GPU-render
///    vs. fall back to the Canvas path.
/// 2. Acquire a color texture from the surface.
/// 3. Build a [gpu.CommandBuffer] with render passes for each command type
///    (clear, mesh, sprite batch, image, etc.).
/// 4. Present the completed frame via [gpu.GpuImageSurface] and draw the
///    resulting [ui.Image] onto the Flutter canvas.
///
/// ## Current status
///
/// This is a work-in-progress skeleton. The concrete backend will be filled
/// in incrementally as each command type gains GPU support.
class LoveGpuRenderBackend implements LoveRenderBackend {
  LoveGpuRenderBackend._(this._renderer);

  static LoveGpuRenderBackend? _instance;

  final GpuCommandRenderer _renderer;

  /// Creates or returns the singleton GPU render backend.
  ///
  /// Returns `null` if [package:flutter_gpu] is not available (e.g. the
  /// Flutter SDK does not bundle it, or Impeller is not enabled) or if the
  /// compiled shader bundle cannot be loaded.
  static Future<LoveGpuRenderBackend?> create() async {
    if (_instance != null) return _instance;
    try {
      final gpuContext = gpu.gpuContext;
      await LoveShaderBundles.load();
      _instance = LoveGpuRenderBackend._(
        GpuCommandRenderer(
          gpuContext: gpuContext,
          surfaceManager: GpuSurfaceManager(gpuContext),
          pipelineCache: GpuPipelineCache(gpuContext),
          textureCache: GpuTextureCache(gpuContext),
          hostBufferPool: GpuHostBufferPool(gpuContext),
          fallbackHandler: GpuFallbackHandler(
            canvasBackend: LoveCanvasRenderBackend(),
          ),
        ),
      );
      return _instance;
    } catch (e, st) {
      debugPrint('love2d_gpu: GPU backend unavailable: $e');
      debugPrint('$st');
      return null;
    }
  }

  @override
  String get name => 'Flutter GPU';

  @override
  bool get isAvailable => true;

  @override
  void renderSurface(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {
    _renderer.renderFrame(canvas, surface, viewportSize, stats: stats);
  }
}
