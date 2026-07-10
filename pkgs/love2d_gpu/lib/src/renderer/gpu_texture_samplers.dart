import 'package:flutter_gpu/gpu.dart' as gpu;

/// Shared sampler state for 2D LOVE textures.
///
/// Matches the flutter_scene pattern of binding an explicit clamp sampler for
/// every sampled texture, avoiding backend defaults that may enable mip lookup
/// or other unwanted sampling state.
final gpu.SamplerOptions kNearestClampSampler = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);
