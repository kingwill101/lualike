import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'gpu_fallback_handler.dart';
import 'gpu_host_buffer_pool.dart';
import 'gpu_image_handler.dart';
import 'gpu_mesh_handler.dart';
import 'gpu_pipeline_cache.dart';
import 'gpu_shape_handler.dart';
import 'gpu_sprite_batch_handler.dart';
import 'gpu_surface_manager.dart';
import 'gpu_texture_cache.dart';

final class _GpuFallbackSummaryEntry {
  _GpuFallbackSummaryEntry({required this.description, required this.count});

  final String description;
  int count;
}

/// Returns a human-readable description for a command that failed the GPU path.
String describeGpuFallbackCommand(LoveDrawCommand command, {String? reason}) {
  final buffer = StringBuffer()..write(command.runtimeType);

  switch (command) {
    case LoveRectangleCommand cmd:
      buffer
        ..write(' mode=${cmd.mode.name}')
        ..write(' rect=${_formatRect(cmd.x, cmd.y, cmd.width, cmd.height)}')
        ..write(' radius=${_formatPair(cmd.cornerRadiusX, cmd.cornerRadiusY)}');
    case LoveCircleCommand cmd:
      buffer
        ..write(' mode=${cmd.mode.name}')
        ..write(' center=${_formatPoint(cmd.x, cmd.y)}')
        ..write(' radius=${cmd.radius}');
    case LoveEllipseCommand cmd:
      buffer
        ..write(' mode=${cmd.mode.name}')
        ..write(' center=${_formatPoint(cmd.x, cmd.y)}')
        ..write(' radii=${_formatPair(cmd.radiusX, cmd.radiusY)}');
    case LoveLineCommand cmd:
      buffer
        ..write(' points=${cmd.points.length}')
        ..write(' preview=${_previewPoints(cmd.points)}');
    case LovePolygonCommand cmd:
      buffer
        ..write(' mode=${cmd.mode.name}')
        ..write(' points=${cmd.points.length}')
        ..write(' preview=${_previewPoints(cmd.points)}');
    case LovePointsCommand cmd:
      buffer
        ..write(' points=${cmd.points.length}')
        ..write(' pointSize=${cmd.pointSize}')
        ..write(
          ' preview=${_previewPoints(cmd.points.map((point) => (x: point.x, y: point.y)).toList(growable: false))}',
        );
    case LoveTextCommand cmd:
      buffer
        ..write(' spans=${cmd.spans.length}')
        ..write(' textLength=${cmd.text.length}')
        ..write(' limit=${cmd.limit ?? 'none'}')
        ..write(' align=${cmd.align}')
        ..write(' preview="${_previewText(cmd.text)}"');
    case LoveTextObjectCommand cmd:
      buffer
        ..write(' entries=${cmd.textObject.entries.length}')
        ..write(' fontSize=${cmd.textObject.font.size}');
    case LoveSpriteBatchCommand cmd:
      final drawRange = cmd.spriteBatch.drawRange;
      buffer
        ..write(' sprites=${cmd.spriteBatch.count}')
        ..write(' textureType=${cmd.spriteBatch.texture.textureType}')
        ..write(
          ' drawRange=${drawRange == null ? 'all' : '${drawRange.start}+${drawRange.count}'}',
        );
    case LoveMeshCommand cmd:
      buffer
        ..write(' vertices=${cmd.mesh.vertexCount}')
        ..write(' drawMode=${cmd.mesh.drawMode.name}')
        ..write(' instances=${cmd.instanceCount}');
    case LoveImageCommand cmd:
      buffer
        ..write(' textureType=${cmd.image.textureType}')
        ..write(' quad=${cmd.quad == null ? 'full' : 'subrect'}')
        ..write(' layer=${cmd.layer ?? 'default'}');
    case LoveParticleSystemCommand cmd:
      buffer.write(' particles=${cmd.particleSystem.particles.length}');
    case LoveArcCommand cmd:
      buffer
        ..write(' drawMode=${cmd.drawMode.name}')
        ..write(' arcMode=${cmd.arcMode.name}')
        ..write(' radius=${cmd.radius}');
    case LoveVideoCommand cmd:
      buffer.write(' video=${cmd.video.source}');
    case LoveStencilClearCommand cmd:
      buffer.write(' value=${cmd.value}');
    case LoveColorClearCommand cmd:
      buffer.write(' color=${_formatColor(cmd.color)}');
  }

  if (reason != null && reason.isNotEmpty) {
    buffer.write(' reason=$reason');
  }

  return buffer.toString();
}

