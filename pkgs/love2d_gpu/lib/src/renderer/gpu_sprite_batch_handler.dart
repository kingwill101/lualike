import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'gpu_api_compat.dart';
import 'gpu_draw_state.dart';
import 'gpu_host_buffer_pool.dart';
import 'gpu_pipeline_cache.dart';
import 'gpu_sprite_geometry.dart';
import 'gpu_texture_cache.dart';
import 'gpu_texture_samplers.dart';

const bool _kDefaultDirectSpriteGeometry = bool.fromEnvironment(
  'LOVE2D_GPU_DIRECT_SPRITE_GEOMETRY',
  defaultValue: true,
);
const bool _kRuntimeSpriteGeometryTuning = bool.fromEnvironment(
  'LOVE2D_GPU_RUNTIME_SPRITE_GEOMETRY_TUNING',
  defaultValue: false,
);

/// Handles GPU rendering of [LoveSpriteBatchCommand] instances.
///
/// A sprite batch contains multiple sprites that share the same texture.
/// The GPU path expands each sprite into a textured quad on the CPU and draws
/// the resulting triangle list in one call.
class GpuSpriteBatchHandler {
  /// Creates a sprite batch handler.
  GpuSpriteBatchHandler({
    required GpuPipelineCache pipelineCache,
    required GpuTextureCache textureCache,
    required GpuHostBufferPool hostBufferPool,
  }) : _pipelineCache = pipelineCache,
       _textureCache = textureCache,
       _hostBufferPool = hostBufferPool;

  final GpuPipelineCache _pipelineCache;
  final GpuTextureCache _textureCache;
  final GpuHostBufferPool _hostBufferPool;
  final GpuSpriteGeometryBuilder _geometryBuilder = GpuSpriteGeometryBuilder();
  bool _runtimeDirectSpriteGeometry = _kDefaultDirectSpriteGeometry;

  bool get usesDirectSpriteGeometry => _kRuntimeSpriteGeometryTuning
      ? _runtimeDirectSpriteGeometry
      : _kDefaultDirectSpriteGeometry;

  bool get supportsRuntimeSpriteGeometryTuning => _kRuntimeSpriteGeometryTuning;

  void setDirectSpriteGeometryForDiagnostics(bool enabled) {
    if (!_kRuntimeSpriteGeometryTuning) {
      throw StateError(
        'Runtime sprite geometry tuning requires '
        'LOVE2D_GPU_RUNTIME_SPRITE_GEOMETRY_TUNING=true',
      );
    }
    _runtimeDirectSpriteGeometry = enabled;
  }

  /// Renders [command] into [renderPass] synchronously.
  ///
  /// Textures must be pre-uploaded via [GpuTextureCache.preWarmCommands].
  /// Returns `false` if the texture is not yet cached or missing.
  bool renderSync(
    gpu.RenderPass renderPass,
    LoveSpriteBatchCommand command,
    ui.Size viewportSize,
  ) {
    final batch = command.spriteBatch;
    final loveImage = batch.texture;

    final gpuTexture = _textureCache.getCachedLoveImage(loveImage);
    if (gpuTexture == null) {
      return false;
    }

    final sprites = batch.spritesToDraw();
    if (sprites.isEmpty) return false;

    final pipeline = _pipelineCache.getSpriteBatchPipeline();
    renderPass.bindPipeline(pipeline);
    // Bind texture.
    final textureSlot = pipeline.fragmentShader.getUniformSlot(
      'texture_sampler',
    );
    renderPass.bindTexture(
      textureSlot,
      gpuTexture,
      sampler: gpuSamplerForLoveImage(loveImage),
    );

    applyGpuDrawState(renderPass, command, viewportSize);

    // VertInfo uniform with MVP mapping LOVE screen-space to NDC.
    // Vertices are pre-transformed to screen-space by _transformPoint,
    // so the projection must convert screen-space → NDC with identity
    // model transform.
    final vertInfo = _hostBufferPool.emplaceVertInfo(
      _screenSpaceMVP(viewportSize),
      vm.Vector4(1, 1, 1, 1),
      mipBias: gpuMipmapLodBiasForLoveImage(loveImage),
    );
    final vertInfoSlot = pipeline.vertexShader.getUniformSlot('VertInfo');
    renderPass.bindUniform(vertInfoSlot, vertInfo);

    final directGeometry = usesDirectSpriteGeometry;
    final vertices = directGeometry
        ? _geometryBuilder.buildSprites(
            sprites: sprites,
            image: loveImage,
            commandTransform: command.transform,
            drawTransform: command.drawTransform,
            commandColor: command.color,
          )
        : buildLegacySpriteVertices(
            sprites: sprites,
            image: loveImage,
            commandTransform: command.transform,
            drawTransform: command.drawTransform,
            commandColor: command.color,
          );
    final floatLength = directGeometry
        ? _geometryBuilder.floatLength
        : vertices.length;
    final vertexBuffer = _hostBufferPool.emplaceFloat32List(
      vertices,
      length: floatLength,
    );
    bindVertexBufferCompat(renderPass, vertexBuffer);
    drawVerticesCompat(renderPass, floatLength ~/ 8);

    return true;
  }

