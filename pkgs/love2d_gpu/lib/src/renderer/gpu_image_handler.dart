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

/// Handles GPU rendering of [LoveImageCommand] instances.
///
/// Renders an image as a textured quad (two triangles forming a rectangle).
/// The quad geometry is generated from the image's source rectangle and the
/// command's draw transform.
///
/// ## Quad geometry
///
/// ```
/// (0,0) ─── (1,0)
///   │         │
///   │    X    │    Two triangles (0,1,2 and 1,3,2)
///   │         │
/// (0,1) ─── (1,1)
/// ```
///
/// The quad is transformed by the command's `drawTransform` matrix and mapped
/// to the image's source rectangle via UV coordinates.
class GpuImageHandler {
  /// Creates an image handler.
  const GpuImageHandler({
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
  /// The image texture must be pre-uploaded via [GpuTextureCache.preWarmCommands]
  /// before calling this. Returns `false` if the texture is not yet cached.
  bool renderSync(
    gpu.RenderPass renderPass,
    LoveImageCommand command,
    ui.Size viewportSize,
  ) {
    final image = command.image;
    final texture = _textureCache.getCachedLoveImage(image);
    if (texture == null) return false;

    final quad = command.quad;
    final quadX = quad?.x ?? 0;
    final quadY = quad?.y ?? 0;
    final quadW = quad?.width ?? image.width.toDouble();
    final quadH = quad?.height ?? image.height.toDouble();

    final imageW = image.width.toDouble();
    final imageH = image.height.toDouble();
    final u1 = (quadX + quadW) / imageW;
    final v1 = (quadY + quadH) / imageH;

    // Quad rendered as two triangles (six vertices), avoiding indexed draws.
    final vertices = Float32List(6 * 8);
    var offset = 0;
    void write(double x, double y, double u, double v) {
      vertices[offset++] = x;
      vertices[offset++] = y;
      vertices[offset++] = u;
      vertices[offset++] = v;
      vertices[offset++] = 1.0;
      vertices[offset++] = 1.0;
      vertices[offset++] = 1.0;
      vertices[offset++] = 1.0;
    }

    write(0.0, 0.0, quadX / imageW, quadY / imageH);
    write(quadW, 0.0, u1, quadY / imageH);
    write(0.0, quadH, quadX / imageW, v1);
    write(quadW, 0.0, u1, quadY / imageH);
    write(quadW, quadH, u1, v1);
    write(0.0, quadH, quadX / imageW, v1);

    final vertexBuffer = _hostBufferPool.emplaceFloat32List(vertices);

    final pipeline = _pipelineCache.get(
      const PipelineKey(vertexStride: 32, isTextured: true),
    );
    renderPass.bindPipeline(pipeline);
    applyGpuDrawState(renderPass, command, viewportSize);
    bindVertexBufferCompat(renderPass, vertexBuffer);

    final fullTransform = vm.Matrix4.fromList(
      command.transform.storage.toList(),
    )..multiply(vm.Matrix4.fromList(command.drawTransform.storage.toList()));
    final mvp = _buildMVP(fullTransform, viewportSize);
    final vertInfo = _hostBufferPool.emplaceVertInfo(
      mvp,
      vm.Vector4(1, 1, 1, 1),
    );
    final vertInfoSlot = pipeline.vertexShader.getUniformSlot('VertInfo');
    renderPass.bindUniform(vertInfoSlot, vertInfo);

    // Bind texture
    final textureSlot = pipeline.fragmentShader.getUniformSlot(
      'texture_sampler',
    );
    renderPass.bindTexture(textureSlot, texture, sampler: kNearestClampSampler);

    drawVerticesCompat(renderPass, 6);

    return true;
  }

  vm.Matrix4 _buildMVP(vm.Matrix4 transform, ui.Size viewportSize) {
    final w = viewportSize.width;
    final h = viewportSize.height;
    if (w <= 0 || h <= 0) return vm.Matrix4.identity();

    // Column-major orthographic projection: LOVE screen-space → NDC.
    final proj = vm.Matrix4.columns(
      vm.Vector4(2 / w, 0, 0, 0),
      vm.Vector4(0, -2 / h, 0, 0),
      vm.Vector4(0, 0, 1, 0),
      vm.Vector4(-1, 1, 0, 1),
    );
    return proj * transform;
  }
}
