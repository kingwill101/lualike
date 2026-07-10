import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Manages a pool of offscreen [gpu.Texture] objects used as render targets.
///
/// flutter_gpu has no swapchain or platform surface abstraction. Instead, we
/// render into GPU textures and present the result to Flutter via
/// [gpu.Texture.asImage], which returns a [ui.Image] that can be drawn onto
/// the Flutter canvas with `Canvas.drawImageRect`.
///
/// ## Lifecycle
///
/// Each frame:
/// 1. [acquire] returns a [Frame] with color + depth-stencil textures sized
///    to the viewport.
/// 2. The caller renders into the [gpu.RenderPass] created from [Frame]'s
///    textures.
/// 3. [Frame.present] submits the command buffer, converts the color texture
///    to a [ui.Image], and draws it on the Flutter canvas.
///
/// The pool reuses textures across frames to avoid per-frame GPU allocation.
/// Textures are grown when the viewport expands but never shrunk. Presented
/// images are retired a frame later (or after the rasterizer confirms they are
/// no longer needed) so live textures are never disposed too early.
///
/// ## Why a pool instead of create-per-frame?
///
/// Creating a [gpu.Texture] every frame would allocate GPU memory each time
/// and require GC collection of the old one. LOVE targets 60 fps, so pooling
/// eliminates per-frame allocation churn.
class GpuSurfaceManager {
  /// Creates a surface manager rooted at [gpuContext].
  GpuSurfaceManager(this._gpuContext);

  static const _retiredCapacity = 8;

  final gpu.GpuContext _gpuContext;

  gpu.Texture? _colorTexture;
  gpu.Texture? _depthStencilTexture;
  ui.Image? _currentImage;
  final List<(ui.Image, int)> _retiredImages = [];
  bool _timingsHooked = false;
  int _cachedWidth = 0;
  int _cachedHeight = 0;

  /// Returns a [Frame] containing color and depth-stencil textures sized to
  /// [width]×[height].
  ///
  /// The caller should create a [gpu.RenderPass] from the frame, issue draw
  /// calls, and then call [Frame.present] to blit the result to the canvas.
  /// Textures are reused across frames for the same viewport size.
  Frame acquire(int width, int height) {
    _ensureSize(width, height);
    return Frame._(
      manager: this,
      colorTexture: _colorTexture!,
      depthStencilTexture: _depthStencilTexture!,
    );
  }

  void _ensureSize(int width, int height) {
    if (_cachedWidth == width && _cachedHeight == height) {
      return;
    }

    _colorTexture = _gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );

    _depthStencilTexture = _gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      width,
      height,
      format: gpu.PixelFormat.d24UnormS8Uint,
    );

    _cachedWidth = width;
    _cachedHeight = height;
  }

  /// Releases the pooled GPU textures.
  ///
  /// Call this when the backend is disposed or when the viewport is known to
  /// have changed permanently (e.g., window resize). The next [acquire] call
  /// will create fresh textures.
  void release() {
    _colorTexture = null;
    _depthStencilTexture = null;
    _cachedWidth = 0;
    _cachedHeight = 0;
  }

  /// Releases all retained frame images and unregisters the timing callback.
  ///
  /// Call this when the backend is disposed. Images still referenced by the
  /// rasterizer are retired first; anything left is disposed immediately.
  void dispose() {
    release();
    _currentImage?.dispose();
    _currentImage = null;
    for (final (image, _) in _retiredImages) {
      image.dispose();
    }
    _retiredImages.clear();
    if (_timingsHooked) {
      _timingsHooked = false;
      SchedulerBinding.instance.removeTimingsCallback(_flushRetired);
    }
  }

  void _presentImage(ui.Image image) {
    final previous = _currentImage;
    if (previous != null) {
      _retireImage(previous);
    }
    _currentImage = image;
    if (!_timingsHooked) {
      _timingsHooked = true;
      SchedulerBinding.instance.addTimingsCallback(_flushRetired);
    }
  }

  void _retireImage(ui.Image image) {
    while (_retiredImages.length >= _retiredCapacity) {
      _retiredImages.removeAt(0).$1.dispose();
    }
    _retiredImages.add((
      image,
      ui.PlatformDispatcher.instance.frameData.frameNumber,
    ));
  }

  void _flushRetired(List<ui.FrameTiming> timings) {
    var latest = -1;
    for (final timing in timings) {
      if (timing.frameNumber > latest) latest = timing.frameNumber;
    }
    while (_retiredImages.isNotEmpty && _retiredImages.first.$2 <= latest) {
      _retiredImages.removeAt(0).$1.dispose();
    }
    if (_retiredImages.isEmpty && _timingsHooked) {
      _timingsHooked = false;
      SchedulerBinding.instance.removeTimingsCallback(_flushRetired);
    }
  }
}

/// A single frame's worth of GPU resources.
///
/// Wraps the color and depth-stencil textures for one render pass. After the
/// caller has issued draw calls through a [gpu.CommandBuffer], calling
/// [present] submits the work and draws the rendered image onto the Flutter
/// canvas via [gpu.Texture.asImage].
///
/// ## Present flow
///
/// ```
/// Frame.present(commandBuffer, canvas, viewportSize)
///   ├── commandBuffer.submit()
///   ├── _colorTexture.asImage()  →  ui.Image
///   └── canvas.drawImageRect(image, srcRect, dstRect, Paint())
/// ```
class Frame {
  Frame._({
    required GpuSurfaceManager manager,
    required gpu.Texture colorTexture,
    required gpu.Texture depthStencilTexture,
  }) : _manager = manager,
       _colorTexture = colorTexture,
       _depthStencilTexture = depthStencilTexture;

  final GpuSurfaceManager _manager;
  final gpu.Texture _colorTexture;
  final gpu.Texture _depthStencilTexture;

  /// The color texture used as the render target attachment.
  ///
  /// Exposed so callers can construct a [gpu.RenderTarget] with this as the
  /// color attachment.
  gpu.Texture get colorTexture => _colorTexture;

  /// The depth-stencil texture used as the depth/stencil attachment.
  gpu.Texture get depthStencilTexture => _depthStencilTexture;

  /// Submits [commandBuffer], converts the color texture to a [ui.Image], and
  /// draws it onto [canvas] filling the LOVE viewport rectangle.
  void present(
    gpu.CommandBuffer commandBuffer,
    ui.Canvas canvas,
    ui.Size viewportSize,
  ) {
    commandBuffer.submit();
    final ui.Image image = _colorTexture.asImage();
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, viewportSize.width, viewportSize.height),
      ui.Paint(),
    );
    _manager._presentImage(image);
  }
}