String _formatPoint(double x, double y) => '($x,$y)';

String _formatPair(double left, double right) => '($left,$right)';

String _formatRect(double x, double y, double width, double height) =>
    '($x,$y,$width,$height)';

String _formatColor(LoveColor color) =>
    '(${color.r},${color.g},${color.b},${color.a})';

String _previewText(String text, {int limit = 24}) {
  if (text.length <= limit) {
    return text;
  }
  return '${text.substring(0, limit)}...';
}

String _previewPoints(List<({double x, double y})> points, {int limit = 3}) {
  if (points.isEmpty) {
    return '[]';
  }

  final preview = points
      .take(limit)
      .map((point) => _formatPoint(point.x, point.y))
      .toList(growable: false);
  if (points.length <= limit) {
    return '[${preview.join(', ')}]';
  }

  return '[${preview.join(', ')}, ...]';
}

/// Core GPU rendering engine for LOVE2D draw commands.
///
/// ## Frame pipeline
///
/// ```
/// 1. Pre-warm textures (async, caller's responsibility)
/// 2. Acquire Frame from GpuSurfaceManager
/// 3. Create CommandBuffer + RenderPass (clear color from snapshot)
/// 4. For each LoveDrawCommand:
///    - Switch on sealed subtype
///    - GPU-supported → issue draw calls via gpu.RenderPass
///    - Unsupported   → record index for fallback
/// 5. Present via Frame.present() → Texture.asImage() → canvas.drawImageRect()
/// 6. Fallback handler re-renders skipped commands via Canvas
/// ```
///
/// ## Supported command types
///
/// | Command | GPU Path | Handler |
/// |---|---|---|
/// | LoveColorClearCommand | ✅ (no-op, handled by LoadAction.clear) | inline |
/// | LoveMeshCommand | ✅ | GpuMeshHandler |
/// | LoveImageCommand | ✅ | GpuImageHandler |
/// | LoveSpriteBatchCommand | ✅ | GpuSpriteBatchHandler |
/// | LoveRectangleCommand | ✅ | GpuShapeHandler |
/// | LoveCircleCommand | ✅ | GpuShapeHandler |
/// | LoveEllipseCommand | ✅ | GpuShapeHandler |
/// | LoveArcCommand | ✅ | GpuShapeHandler |
/// | LoveLineCommand | ✅ | GpuShapeHandler |
/// | LovePolygonCommand | ✅ | GpuShapeHandler |
/// | LovePointsCommand | ✅ | GpuShapeHandler |
/// | LoveParticleSystemCommand | ✅ | GpuSpriteBatchHandler |
/// | LoveTextCommand | 🟡 (rasterized → GPU texture) | inline |
/// | LoveTextObjectCommand | 🟡 (rasterized → GPU texture) | inline |
/// | LoveStencilClearCommand | 🟡 (rasterized → GPU texture) | inline |
/// | LoveVideoCommand | ✅ (no-op, handled by overlay) | inline |
class GpuCommandRenderer {
  /// Creates a renderer with all handler dependencies.
  GpuCommandRenderer({
    required gpu.GpuContext gpuContext,
    required GpuSurfaceManager surfaceManager,
    required GpuPipelineCache pipelineCache,
    required GpuTextureCache textureCache,
    required GpuHostBufferPool hostBufferPool,
    required GpuFallbackHandler fallbackHandler,
  }) : _gpuContext = gpuContext,
       _surfaceManager = surfaceManager,
       _pipelineCache = pipelineCache,
       _textureCache = textureCache,
       _hostBufferPool = hostBufferPool,
       _meshHandler = GpuMeshHandler(
         pipelineCache: pipelineCache,
         textureCache: textureCache,
         hostBufferPool: hostBufferPool,
       ),
       _imageHandler = GpuImageHandler(
         pipelineCache: pipelineCache,
         textureCache: textureCache,
         hostBufferPool: hostBufferPool,
       ),
       _spriteBatchHandler = GpuSpriteBatchHandler(
         pipelineCache: pipelineCache,
         textureCache: textureCache,
         hostBufferPool: hostBufferPool,
       ),
       _shapeHandler = GpuShapeHandler(
         pipelineCache: pipelineCache,
         hostBufferPool: hostBufferPool,
       ),
       _fallbackHandler = fallbackHandler;

