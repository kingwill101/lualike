import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'gpu_api_compat.dart';
import 'gpu_draw_state.dart';
import 'gpu_host_buffer_pool.dart';
import 'gpu_pipeline_cache.dart';
import 'gpu_texture_cache.dart';
import 'gpu_texture_samplers.dart';

const int _loveVertexStride = 32;

/// Handles GPU rendering of [LoveMeshCommand] instances.
///
/// Converts LOVE mesh geometry (vertices with position, UV, and color) into
/// flutter_gpu vertex/index buffers and issues indexed draw calls.
///
/// ## Vertex format
///
/// Each LOVE vertex is packed as 8 consecutive floats (32 bytes):
///
/// | Offset | Type | LOVE Attribute |
/// |---|---|---|
/// | 0 | float32x2 | VertexPosition |
/// | 8 | float32x2 | VertexTexCoord |
/// | 16 | float32x4 | VertexColor |
///
/// This matches the `VertexLayout` in [GpuPipelineCache] and the `in`
/// declarations in `love_base.vert`.
///
/// ## Pipeline selection
///
/// - **Unlit pipeline**: used when the mesh has no texture (`mesh.textureObject`
///   is null). Draws vertex color only.
/// - **Textured pipeline**: used when the mesh has a texture. Samples the
///   texture at the interpolated UV coordinates and multiplies by vertex color.
///
/// ## Indexed drawing
///
/// When the mesh has a `vertexMap` (indices), the handler generates an index
/// buffer and issues [RenderPass.drawIndexed]. Otherwise, it uses
/// [RenderPass.draw] with `vertexCount`.
class GpuMeshHandler {
  /// Creates a mesh handler.
  const GpuMeshHandler({
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
  /// Textures must be pre-uploaded via [GpuTextureCache.preWarmCommands] or
  /// [GpuTextureCache.upload] before calling this. If a texture is needed but
  /// not yet cached, the command is skipped and returns `false`.
  bool renderSync(
    gpu.RenderPass renderPass,
    LoveMeshCommand command,
    ui.Size viewportSize,
  ) {
    final mesh = command.mesh;
    final vertices = mesh.verticesForDraw();
    if (vertices.isEmpty) return false;

    final isTextured = mesh.textureObject != null;
    final vertexMap = mesh.vertexMap;

    // Look up texture from cache (must be pre-warmed)
    gpu.Texture? gpuTexture;
    if (isTextured) {
      final texObj = mesh.textureObject;
      if (texObj is LoveImage) {
        gpuTexture = _textureCache.getCachedLoveImage(texObj);
        if (gpuTexture == null) return false;
      } else {
        return false;
      }
    }

    // Build vertex buffer
    final vertexBuffer = _buildVertexBuffer(vertices);

    // Build index buffer if vertex map is present
    final hasIndexBuffer = vertexMap != null && vertexMap.length >= 3;
    gpu.BufferView? indexBuffer;
    int indexCount = 0;
    if (hasIndexBuffer) {
      final indices = vertexMap.map((i) => i - 1).toList();
      indexBuffer = _hostBufferPool.emplaceIndices(indices);
      indexCount = indices.length;
    }

    // Select pipeline
    final pipeline = _pipelineCache.get(
      PipelineKey(vertexStride: _loveVertexStride, isTextured: isTextured),
    );
    renderPass.bindPipeline(pipeline);
    applyGpuDrawState(renderPass, command, viewportSize);
    renderPass.setCullMode(_cullModeForLove(command.cullMode));
    renderPass.setWindingOrder(
      command.frontFaceWinding == LoveGraphicsVertexWinding.ccw
          ? gpu.WindingOrder.counterClockwise
          : gpu.WindingOrder.clockwise,
    );
    renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);

    // Bind vertex (and optionally index) buffer
    bindVertexBufferCompat(renderPass, vertexBuffer);
    if (indexBuffer != null) {
      bindIndexBufferCompat(
        renderPass,
        indexBuffer,
        indexType: gpu.IndexType.int16,
        indexCount: indexCount,
      );
    }

    // Build and bind the VertInfo uniform (MVP + color)
    final fullTransform = vm.Matrix4.fromList(
      command.transform.storage.toList(),
    )..multiply(vm.Matrix4.fromList(command.drawTransform.storage.toList()));
    final mvp = _buildMVP(fullTransform, viewportSize);
    final color = vm.Vector4(
      command.color.r,
      command.color.g,
      command.color.b,
      command.color.a,
    );
    final vertInfo = _hostBufferPool.emplaceVertInfo(mvp, color);
    final vertInfoSlot = pipeline.vertexShader.getUniformSlot('VertInfo');
    renderPass.bindUniform(vertInfoSlot, vertInfo);

    // Bind texture if present
    if (gpuTexture != null) {
      final textureSlot = pipeline.fragmentShader.getUniformSlot(
        'texture_sampler',
      );
      renderPass.bindTexture(
        textureSlot,
        gpuTexture,
        sampler: kNearestClampSampler,
      );
    }

    // Issue draw call
    if (indexBuffer != null) {
      drawIndexedCompat(
        renderPass,
        indexCount,
        instanceCount: command.instanceCount,
      );
    } else {
      drawVerticesCompat(
        renderPass,
        vertices.length,
        instanceCount: command.instanceCount,
      );
    }

    return true;
  }

  /// Builds the combined MVP matrix from the command's transform.
  ///
  /// LOVE uses an orthographic projection where (0, 0) is the top-left corner
  /// and y increases downward. The command's `transform` encodes the model
  /// matrix. For the initial implementation, we use an orthographic projection
  /// that maps the LOVE coordinate space to clip space [-1, 1].
  ///
  /// TODO: Receive the projection matrix from the LOVE runtime instead of
  ///       hardcoding it here.
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

  gpu.CullMode _cullModeForLove(LoveGraphicsCullMode mode) {
    return switch (mode) {
      LoveGraphicsCullMode.none => gpu.CullMode.none,
      LoveGraphicsCullMode.front => gpu.CullMode.frontFace,
      LoveGraphicsCullMode.back => gpu.CullMode.backFace,
    };
  }

  gpu.BufferView _buildVertexBuffer(List<LoveMeshVertex> vertices) {
    final floats = Float32List(vertices.length * 8);
    var offset = 0;
    for (final v in vertices) {
      floats[offset++] = v.x;
      floats[offset++] = v.y;
      floats[offset++] = v.u;
      floats[offset++] = v.v;
      floats[offset++] = v.color.r;
      floats[offset++] = v.color.g;
      floats[offset++] = v.color.b;
      floats[offset++] = v.color.a;
    }
    return _hostBufferPool.emplaceFloat32List(floats);
  }
}
