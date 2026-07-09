/// Render backend abstraction for LOVE2D.
///
/// The default [LoveCanvasRenderBackend] uses Flutter's Canvas 2D API.
/// The experimental [LoveGpuRenderBackend] uses [package:flutter_gpu].
library;

export 'love_render_backend.dart';
export 'love_canvas_render_backend.dart';
export 'love_gpu_render_backend.dart';