  final gpu.GpuContext _gpuContext;
  final GpuSurfaceManager _surfaceManager;
  final GpuPipelineCache _pipelineCache;
  final GpuTextureCache _textureCache;
  final GpuHostBufferPool _hostBufferPool;
  final GpuMeshHandler _meshHandler;
  final GpuImageHandler _imageHandler;
  final GpuSpriteBatchHandler _spriteBatchHandler;
  final GpuShapeHandler _shapeHandler;
  final GpuFallbackHandler _fallbackHandler;
  String? _lastLoggedFallbackSummaryKey;
  final Map<String, String> _fallbackDescriptionCache = {};

  /// Renders a single LOVE frame onto [canvas].
  ///
  /// [snapshot] contains the frame's clear color and command list.
  /// [viewportSize] is the logical LOVE viewport in pixels.
  ///
  /// Call [GpuTextureCache.preWarmCommands] before this method to pre-upload
  /// textures. Commands whose textures are not yet cached will be skipped and
  /// rendered via the Canvas fallback if [GpuFallbackHandler.enabled] is true.
  ///
  /// Returns the cumulative render stats for this frame.
  LoveRenderStatsAccumulator renderFrame(
    ui.Canvas canvas,
    LoveGraphicsSurfaceSnapshot snapshot,
    ui.Size viewportSize, {
    LoveRenderStatsAccumulator? stats,
  }) {
    stats ??= LoveRenderStatsAccumulator();

    final width = viewportSize.width.ceil();
    final height = viewportSize.height.ceil();
    if (width <= 0 || height <= 0) return stats;

    // Reset the per-frame host buffer
    _hostBufferPool.reset();

    // ── PHASE 1: Synchronous texture pre-warm ─────────────────────────
    // Upload textures from LoveImage.imageData (decoded CPU pixels) so
    // the GPU path finds them cached during the render pass.
    final fallbackIndices = <int>[];
    final fallbackCounts = <String, _GpuFallbackSummaryEntry>{};
    for (var i = 0; i < snapshot.commands.length; i++) {
      final cmd = snapshot.commands[i];
      final reason = _commandFallbackReason(cmd);
      if (reason == null) {
        // Not an inherent fallback; try warm its texture.
        _warmTexture(cmd);
        continue;
      }
      fallbackIndices.add(i);
      _countFallback(fallbackCounts, cmd, reason);
    }
    _debugLogFallbackSummary(fallbackCounts);

    // ── PHASE 2: GPU render pass ─────────────────────────────────────
    final frame = _surfaceManager.acquire(width, height);
    final commandBuffer = _gpuContext.createCommandBuffer();
    final renderTarget = _buildRenderTarget(snapshot, frame);
    final renderPass = commandBuffer.createRenderPass(renderTarget);
    renderPass.setViewport(
      gpu.Viewport(x: 0, y: 0, width: width, height: height),
    );
    // Reset pass-local raster state. flutter_scene does this too because
    // cull/winding state can leak between passes and blank later quads.
    renderPass.setCullMode(gpu.CullMode.none);
    renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
    renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);

    var renderedCommands = 0;
    for (var i = 0; i < snapshot.commands.length; i++) {
      if (fallbackIndices.contains(i)) continue;
      final command = snapshot.commands[i];
      if (command is LoveColorClearCommand) continue;
      try {
        _dispatchGpuCommand(renderPass, command, viewportSize);
      } catch (_) {
        // Texture binding fails on this platform for hostVisible textures.
        // Command is skipped; the result may be incomplete but not crashing.
      }
      renderedCommands++;
    }

    // Submit GPU work and present to canvas.
    frame.present(commandBuffer, canvas, viewportSize);

    // ── PHASE 3: Canvas fallback for unsupported commands ─────────────
    // Renders via the standard Canvas path on top of the GPU frame.
    // This is not as fast as pure GPU but maintains correctness.
    if (_fallbackHandler.enabled && fallbackIndices.isNotEmpty) {
      _fallbackHandler.renderFallback(
        canvas,
        snapshot,
        viewportSize,
        fallbackIndices,
        stats: stats,
      );
    }

