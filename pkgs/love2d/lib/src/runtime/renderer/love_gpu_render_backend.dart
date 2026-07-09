import 'dart:ui' as ui;

import '../love_runtime.dart';
import 'love_render_backend.dart';

/// Experimental GPU rendering backend using [package:flutter_gpu].
///
/// This backend renders LOVE draw commands via the low-level Flutter GPU
/// API instead of the Canvas 2D pipeline. It requires:
///
/// - Flutter **master** channel
/// - Impeller enabled (`--enable-impeller`)
/// - Native assets enabled (`flutter config --enable-native-assets`)
///
/// ## Current status
///
/// This is a work-in-progress skeleton. It falls back to the Canvas backend
/// when:
/// - [package:flutter_gpu] is not available at runtime
/// - The command list contains types not yet handled by the GPU path
///
/// ## Planned command support
///
/// | Type | Priority | Status |
/// |---|---|---|
/// | `LoveMeshCommand` | P0 | Not started |
/// | `LoveSpriteBatchCommand` | P0 | Not started |
/// | `LoveParticleSystemCommand` | P0 | Not started |
/// | `LoveImageCommand` | P0 | Not started |
/// | `LoveColorClearCommand` | P0 | Not started |
/// | Shape commands | P1 | Not started |
/// | Text commands | P2 | Canvas fallback |
class LoveGpuRenderBackend implements LoveRenderBackend {
  LoveGpuRenderBackend();

  @override
  String get name => 'Flutter GPU';

  @override
  bool get isAvailable => false;

  @override
  void renderSurface(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot surface,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {
    // TODO: implement GPU rendering path.
  }
}
