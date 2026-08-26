import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

/// Caches [gpu.Texture] objects uploaded from [ui.Image] sources.
///
/// LOVE images arrive as [ui.Image] via `LoveImage.nativeImage`. The GPU
/// backend needs a [gpu.Texture] for sampling in fragment shaders.
///
/// ## Two-phase access
///
/// Texture upload ([ui.Image.toByteData] → [gpu.Texture.overwrite]) is
/// asynchronous. The cache separates lookup from upload:
///
/// - **[getCached]** — synchronous, returns the texture if already uploaded.
/// - **[upload]** — async, uploads pixels and caches the result.
/// - **[preWarmFrame]** — async, pre-uploads all textures needed by a frame's
///   commands. Call this before [GpuCommandRenderer.renderFrame].
///
/// During rendering, commands whose textures are not yet cached are skipped
/// (return `false` from the handler), causing them to fall back to Canvas.
class GpuTextureCache {
  /// Creates a texture cache rooted at [gpuContext].
  GpuTextureCache(this._gpuContext);

  final gpu.GpuContext _gpuContext;
  // Identity maps avoid constructing a composite string key on every draw.
  // LOVE may create a lightweight copyWith wrapper when filter or wrap state
  // changes, so the image-data/native-image maps retain texture reuse across
  // those wrappers as well as the common stable LoveImage identity path.
  final Map<LoveImage, _CachedTexture> _loveImageCache =
      Map<LoveImage, _CachedTexture>.identity();
  final Map<LoveImageData, _CachedTexture> _imageDataCache =
      Map<LoveImageData, _CachedTexture>.identity();
  final Map<ui.Image, _CachedTexture> _uiImageCache =
      Map<ui.Image, _CachedTexture>.identity();

  /// Returns a cached [gpu.Texture] for [image], or `null` if not yet uploaded.
  ///
  /// This is synchronous — use it during the render phase.
  gpu.Texture? getCached(ui.Image? image) {
    if (image == null) return null;
    return _uiImageCache[image]?.texture;
  }

  /// Returns a cached [gpu.Texture] for a [LoveImage], or null if not cached.
  gpu.Texture? getCachedLoveImage(LoveImage image) {
    final direct = _loveImageCache[image];
    if (direct != null) {
      return direct.texture;
    }
    final nativeImage = image.nativeImage;
    if (nativeImage is ui.Image) {
      final native = _uiImageCache[nativeImage];
      if (native != null) {
        _loveImageCache[image] = native;
        return native.texture;
      }
    }
    final imageData = image.imageData;
    if (imageData != null) {
      final decoded = _imageDataCache[imageData];
      if (decoded != null) {
        _loveImageCache[image] = decoded;
        return decoded.texture;
      }
    }
    return null;
  }

  /// Asynchronously uploads [image] to a [gpu.Texture] and caches the result.
  ///
  /// Once uploaded, [getCached] returns the texture synchronously.
  Future<gpu.Texture?> upload(ui.Image? image) async {
    if (image == null) return null;
    if (image.width <= 0 || image.height <= 0) return null;

    final existing = _uiImageCache[image];
    if (existing != null && identical(existing.source, image)) {
      return existing.texture;
    }

    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (byteData == null) return null;

    final texture = _gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      image.width,
      image.height,
    );

    texture.overwrite(byteData.buffer.asByteData());
    _uiImageCache[image] = _CachedTexture(
      source: image,
      texture: texture,
    );
    return texture;
  }

  /// Pre-uploads all textures referenced by [commands].
  ///
  /// Call this at the start of each frame if you want to maximize the number
  /// of commands that the GPU path can handle.
  Future<void> preWarmCommands(List<LoveDrawCommand> commands) async {
    final futures = <Future<void>>[];
    for (final cmd in commands) {
      switch (cmd) {
        case LoveMeshCommand(:final mesh):
          final texObj = mesh.textureObject;
          if (texObj is LoveImage) {
            futures.add(_uploadNativeImage(texObj.nativeImage));
          }
        case LoveImageCommand(:final image):
          futures.add(_uploadNativeImage(image.nativeImage));
        case LoveSpriteBatchCommand(:final spriteBatch):
          futures.add(_uploadNativeImage(spriteBatch.texture.nativeImage));
        case LoveParticleSystemCommand(:final particleSystem):
          futures.add(_uploadNativeImage(particleSystem.texture.nativeImage));
        case LoveVideoCommand _:
          // Video frames are sourced from a frame provider, not a static
          // ui.Image. Skip pre-warming — video rendering will fall back
          // to the Canvas path.
          break;
        default:
          break;
      }
    }
    await Future.wait(futures, eagerError: false);
  }

  Future<void> _uploadNativeImage(Object? nativeImage) async {
    if (nativeImage is ui.Image) {
      await upload(nativeImage);
    }
  }

  /// Synchronously uploads a [LoveImage] from its decoded [LoveImageData].
  ///
  /// Unlike [upload], which performs an async `ui.Image.toByteData()` read,
  /// this method prefers the CPU-side [LoveImage.imageData] when available so
  /// the texture upload is deterministic and synchronous.
  gpu.Texture? uploadSync(LoveImage image) {
    final nativeImage = image.nativeImage;

    // Already cached?
    final cached = getCachedLoveImage(image);
    if (cached != null) return cached;

    // Preferred path: upload from decoded LOVE image data.
    final imageData = image.imageData;
    if (imageData != null) {
      final w = imageData.width;
      final h = imageData.height;
      if (w > 0 && h > 0) {
        final pixels = Uint8List(w * h * 4);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final c = imageData.getPixel(x, y).clamped();
            final offset = ((y * w) + x) * 4;
            pixels[offset] = (c.r * 255).round();
            pixels[offset + 1] = (c.g * 255).round();
            pixels[offset + 2] = (c.b * 255).round();
            pixels[offset + 3] = (c.a * 255).round();
          }
        }

        final texture = _gpuContext.createTexture(
          gpu.StorageMode.hostVisible,
          w,
          h,
        );
        texture.overwrite(ByteData.sublistView(pixels));

        final cached = _CachedTexture(
          source: image,
          texture: texture,
        );
        _loveImageCache[image] = cached;
        _imageDataCache[imageData] = cached;
        if (nativeImage is ui.Image) {
          _uiImageCache[nativeImage] = cached;
        }
        return texture;
      }
    }

    // No synchronous ui.Image wrapping fallback here: the upload path is
    // intentionally CPU-side so the result is deterministic across backends.
    return null;
  }

  /// Removes all entries from the cache.
  void clear() {
    _loveImageCache.clear();
    _imageDataCache.clear();
    _uiImageCache.clear();
  }
}

class _CachedTexture {
  const _CachedTexture({required this.source, required this.texture});

  final Object source;
  final gpu.Texture texture;
}
