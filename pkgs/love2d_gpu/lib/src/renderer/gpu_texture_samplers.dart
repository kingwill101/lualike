import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

final Expando<gpu.SamplerOptions> _loveImageSamplers =
    Expando<gpu.SamplerOptions>('loveGpuImageSampler');

/// Returns immutable-in-practice GPU sampler state matching [image].
///
/// LOVE stores minification, magnification, and wrap modes on each texture.
/// The GPU renderer must bind those values explicitly because flutter_gpu's
/// defaults are nearest/clamp and therefore do not match LOVE's default
/// linear filtering. The result is cached by immutable [LoveImage] identity so
/// hot draw paths do not allocate a sampler every frame.
gpu.SamplerOptions gpuSamplerForLoveImage(LoveImage image) {
  final cached = _loveImageSamplers[image];
  if (cached != null) {
    return cached;
  }

  final sampler = gpu.SamplerOptions(
    minFilter: _gpuFilter(image.filter.min),
    magFilter: _gpuFilter(image.filter.mag),
    // GpuTextureCache currently uploads the base level only. Keep mip lookup
    // on that level until the cache uploads LOVE's mip chain as well.
    mipFilter: gpu.MipFilter.nearest,
    widthAddressMode: _gpuAddressMode(image.wrap.horizontal),
    heightAddressMode: _gpuAddressMode(image.wrap.vertical),
  );
  _loveImageSamplers[image] = sampler;
  return sampler;
}

gpu.MinMagFilter _gpuFilter(LoveGraphicsFilterMode filter) => switch (filter) {
  LoveGraphicsFilterMode.linear => gpu.MinMagFilter.linear,
  LoveGraphicsFilterMode.nearest => gpu.MinMagFilter.nearest,
};

gpu.SamplerAddressMode _gpuAddressMode(LoveGraphicsWrapMode wrap) {
  return switch (wrap) {
    LoveGraphicsWrapMode.repeat => gpu.SamplerAddressMode.repeat,
    LoveGraphicsWrapMode.mirroredRepeat => gpu.SamplerAddressMode.mirror,
    // flutter_gpu has no transparent-border address mode. Clamp-to-edge is
    // the closest available behavior for LOVE's clampzero mode.
    LoveGraphicsWrapMode.clamp ||
    LoveGraphicsWrapMode.clampZero => gpu.SamplerAddressMode.clampToEdge,
  };
}