  /// Renders a particle system command as individual textured quads.
  bool renderParticles(
    gpu.RenderPass renderPass,
    LoveParticleSystemCommand command,
    ui.Size viewportSize,
  ) {
    final particles = command.particleSystem.particles;
    if (particles.isEmpty) return false;

    final loveImage = command.particleSystem.texture;
    final gpuTexture = _textureCache.getCachedLoveImage(loveImage);
    if (gpuTexture == null) return false;

    final pipeline = _pipelineCache.getSpriteBatchPipeline();
    renderPass.bindPipeline(pipeline);
    applyGpuDrawState(renderPass, command, viewportSize);

    final textureSlot = pipeline.fragmentShader.getUniformSlot(
      'texture_sampler',
    );
    renderPass.bindTexture(
      textureSlot,
      gpuTexture,
      sampler: gpuSamplerForLoveImage(loveImage),
    );

    final vertInfo = _hostBufferPool.emplaceVertInfo(
      _screenSpaceMVP(viewportSize),
      vm.Vector4(1, 1, 1, 1),
      mipBias: gpuMipmapLodBiasForLoveImage(loveImage),
    );
    final vertInfoSlot = pipeline.vertexShader.getUniformSlot('VertInfo');
    renderPass.bindUniform(vertInfoSlot, vertInfo);

    final directGeometry = usesDirectSpriteGeometry;
    final vertices = directGeometry
        ? _geometryBuilder.buildParticles(
            particles: particles,
            image: loveImage,
            commandTransform: command.transform,
            drawTransform: command.drawTransform,
            commandColor: command.color,
          )
        : buildLegacyParticleVertices(
            particles: particles,
            image: loveImage,
            commandTransform: command.transform,
            drawTransform: command.drawTransform,
            commandColor: command.color,
          );
    final floatLength = directGeometry
        ? _geometryBuilder.floatLength
        : vertices.length;
    final vertexBuffer = _hostBufferPool.emplaceFloat32List(
      vertices,
      length: floatLength,
    );
    bindVertexBufferCompat(renderPass, vertexBuffer);
    drawVerticesCompat(renderPass, floatLength ~/ 8);

    return true;
  }

  /// Builds an MVP that maps LOVE screen-space to NDC.
  ///
  /// Vertices are already in screen-space (pre-transformed via
  /// [_transformPoint]), so the model transform is identity and only
  /// the orthographic projection is applied.
  vm.Matrix4 _screenSpaceMVP(ui.Size viewportSize) {
    final w = viewportSize.width;
    final h = viewportSize.height;
    if (w <= 0 || h <= 0) return vm.Matrix4.identity();
    // Column-major orthographic projection: LOVE screen-space → NDC.
    // Column 0: (2/w, 0, 0, 0)
    // Column 1: (0, -2/h, 0, 0)
    // Column 2: (0, 0, 1, 0)
    // Column 3: (-1, 1, 0, 1)
    return vm.Matrix4(2 / w, 0, 0, 0, 0, -2 / h, 0, 0, 0, 0, 1, 0, -1, 1, 0, 1);
  }
}