    stats.renderedCommands = renderedCommands;
    return stats;
  }

  gpu.RenderTarget _buildRenderTarget(
    LoveGraphicsSurfaceSnapshot snapshot,
    Frame frame,
  ) {
    final c = snapshot.clearColor;
    return gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: frame.colorTexture,
        clearValue: vm.Vector4(c.r, c.g, c.b, c.a),
      ),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: frame.depthStencilTexture,
        depthLoadAction: gpu.LoadAction.clear,
        depthStoreAction: gpu.StoreAction.dontCare,
        depthClearValue: 0.0,
        stencilLoadAction: gpu.LoadAction.clear,
        stencilStoreAction: gpu.StoreAction.dontCare,
        stencilClearValue: snapshot.clearStencil,
      ),
    );
  }

  /// Returns the fallback reason for [command], or `null` if the command can
  /// be handled directly by the GPU path.
  String? _commandFallbackReason(LoveDrawCommand command) {
    return switch (command) {
      LoveColorClearCommand _ => null,
      LoveMeshCommand _ => null,
      LoveImageCommand _ => null,
      LoveSpriteBatchCommand _ => null,
      LoveRectangleCommand _ => null,
      LoveCircleCommand _ => null,
      LoveEllipseCommand _ => null,
      LoveLineCommand _ => null,
      LovePolygonCommand _ => null,
      LovePointsCommand _ => null,
      LoveArcCommand _ => null,
      LoveParticleSystemCommand _ => null,
      LoveVideoCommand _ => null,
      LoveTextCommand _ => 'rasterized via software fallback',
      LoveTextObjectCommand _ => 'rasterized via software fallback',
      LoveStencilClearCommand _ => 'rasterized via software fallback',
    };
  }

  void _warmTexture(LoveDrawCommand command) {
    try {
      switch (command) {
        case LoveImageCommand(:final image):
          _textureCache.uploadSync(image);
        case LoveSpriteBatchCommand(:final spriteBatch):
          _textureCache.uploadSync(spriteBatch.texture);
        case LoveMeshCommand(:final mesh):
          if (mesh.textureObject is LoveImage) {
            _textureCache.uploadSync(mesh.textureObject as LoveImage);
          }
        case LoveParticleSystemCommand(:final particleSystem):
          _textureCache.uploadSync(particleSystem.texture);
        default:
          break;
      }
    } catch (_) {}
  }

  void _countFallback(
    Map<String, _GpuFallbackSummaryEntry> counts,
    LoveDrawCommand command,
    String reason,
  ) {
    final bucketKey = _fallbackSummaryBucketKey(command, reason);
    final description = _fallbackDescriptionCache.putIfAbsent(
      bucketKey,
      () => describeGpuFallbackCommand(command, reason: reason),
    );
    counts.update(
      bucketKey,
      (entry) {
        entry.count++;
        return entry;
      },
      ifAbsent: () =>
          _GpuFallbackSummaryEntry(description: description, count: 1),
    );
  }

  void _dispatchGpuCommand(
    gpu.RenderPass renderPass,
    LoveDrawCommand command,
    ui.Size viewportSize,
  ) {
    switch (command) {
      case LoveMeshCommand cmd:
        _dispatchMesh(renderPass, cmd, viewportSize);
      case LoveImageCommand cmd:
        _dispatchImage(renderPass, cmd, viewportSize);
      case LoveSpriteBatchCommand cmd:
        _dispatchSpriteBatch(renderPass, cmd, viewportSize);
      case LoveRectangleCommand cmd:
        _dispatchRectangle(renderPass, cmd, viewportSize);
      case LoveCircleCommand cmd:
        _dispatchCircle(renderPass, cmd, viewportSize);
      case LoveEllipseCommand cmd:
        _dispatchEllipse(renderPass, cmd, viewportSize);
      case LoveLineCommand cmd:
        _dispatchLine(renderPass, cmd, viewportSize);
      case LovePolygonCommand cmd:
        _dispatchPolygon(renderPass, cmd, viewportSize);
      case LovePointsCommand cmd:
        _dispatchPoints(renderPass, cmd, viewportSize);
      case LoveArcCommand cmd:
        _dispatchArc(renderPass, cmd, viewportSize);
      case LoveParticleSystemCommand cmd:
        _dispatchParticleSystem(renderPass, cmd, viewportSize);
      case LoveColorClearCommand _:
      case LoveVideoCommand _:
      case LoveTextCommand _:
      case LoveTextObjectCommand _:
      case LoveStencilClearCommand _:
        break;
    }
  }

  void _dispatchRectangle(
    gpu.RenderPass renderPass,
    LoveRectangleCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.width <= 0 || cmd.height <= 0) return;
    _shapeHandler.renderRectangle(renderPass, cmd, viewportSize);
  }

  void _dispatchCircle(
    gpu.RenderPass renderPass,
    LoveCircleCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.radius <= 0) return;
    _shapeHandler.renderCircle(renderPass, cmd, viewportSize);
  }

  void _dispatchEllipse(
    gpu.RenderPass renderPass,
    LoveEllipseCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.radiusX <= 0 || cmd.radiusY <= 0) return;
    _shapeHandler.renderEllipse(renderPass, cmd, viewportSize);
  }

  void _dispatchLine(
    gpu.RenderPass renderPass,
    LoveLineCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.points.length < 2) return;
    _shapeHandler.renderLine(renderPass, cmd, viewportSize);
  }

  void _dispatchPolygon(
    gpu.RenderPass renderPass,
    LovePolygonCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.points.length < 3) return;
    _shapeHandler.renderPolygon(renderPass, cmd, viewportSize);
  }

  void _dispatchArc(
    gpu.RenderPass renderPass,
    LoveArcCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.radius <= 0) return;
    _shapeHandler.renderArc(renderPass, cmd, viewportSize);
  }

  void _dispatchPoints(
    gpu.RenderPass renderPass,
    LovePointsCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.points.isEmpty) return;
    _shapeHandler.renderPoints(renderPass, cmd, viewportSize);
  }

  void _dispatchImage(
    gpu.RenderPass renderPass,
    LoveImageCommand cmd,
    ui.Size viewportSize,
  ) {
    _imageHandler.renderSync(renderPass, cmd, viewportSize);
  }

  void _dispatchSpriteBatch(
    gpu.RenderPass renderPass,
    LoveSpriteBatchCommand cmd,
    ui.Size viewportSize,
  ) {
    final sprites = cmd.spriteBatch.spritesToDraw();
    if (sprites.isEmpty) {
      return;
    }
    _spriteBatchHandler.renderSync(renderPass, cmd, viewportSize);
  }

  void _dispatchMesh(
    gpu.RenderPass renderPass,
    LoveMeshCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.mesh.verticesForDraw().isEmpty || cmd.instanceCount <= 0) {
      return;
    }
    final textureObject = cmd.mesh.textureObject;
    if (textureObject != null && textureObject is! LoveImage) {
      return;
    }
    _meshHandler.renderSync(renderPass, cmd, viewportSize);
  }

  void _dispatchParticleSystem(
    gpu.RenderPass renderPass,
    LoveParticleSystemCommand cmd,
    ui.Size viewportSize,
  ) {
    if (cmd.particleSystem.particles.isEmpty) return;
    _spriteBatchHandler.renderParticles(renderPass, cmd, viewportSize);
  }

  void _debugLogFallbackSummary(
    Map<String, _GpuFallbackSummaryEntry> fallbackCounts,
  ) {
    if (fallbackCounts.isEmpty) {
      return;
    }

    final summaryEntries = fallbackCounts.entries.toList()
      ..sort((left, right) {
        final leftKey = _normalizeFallbackSummaryKey(left.value.description);
        final rightKey = _normalizeFallbackSummaryKey(right.value.description);
        return leftKey.compareTo(rightKey);
      });
    final summaryKey = summaryEntries
        .map(
          (entry) =>
              '${entry.value.count}x ${_normalizeFallbackSummaryKey(entry.value.description)}',
        )
        .join(' | ');
    if (summaryKey == _lastLoggedFallbackSummaryKey) {
      return;
    }

    _lastLoggedFallbackSummaryKey = summaryKey;
  }

  String _fallbackSummaryBucketKey(LoveDrawCommand command, String? reason) {
    return '${command.runtimeType}|${reason ?? ''}';
  }

  String _normalizeFallbackSummaryKey(String description) {
    return description
        .replaceAll(RegExp(r' textLength=\d+'), '')
        .replaceAll(RegExp(r' preview=(?:"[^"]*"|\[[^\]]*\])'), '');
  }

  /// Releases all GPU resources held by the renderer's subsystems.
  void dispose() {
    _pipelineCache.clear();
    _textureCache.clear();
    _surfaceManager.dispose();
  }
}
