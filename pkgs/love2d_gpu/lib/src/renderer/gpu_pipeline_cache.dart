import 'package:flutter_gpu/gpu.dart' as gpu;

import '../shader/love_shader_bundle.dart';

/// Key that uniquely identifies a render pipeline variant.
final class PipelineKey {
  const PipelineKey({required this.vertexStride, required this.isTextured});

  final int vertexStride;
  final bool isTextured;

  @override
  bool operator ==(Object other) =>
      other is PipelineKey &&
      other.vertexStride == vertexStride &&
      other.isTextured == isTextured;

  @override
  int get hashCode => Object.hash(vertexStride, isTextured);
}

/// Caches [gpu.RenderPipeline] objects keyed by [PipelineKey].
class GpuPipelineCache {
  GpuPipelineCache(this._gpuContext);

  final gpu.GpuContext _gpuContext;
  final Map<PipelineKey, gpu.RenderPipeline> _cache = {};

  gpu.RenderPipeline get(PipelineKey key) {
    return _cache.putIfAbsent(key, () => _createPipeline(key));
  }

  gpu.RenderPipeline _createPipeline(PipelineKey key) {
    final vertexShader = LoveShaderBundles.baseVertex;
    final fragmentShader = key.isTextured
        ? LoveShaderBundles.texturedFragment
        : LoveShaderBundles.unlitFragment;
    return _gpuContext.createRenderPipeline(vertexShader, fragmentShader);
  }

  /// Sprite batching currently expands to ordinary textured quads on the CPU,
  /// so it reuses the textured mesh pipeline.
  gpu.RenderPipeline getSpriteBatchPipeline() {
    return get(const PipelineKey(vertexStride: 32, isTextured: true));
  }

  void clear() => _cache.clear();
}
