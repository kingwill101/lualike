import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

final Expando<gpu.SamplerOptions> _loveImageSamplers =
    Expando<gpu.SamplerOptions>('loveGpuImageSampler');

/// Optional diagnostic compensation for flutter_gpu mip selection.
///
/// LOVE's OpenGL renderer applies `-mipmapSharpness` as the texture LOD bias.
/// Centered linear mip generation matches LOVE without an additional backend
/// bias. The compile-time override keeps older negative-bias captures and
/// future driver comparisons reproducible without changing source.
final double loveGpuMipmapLodCompensation =
    double.tryParse(
      const String.fromEnvironment(
        'LOVE2D_GPU_MIPMAP_LOD_COMPENSATION',
        defaultValue: '0',
      ),
    ) ??
    0.0;

/// Whether the flutter_gpu compensation fades out near the base mip level.
const bool loveGpuAdaptiveMipmapLodCompensation = bool.fromEnvironment(
  'LOVE2D_GPU_ADAPTIVE_MIPMAP_LOD_COMPENSATION',
  defaultValue: true,
);

/// Returns the fragment sampling bias for [image].
///
/// Textures without a mip chain use the base level and therefore receive no
/// compensation. When [effectiveScale] is supplied, the adaptive path leaves
/// near-base-level sampling unchanged and smoothly reaches the full
/// compensation between 0.5x and 0.25x minification. [compensation] and
/// [adaptiveCompensation] are injectable for focused tests.
double gpuMipmapLodBiasForLoveImage(
  LoveImage image, {
  double? compensation,
  double? effectiveScale,
  bool? adaptiveCompensation,
}) {
  if (image.mipmapCount <= 1) return 0.0;
  final resolvedCompensation = compensation ?? loveGpuMipmapLodCompensation;
  final useAdaptive =
      adaptiveCompensation ?? loveGpuAdaptiveMipmapLodCompensation;
  if (!useAdaptive || effectiveScale == null || !effectiveScale.isFinite) {
    return -image.mipmapSharpness + resolvedCompensation;
  }
  final weight = ((0.5 - effectiveScale) / 0.25).clamp(0.0, 1.0);
  return -image.mipmapSharpness + (resolvedCompensation * weight);
}

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
    mipFilter: _gpuMipFilter(image.mipmapFilter),
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

gpu.MipFilter _gpuMipFilter(LoveGraphicsFilterMode? filter) => switch (filter) {
  LoveGraphicsFilterMode.linear => gpu.MipFilter.linear,
  LoveGraphicsFilterMode.nearest || null => gpu.MipFilter.nearest,
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
