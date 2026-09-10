import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

import 'renderer/renderer.dart';
import 'shader/love_shader_bundle.dart';

const bool _loveGpuMsaaPermitted = bool.fromEnvironment(
  'LOVE2D_GPU_MSAA',
  defaultValue: true,
);

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
class LoveGpuRenderBackend
    implements LoveRenderBackend, LoveWindowMetricsAwareRenderBackend {
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
          surfaceManager: GpuSurfaceManager(
            gpuContext,
            // LOVE defaults t.window.msaa to zero. The harness applies the
            // effective mode through updateLoveWindowMetrics after love.conf.
            enableMsaa: false,
          ),
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

  /// Whether the backend is currently rendering through offscreen MSAA.
  bool get usesMultisampleAntialiasing => _renderer.usesMultisampleAntialiasing;

  /// The sample count of the currently allocated offscreen color target.
  int get renderSampleCount => _renderer.renderSampleCount;

  @override
  void updateLoveWindowMetrics(LoveWindowMetrics metrics) {
    _renderer.setMultisampleAntialiasingEnabled(
      _loveGpuMsaaPermitted && metrics.msaa > 1,
    );
  }

  /// Whether this build permits uploading LOVE-authored mip chains.
  bool get mipmapUploadsEnabled => _renderer.mipmapUploadsEnabled;

  /// Whether the active GPU backend supports manually uploaded mip chains.
  bool get manuallyMippedTexturesSupported =>
      _renderer.manuallyMippedTexturesSupported;

  /// Whether generated circle and arc strokes use reusable typed coordinates.
  bool get usesTypedGeneratedStrokes => _renderer.usesTypedGeneratedStrokes;

  /// Whether this build permits live stroke-path A/B switching.
  bool get supportsRuntimeStrokeTuning => _renderer.supportsRuntimeStrokeTuning;

  /// Switches the generated-stroke path in an explicitly instrumented build.
  ///
  /// Production builds reject this unless compiled with
  /// `LOVE2D_GPU_RUNTIME_STROKE_TUNING=true`, allowing the compiler to remove
  /// the legacy control path from ordinary builds.
  void setTypedGeneratedStrokesForDiagnostics(bool enabled) {
    _renderer.setTypedGeneratedStrokesForDiagnostics(enabled);
  }

  /// Whether eligible odd-width rough lines use the native pixel shader.
  bool get usesRoughLineShader => _renderer.usesRoughLineShader;

  /// Whether this build permits live rough-line shader A/B switching.
  bool get supportsRuntimeRoughLineShaderTuning =>
      _renderer.supportsRuntimeRoughLineShaderTuning;

  void setRoughLineShaderForDiagnostics(bool enabled) {
    _renderer.setRoughLineShaderForDiagnostics(enabled);
  }

  /// Whether exact half-open rectangles render eligible axis-aligned rough lines.
  bool get usesRoughAxisRuns => _renderer.usesRoughAxisRuns;

  /// Whether this build permits live exact-axis-run A/B switching.
  bool get supportsRuntimeRoughAxisRunTuning =>
      _renderer.supportsRuntimeRoughAxisRunTuning;

  void setRoughAxisRunsForDiagnostics(bool enabled) {
    _renderer.setRoughAxisRunsForDiagnostics(enabled);
  }

  /// Whether sprite and particle quads use reusable direct affine expansion.
  bool get usesDirectSpriteGeometry => _renderer.usesDirectSpriteGeometry;

  /// Whether this build permits live sprite-geometry A/B switching.
  bool get supportsRuntimeSpriteGeometryTuning =>
      _renderer.supportsRuntimeSpriteGeometryTuning;

  /// Switches the sprite-geometry path in an explicitly instrumented build.
  ///
  /// Production builds reject this unless compiled with
  /// `LOVE2D_GPU_RUNTIME_SPRITE_GEOMETRY_TUNING=true`, allowing the compiler
  /// to remove the legacy expansion path from ordinary builds.
  void setDirectSpriteGeometryForDiagnostics(bool enabled) {
    _renderer.setDirectSpriteGeometryForDiagnostics(enabled);
  }

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
