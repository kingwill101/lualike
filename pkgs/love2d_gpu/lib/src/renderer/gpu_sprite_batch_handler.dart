import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'gpu_api_compat.dart';
import 'gpu_draw_state.dart';
import 'gpu_host_buffer_pool.dart';
import 'gpu_pipeline_cache.dart';
import 'gpu_texture_cache.dart';
import 'gpu_texture_samplers.dart';

const _triVertexOrder = <int>[0, 1, 2, 1, 3, 2];
const _quadPositions = <({double x, double y})>[
  (x: 0.0, y: 0.0),
  (x: 1.0, y: 0.0),
  (x: 0.0, y: 1.0),
  (x: 1.0, y: 1.0),
];

/// Handles GPU rendering of [LoveSpriteBatchCommand] instances.
///
/// A sprite batch contains multiple sprites that share the same texture.
/// The GPU path expands each sprite into a textured quad on the CPU and draws
/// the resulting triangle list in one call.
class GpuSpriteBatchHandler {
  /// Creates a sprite batch handler.
  const GpuSpriteBatchHandler({
    required GpuPipelineCache pipelineCache,
    required GpuTextureCache textureCache,
    required GpuHostBufferPool hostBufferPool,
  }) : _pipelineCache = pipelineCache,
       _textureCache = textureCache,
       _hostBufferPool = hostBufferPool;

  final GpuPipelineCache _pipelineCache;
  final GpuTextureCache _textureCache;
  final GpuHostBufferPool _hostBufferPool;

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
      sampler: kNearestClampSampler,
    );

    applyGpuDrawState(renderPass, command, viewportSize);

    // VertInfo uniform with MVP mapping LOVE screen-space to NDC.
    // Vertices are pre-transformed to screen-space by _transformPoint,
    // so the projection must convert screen-space → NDC with identity
    // model transform.
    final vertInfo = _hostBufferPool.emplaceVertInfo(
      _screenSpaceMVP(viewportSize),
      vm.Vector4(1, 1, 1, 1),
    );
    final vertInfoSlot = pipeline.vertexShader.getUniformSlot('VertInfo');
    renderPass.bindUniform(vertInfoSlot, vertInfo);

    final batchBase = vm.Matrix4.copy(command.transform)
      ..multiply(command.drawTransform);

    final vertices = Float32List(sprites.length * 6 * 8);
    var vertexOffset = 0;

    for (final sprite in sprites) {
      final quad = sprite.quad;
      final imageWidth = quad?.textureWidth ?? loveImage.width.toDouble();
      final imageHeight = quad?.textureHeight ?? loveImage.height.toDouble();
      final quadWidth = quad?.width ?? imageWidth;
      final quadHeight = quad?.height ?? imageHeight;
      final uvX = (quad?.x ?? 0.0) / imageWidth;
      final uvY = (quad?.y ?? 0.0) / imageHeight;
      final uvScaleX = quadWidth / imageWidth;
      final uvScaleY = quadHeight / imageHeight;

      final scale = vm.Matrix4.diagonal3Values(quadWidth, quadHeight, 1.0);
      final instanceTransform = vm.Matrix4.copy(batchBase)
        ..multiply(sprite.transform)
        ..multiply(scale);

      final tint = sprite.color == null
          ? command.color
          : LoveColor(
              command.color.r * sprite.color!.r,
              command.color.g * sprite.color!.g,
              command.color.b * sprite.color!.b,
              command.color.a * sprite.color!.a,
            );

      for (final index in _triVertexOrder) {
        final point = _quadPositions[index];
        final transformed = _transformPoint(
          instanceTransform,
          point.x,
          point.y,
        );
        vertices[vertexOffset++] = transformed.dx;
        vertices[vertexOffset++] = transformed.dy;
        vertices[vertexOffset++] = point.x * uvScaleX + uvX;
        vertices[vertexOffset++] = point.y * uvScaleY + uvY;
        vertices[vertexOffset++] = tint.r;
        vertices[vertexOffset++] = tint.g;
        vertices[vertexOffset++] = tint.b;
        vertices[vertexOffset++] = tint.a;
      }
    }

    final vertexBuffer = _hostBufferPool.emplaceFloat32List(vertices);
    bindVertexBufferCompat(renderPass, vertexBuffer);
    drawVerticesCompat(renderPass, vertices.length ~/ 8);

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
      sampler: kNearestClampSampler,
    );

    final batchBase = vm.Matrix4.copy(command.transform)
      ..multiply(command.drawTransform);

    final imageWidth = loveImage.width.toDouble();
    final imageHeight = loveImage.height.toDouble();
    final vertices = Float32List(particles.length * 6 * 8);
    var vertexOffset = 0;

    for (final particle in particles) {
      final quad = particle.quad;
      final quadWidth = quad?.width ?? imageWidth;
      final quadHeight = quad?.height ?? imageHeight;
      final uvX = (quad?.x ?? 0.0) / imageWidth;
      final uvY = (quad?.y ?? 0.0) / imageHeight;
      final uvScaleX = quadWidth / imageWidth;
      final uvScaleY = quadHeight / imageHeight;

      final scale = vm.Matrix4.diagonal3Values(quadWidth, quadHeight, 1.0);
      final particleTransform = vm.Matrix4.copy(batchBase)
        ..multiply(particle.transform)
        ..multiply(scale);

      final tint = LoveColor(
        command.color.r * particle.color.r,
        command.color.g * particle.color.g,
        command.color.b * particle.color.b,
        command.color.a * particle.color.a,
      );

      for (final index in _triVertexOrder) {
        final point = _quadPositions[index];
        final transformed = _transformPoint(
          particleTransform,
          point.x,
          point.y,
        );
        vertices[vertexOffset++] = transformed.dx;
        vertices[vertexOffset++] = transformed.dy;
        vertices[vertexOffset++] = point.x * uvScaleX + uvX;
        vertices[vertexOffset++] = point.y * uvScaleY + uvY;
        vertices[vertexOffset++] = tint.r;
        vertices[vertexOffset++] = tint.g;
        vertices[vertexOffset++] = tint.b;
        vertices[vertexOffset++] = tint.a;
      }
    }

    final vertexBuffer = _hostBufferPool.emplaceFloat32List(vertices);
    bindVertexBufferCompat(renderPass, vertexBuffer);
    drawVerticesCompat(renderPass, vertices.length ~/ 8);

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

  ui.Offset _transformPoint(vm.Matrix4 matrix, double x, double y) {
    final s = matrix.storage;
    return ui.Offset(s[0] * x + s[4] * y + s[12], s[1] * x + s[5] * y + s[13]);
  }
}
