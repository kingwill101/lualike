import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

/// Whether LOVE-authored mip chains are uploaded to flutter_gpu textures.
///
/// Set `LOVE2D_GPU_MIPMAP_UPLOADS=false` for a base-level-only A/B build.
const bool loveGpuMipmapUploadsEnabled = bool.fromEnvironment(
  'LOVE2D_GPU_MIPMAP_UPLOADS',
  defaultValue: true,
);

/// Selects the valid prefix of [image]'s decoded mip chain for GPU upload.
///
/// Flutter GPU currently imposes its own [maxMipLevels] bound. Malformed or
/// missing levels truncate the chain instead of risking an invalid texture.
List<LoveImageData> gpuMipLevelsForLoveImage(
  LoveImage image, {
  required bool uploadsEnabled,
  required bool manuallyMippedTexturesSupported,
  required int maxMipLevels,
}) {
  final base = image.imageData;
  if (base == null) {
    return const <LoveImageData>[];
  }

  final levels = <LoveImageData>[base];
  final mipmaps = image.imageDataMipmaps;
  if (!uploadsEnabled ||
      !manuallyMippedTexturesSupported ||
      maxMipLevels <= 1 ||
      image.mipmapCount <= 1 ||
      mipmaps == null ||
      mipmaps.length <= 1) {
    return levels;
  }

  final levelLimit = <int>[
    maxMipLevels,
    image.mipmapCount,
    mipmaps.length,
  ].reduce((left, right) => left < right ? left : right);
  for (var level = 1; level < levelLimit; level++) {
    final candidate = mipmaps[level];
    final expectedWidth = (base.width >> level).clamp(1, base.width);
    final expectedHeight = (base.height >> level).clamp(1, base.height);
    if (candidate.width != expectedWidth ||
        candidate.height != expectedHeight) {
      break;
    }
    levels.add(candidate);
  }
  return levels;
}

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
  GpuTextureCache(
    this._gpuContext, {
    bool mipmapUploadsEnabled = loveGpuMipmapUploadsEnabled,
  }) : _mipmapUploadsEnabled = mipmapUploadsEnabled,
       _manuallyMippedTexturesSupported =
           _gpuContext.doesSupportManuallyMippedTextures;

  final gpu.GpuContext _gpuContext;
  final bool _mipmapUploadsEnabled;
  final bool _manuallyMippedTexturesSupported;
  // Expandos provide identity-keyed lookup without making the source objects
  // cache roots. LOVE may create a lightweight copyWith wrapper when filter or
  // wrap state changes, so the image-data/native-image associations retain
  // texture reuse across those wrappers. Once a discarded runtime no longer
  // owns any of the three source identities, the singleton GPU backend no
  // longer keeps its decoded image data and mip chain alive.
  Expando<_CachedTexture> _loveImageCache = Expando<_CachedTexture>(
    'love2d_gpu.LoveImage textures',
  );
  Expando<_CachedTexture> _imageDataCache = Expando<_CachedTexture>(
    'love2d_gpu.LoveImageData textures',
  );
  Expando<_CachedTexture> _uiImageCache = Expando<_CachedTexture>(
    'love2d_gpu.ui.Image textures',
  );

  /// Whether this build allows LOVE-authored mipmap uploads.
  bool get mipmapUploadsEnabled => _mipmapUploadsEnabled;

  /// Whether the current GPU backend can safely sample manual mip chains.
  bool get manuallyMippedTexturesSupported => _manuallyMippedTexturesSupported;

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
    final imageData = image.imageData;
    if (imageData != null) {
      final decoded = _imageDataCache[imageData];
      if (decoded != null &&
          decoded.texture.mipLevelCount == _mipLevelsFor(image).length) {
        _loveImageCache[image] = decoded;
        return decoded.texture;
      }
    }
    final nativeImage = image.nativeImage;
    if (nativeImage is ui.Image) {
      final native = _uiImageCache[nativeImage];
      if (native != null && _mipLevelsFor(image).length == 1) {
        _loveImageCache[image] = native;
        return native.texture;
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
    if (existing != null) {
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
    _uiImageCache[image] = _CachedTexture(texture);
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
            futures.add(_preWarmLoveImage(texObj));
          }
        case LoveImageCommand(:final image):
          futures.add(_preWarmLoveImage(image));
        case LoveSpriteBatchCommand(:final spriteBatch):
          futures.add(_preWarmLoveImage(spriteBatch.texture));
        case LoveParticleSystemCommand(:final particleSystem):
          futures.add(_preWarmLoveImage(particleSystem.texture));
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

  Future<void> _preWarmLoveImage(LoveImage image) async {
    if (image.imageData != null) {
      uploadSync(image);
      return;
    }
    await _uploadNativeImage(image.nativeImage);
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
        final mipLevels = _mipLevelsFor(image);

        final texture = _gpuContext.createTexture(
          gpu.StorageMode.hostVisible,
          w,
          h,
          mipLevelCount: mipLevels.length,
        );
        for (var level = 0; level < mipLevels.length; level++) {
          texture.overwrite(
            ByteData.sublistView(mipLevels[level].toRgbaBytes()),
            mipLevel: level,
          );
        }

        final cached = _CachedTexture(texture);
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

  List<LoveImageData> _mipLevelsFor(LoveImage image) {
    return gpuMipLevelsForLoveImage(
      image,
      uploadsEnabled: _mipmapUploadsEnabled,
      manuallyMippedTexturesSupported: _manuallyMippedTexturesSupported,
      maxMipLevels: gpu.Texture.fullMipCount(
        image.imageData?.width ?? image.pixelWidth,
        image.imageData?.height ?? image.pixelHeight,
      ),
    );
  }

  /// Removes all entries from the cache.
  void clear() {
    _loveImageCache = Expando<_CachedTexture>('love2d_gpu.LoveImage textures');
    _imageDataCache = Expando<_CachedTexture>(
      'love2d_gpu.LoveImageData textures',
    );
    _uiImageCache = Expando<_CachedTexture>('love2d_gpu.ui.Image textures');
  }
}

class _CachedTexture {
  const _CachedTexture(this.texture);

  final gpu.Texture texture;
}
