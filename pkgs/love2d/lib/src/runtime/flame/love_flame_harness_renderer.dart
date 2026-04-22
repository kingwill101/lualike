import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../love_runtime.dart';
import 'love_flame_host.dart';
import 'love_registered_fragment_shader_cache.dart';
import 'love_flame_viewport_geometry.dart';

final Map<LoveImage, ui.Image> _staticShaderSamplerImages =
    <LoveImage, ui.Image>{};
final Set<LoveImage> _pendingStaticShaderSamplerImages = <LoveImage>{};
final Map<LoveCanvas, ui.Image> _liveCanvasShaderSamplerImages =
    <LoveCanvas, ui.Image>{};
final Set<LoveCanvas> _pendingLiveCanvasShaderSamplerImages = <LoveCanvas>{};

class LoveFlameHarnessGame extends FlameGame {
  LoveFlameHarnessGame({this.audioBackendFactory, AssetBundle? assetBundle})
    : _assetBundle = assetBundle;

  final LoveAudioBackendFactory? audioBackendFactory;
  final AssetBundle? _assetBundle;

  late final LoveFlameHost host = LoveFlameHost(
    game: this,
    assetBundle: _assetBundle,
    audioBackendFactory: audioBackendFactory,
  );
  late LoveGraphicsSurfaceSnapshot _presentedFrame = host.graphics
      .snapshotScreenSurface();

  void Function(double dt)? onTick;

  LoveGraphicsSurfaceSnapshot get presentedFrame => _presentedFrame;

  void presentFrame(LoveGraphicsSurfaceSnapshot frame) {
    _presentedFrame = frame;
  }

  @override
  Color backgroundColor() => const Color(0xFF050816);

  @override
  void update(double dt) {
    super.update(dt);
    onTick?.call(dt);
  }

  @override
  void render(Canvas canvas) {
    final frame = _presentedFrame;
    final viewportSize = Size(canvasSize.x, canvasSize.y);
    super.render(canvas);
    final destinationRect = loveViewportDestinationRect(
      windowMetrics: host.windowMetrics,
      viewportSize: viewportSize,
    );
    final logicalViewportSize = loveLogicalViewportSize(
      windowMetrics: host.windowMetrics,
      viewportSize: viewportSize,
    );
    if (destinationRect.width <= 0 ||
        destinationRect.height <= 0 ||
        logicalViewportSize.width <= 0 ||
        logicalViewportSize.height <= 0) {
      return;
    }

    canvas.save();
    canvas.clipRect(destinationRect);
    canvas.translate(destinationRect.left, destinationRect.top);
    canvas.scale(
      destinationRect.width / logicalViewportSize.width,
      destinationRect.height / logicalViewportSize.height,
    );
    _renderSurfaceSnapshot(canvas, frame, logicalViewportSize);
    canvas.restore();
  }
}

Rect _rectForScissor(LoveScissorRect scissor) {
  return Rect.fromLTWH(scissor.x, scissor.y, scissor.width, scissor.height);
}

void _renderRecordedCommand(Canvas canvas, LoveDrawCommand command) {
  canvas.save();
  final scissor = command.scissor;
  if (scissor != null) {
    canvas.clipRect(_rectForScissor(scissor));
  }
  final layerPaint = _layerPaintForCommand(command);
  final shaderLayerPaint = _shaderLayerPaintForCommand(command);
  final radialGradientMaskPaint = _radialGradientMaskPaintForCommand(command);
  if (layerPaint != null) {
    canvas.saveLayer(null, layerPaint);
  }
  if (shaderLayerPaint != null) {
    canvas.saveLayer(null, shaderLayerPaint);
  }
  if (radialGradientMaskPaint != null) {
    canvas.saveLayer(null, Paint());
  }
  canvas.save();
  canvas.transform(command.transform.storage);

  switch (command) {
    case final LoveColorClearCommand clear:
      canvas.drawRect(
        Rect.fromLTWH(-1000000, -1000000, 2000000, 2000000),
        Paint()..color = _toFlutterColor(clear.color),
      );
    case LoveStencilClearCommand():
      break;
    case final LoveParticleSystemCommand particleSystem:
      _renderParticleSystemCommand(canvas, particleSystem);
    case final LoveRectangleCommand rectangle:
      final paint = Paint()
        ..color = _toFlutterColor(rectangle.color)
        ..style = _shapeStyle(rectangle.mode, rectangle.wireframe)
        ..strokeWidth = rectangle.lineWidth
        ..strokeJoin = _strokeJoinForLove(rectangle.lineJoin)
        ..isAntiAlias = _isAntiAliasForLove(rectangle.lineStyle);
      final rect = Rect.fromLTWH(
        rectangle.x,
        rectangle.y,
        rectangle.width,
        rectangle.height,
      );
      _configureShaderPaint(paint, rectangle);

      if (rectangle.cornerRadiusX > 0 || rectangle.cornerRadiusY > 0) {
        final rrect = RRect.fromRectAndRadius(
          rect,
          Radius.elliptical(rectangle.cornerRadiusX, rectangle.cornerRadiusY),
        );
        canvas.drawRRect(rrect, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    case final LoveCircleCommand circle:
      final paint = Paint()
        ..color = _toFlutterColor(circle.color)
        ..style = _shapeStyle(circle.mode, circle.wireframe)
        ..strokeWidth = circle.lineWidth
        ..strokeJoin = _strokeJoinForLove(circle.lineJoin)
        ..isAntiAlias = _isAntiAliasForLove(circle.lineStyle);
      _configureShaderPaint(paint, circle);
      canvas.drawCircle(Offset(circle.x, circle.y), circle.radius, paint);
    case final LoveLineCommand line:
      final paint = Paint()
        ..color = _toFlutterColor(line.color)
        ..style = PaintingStyle.stroke
        ..strokeWidth = line.lineWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = _strokeJoinForLove(line.lineJoin)
        ..isAntiAlias = _isAntiAliasForLove(line.lineStyle);
      final path = Path()..moveTo(line.points.first.x, line.points.first.y);
      for (final point in line.points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      canvas.drawPath(path, paint);
    case final LovePolygonCommand polygon:
      final paint = Paint()
        ..color = _toFlutterColor(polygon.color)
        ..style = _shapeStyle(polygon.mode, polygon.wireframe)
        ..strokeWidth = polygon.lineWidth
        ..strokeJoin = _strokeJoinForLove(polygon.lineJoin)
        ..isAntiAlias = _isAntiAliasForLove(polygon.lineStyle);
      final path = Path()
        ..moveTo(polygon.points.first.x, polygon.points.first.y);
      for (final point in polygon.points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      path.close();
      _configureShaderPaint(paint, polygon);
      canvas.drawPath(path, paint);
    case final LovePointsCommand points:
      final basePaint = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = _isAntiAliasForLove(points.lineStyle);
      for (final point in points.points) {
        final paint = Paint()
          ..color = _toFlutterColor(point.color ?? points.color)
          ..style = basePaint.style
          ..isAntiAlias = basePaint.isAntiAlias;
        final halfSize = points.pointSize / 2;
        canvas.drawRect(
          Rect.fromLTWH(
            point.x - halfSize,
            point.y - halfSize,
            points.pointSize,
            points.pointSize,
          ),
          paint,
        );
      }
    case final LoveEllipseCommand ellipse:
      final paint = Paint()
        ..color = _toFlutterColor(ellipse.color)
        ..style = _shapeStyle(ellipse.mode, ellipse.wireframe)
        ..strokeWidth = ellipse.lineWidth
        ..strokeJoin = _strokeJoinForLove(ellipse.lineJoin)
        ..isAntiAlias = _isAntiAliasForLove(ellipse.lineStyle);
      _configureShaderPaint(paint, ellipse);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ellipse.x, ellipse.y),
          width: ellipse.radiusX * 2,
          height: ellipse.radiusY * 2,
        ),
        paint,
      );
    case final LoveArcCommand arc:
      final paint = Paint()
        ..color = _toFlutterColor(arc.color)
        ..style = _shapeStyle(arc.drawMode, arc.wireframe)
        ..strokeWidth = arc.lineWidth
        ..strokeJoin = _strokeJoinForLove(arc.lineJoin)
        ..isAntiAlias = _isAntiAliasForLove(arc.lineStyle);
      final rect = Rect.fromCircle(
        center: Offset(arc.x, arc.y),
        radius: arc.radius,
      );
      final sweepAngle = arc.angle2 - arc.angle1;
      final path = Path();

      switch (arc.arcMode) {
        case LoveGraphicsArcMode.open:
          path.addArc(rect, arc.angle1, sweepAngle);
        case LoveGraphicsArcMode.closed:
          path.arcTo(rect, arc.angle1, sweepAngle, true);
          path.close();
        case LoveGraphicsArcMode.pie:
          path.moveTo(arc.x, arc.y);
          path.arcTo(rect, arc.angle1, sweepAngle, false);
          path.close();
      }

      _configureShaderPaint(paint, arc);
      canvas.drawPath(path, paint);
    case final LoveTextCommand text:
      final wrapWidth = text.limit != null && text.limit! > 0
          ? text.limit!
          : null;
      final painter =
          TextPainter(
            text: TextSpan(
              children: text.spans
                  .map(
                    (segment) => TextSpan(
                      text: segment.text,
                      style: TextStyle(
                        color: _toFlutterColor(
                          text.color.modulate(segment.color ?? LoveColor.white),
                        ),
                        fontSize: text.font.size,
                        height: text.font.lineHeight,
                        fontFamily: text.font.family ?? 'monospace',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            textDirection: TextDirection.ltr,
            textAlign: _textAlignForLove(text.align),
            maxLines: null,
          )..layout(
            minWidth: wrapWidth ?? 0.0,
            maxWidth: wrapWidth ?? double.infinity,
          );
      canvas.transform(text.textTransform.storage);
      painter.paint(canvas, Offset.zero);
    case final LoveTextObjectCommand text:
      _renderTextObjectCommand(canvas, text);
    case final LoveImageCommand image:
      _renderImageCommand(canvas, image);
    case final LoveSpriteBatchCommand spriteBatch:
      _renderSpriteBatchCommand(canvas, spriteBatch);
    case final LoveMeshCommand mesh:
      _renderMeshCommand(canvas, mesh);
  }

  canvas.restore();
  if (radialGradientMaskPaint != null) {
    canvas.drawPaint(radialGradientMaskPaint);
    canvas.restore();
  }
  if (shaderLayerPaint != null) {
    canvas.restore();
  }
  if (layerPaint != null) {
    canvas.restore();
  }
  canvas.restore();
}

void _renderTextObjectCommand(Canvas canvas, LoveTextObjectCommand text) {
  for (final entry in text.textObject.entries) {
    if (entry.spans.isEmpty) {
      continue;
    }

    final wrapWidth = entry.wrapLimit != null && entry.wrapLimit! > 0
        ? entry.wrapLimit!
        : null;
    final painter =
        TextPainter(
          text: TextSpan(
            children: entry.spans
                .map(
                  (segment) => TextSpan(
                    text: segment.text,
                    style: TextStyle(
                      color: _toFlutterColor(
                        text.color.modulate(segment.color ?? LoveColor.white),
                      ),
                      fontSize: text.textObject.font.size,
                      height: text.textObject.font.lineHeight,
                      fontFamily: text.textObject.font.family ?? 'monospace',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          textDirection: TextDirection.ltr,
          textAlign: _textAlignForLove(entry.align),
          maxLines: null,
        )..layout(
          minWidth: wrapWidth ?? 0.0,
          maxWidth: wrapWidth ?? double.infinity,
        );

    canvas.save();
    canvas.transform(text.drawTransform.storage);
    canvas.transform(entry.transform.storage);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }
}

void _renderImageCommand(Canvas canvas, LoveImageCommand image) {
  _renderResolvedImage(
    canvas,
    command: image,
    image: image.image,
    quad: image.quad,
    layer: image.layer,
    drawTransform: image.drawTransform,
    tint: image.color.clamped(),
  );
}

void _renderSpriteBatchCommand(
  Canvas canvas,
  LoveSpriteBatchCommand spriteBatchCommand,
) {
  final entries = spriteBatchCommand.spriteBatch.spritesToDraw();
  if (entries.isEmpty) {
    return;
  }

  canvas.save();
  canvas.transform(spriteBatchCommand.drawTransform.storage);
  for (final entry in entries) {
    _renderResolvedImage(
      canvas,
      command: spriteBatchCommand,
      image: spriteBatchCommand.spriteBatch.texture,
      quad: entry.quad,
      layer: entry.layer,
      drawTransform: entry.transform,
      tint: entry.color == null
          ? spriteBatchCommand.color
          : spriteBatchCommand.color.modulate(entry.color!),
    );
  }
  canvas.restore();
}

void _renderParticleSystemCommand(
  Canvas canvas,
  LoveParticleSystemCommand particleSystemCommand,
) {
  final particles = particleSystemCommand.particleSystem.particles;
  if (particles.isEmpty) {
    return;
  }

  canvas.save();
  canvas.transform(particleSystemCommand.drawTransform.storage);
  for (final particle in particles) {
    _renderResolvedImage(
      canvas,
      command: particleSystemCommand,
      image: particleSystemCommand.particleSystem.texture,
      quad: particle.quad,
      drawTransform: particle.transform,
      tint: particleSystemCommand.color.modulate(particle.color),
    );
  }
  canvas.restore();
}

void _renderResolvedImage(
  Canvas canvas, {
  required LoveDrawCommand command,
  required LoveImage image,
  required LoveQuad? quad,
  int? layer,
  required vm.Matrix4 drawTransform,
  required LoveColor tint,
}) {
  final resolvedImage = resolveDrawableImageForLayer(image, layer: layer);
  if (resolvedImage == null) {
    return;
  }

  final sourceRect = quad == null
      ? Rect.fromLTWH(
          0,
          0,
          resolvedImage.width.toDouble(),
          resolvedImage.height.toDouble(),
        )
      : Rect.fromLTWH(quad.x, quad.y, quad.width, quad.height);
  final destinationRect = Rect.fromLTWH(
    0,
    0,
    sourceRect.width,
    sourceRect.height,
  );

  canvas.save();
  canvas.transform(drawTransform.storage);
  final radialGradientOverlayPaint = _radialGradientImageOverlayPaintForCommand(
    command,
  );
  final registeredShaderPaint = _registeredFragmentPaintForCommand(
    command,
    sourceImage: resolvedImage,
  );
  if (radialGradientOverlayPaint != null) {
    canvas.saveLayer(destinationRect, Paint());
  }
  if (registeredShaderPaint != null) {
    canvas.drawRect(destinationRect, registeredShaderPaint);
    if (radialGradientOverlayPaint != null) {
      canvas.restore();
    }
    canvas.restore();
    return;
  }

  switch (resolvedImage) {
    case final LoveCanvasSnapshot snapshot:
      canvas.save();
      canvas.clipRect(destinationRect);
      canvas.translate(-sourceRect.left, -sourceRect.top);
      if (tint != LoveColor.white) {
        canvas.saveLayer(
          destinationRect,
          Paint()
            ..colorFilter = ColorFilter.mode(
              _toFlutterColor(tint),
              BlendMode.modulate,
            ),
        );
      }
      _renderSurfaceSnapshot(
        canvas,
        snapshot.surface,
        Size(snapshot.width.toDouble(), snapshot.height.toDouble()),
      );
      if (tint != LoveColor.white) {
        canvas.restore();
      }
      canvas.restore();
    default:
      final rawImage = resolvedImage.nativeImage;
      final imageData = resolvedImage.imageData;
      final shouldRenderImageData =
          imageData != null &&
          (resolvedImage.preferImageDataRendering || rawImage is! ui.Image);
      if (shouldRenderImageData) {
        final resolvedImageData = imageData;
        final left = sourceRect.left.round();
        final top = sourceRect.top.round();
        final width = sourceRect.width.round();
        final height = sourceRect.height.round();

        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final color = resolvedImageData.getPixel(left + x, top + y);
            final paint = Paint()
              ..color = _toFlutterColor(_modulateLoveColor(color, tint));
            canvas.drawRect(
              Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
              paint,
            );
          }
        }
      } else if (rawImage is ui.Image) {
        final paint = Paint()
          ..filterQuality = _filterQualityForLove(resolvedImage.filter);
        if (tint != LoveColor.white) {
          paint.colorFilter = ColorFilter.mode(
            _toFlutterColor(tint),
            BlendMode.modulate,
          );
        }
        canvas.drawImageRect(rawImage, sourceRect, destinationRect, paint);
      }
  }
  if (radialGradientOverlayPaint != null) {
    canvas.drawRect(destinationRect, radialGradientOverlayPaint);
    canvas.restore();
  }
  canvas.restore();
}

void _renderMeshCommand(Canvas canvas, LoveMeshCommand mesh) {
  final vertices = mesh.mesh.verticesForDraw();
  if (vertices.isEmpty || mesh.instanceCount <= 0) {
    return;
  }

  final combinedTransform = vm.Matrix4.copy(mesh.transform)
    ..multiply(mesh.drawTransform);
  final effectiveMode =
      mesh.mesh.drawMode == LoveMeshDrawMode.points ||
          mesh.cullMode == LoveGraphicsCullMode.none
      ? mesh.mesh.drawMode
      : LoveMeshDrawMode.triangles;
  final effectiveVertices =
      mesh.mesh.drawMode == LoveMeshDrawMode.points ||
          mesh.cullMode == LoveGraphicsCullMode.none
      ? vertices
      : _meshVerticesAfterCulling(mesh, vertices, combinedTransform);
  if (effectiveVertices.isEmpty) {
    return;
  }

  final meshBounds = _meshLocalBounds(effectiveVertices);
  final positions = Float32List(effectiveVertices.length * 2);
  final textureImage = _resolvedMeshTextureImage(mesh.mesh);
  if (mesh.wireframe || effectiveMode == LoveMeshDrawMode.points) {
    _renderSoftwareMeshCommand(
      canvas,
      mesh: mesh,
      effectiveMode: effectiveMode,
      effectiveVertices: effectiveVertices,
      meshBounds: meshBounds,
      textureImage: textureImage,
    );
    return;
  }
  final rawTextureImage = _resolvedMeshTextureNativeImage(textureImage);
  final texturedModulationColors = textureImage == null
      ? null
      : _texturedMeshModulationColors(mesh, effectiveVertices);
  final uniformTexturedTint = texturedModulationColors == null
      ? null
      : _uniformTexturedMeshTint(texturedModulationColors);
  final texturedVertexRgbTintColors =
      texturedModulationColors == null || uniformTexturedTint != null
      ? null
      : _texturedMeshRgbModulationColors(texturedModulationColors);
  final texturedVertexAlphaTintColors =
      texturedModulationColors == null || uniformTexturedTint != null
      ? null
      : _texturedMeshAlphaModulationColors(texturedModulationColors);
  if (textureImage != null && rawTextureImage is! ui.Image) {
    _renderSoftwareMeshCommand(
      canvas,
      mesh: mesh,
      effectiveMode: effectiveMode,
      effectiveVertices: effectiveVertices,
      meshBounds: meshBounds,
      textureImage: textureImage,
    );
    return;
  }

  canvas.transform(mesh.drawTransform.storage);
  final colors = rawTextureImage is ui.Image && textureImage != null
      ? null
      : Int32List(effectiveVertices.length);
  final textureCoordinates = rawTextureImage is ui.Image
      ? Float32List(effectiveVertices.length * 2)
      : null;
  for (var index = 0; index < effectiveVertices.length; index++) {
    final vertex = effectiveVertices[index];
    positions[index * 2] = vertex.x;
    positions[(index * 2) + 1] = vertex.y;
    if (colors != null) {
      colors[index] = _toFlutterColor(
        _modulateLoveColor(vertex.color, mesh.color),
      ).toARGB32();
    }
    if (textureCoordinates != null && textureImage != null) {
      textureCoordinates[index * 2] = vertex.u * textureImage.width;
      textureCoordinates[(index * 2) + 1] = vertex.v * textureImage.height;
    }
  }

  final uiVertices = ui.Vertices.raw(
    _vertexModeForLove(effectiveMode),
    positions,
    textureCoordinates: textureCoordinates,
    colors: colors,
  );
  final texturedRgbTintVertices = texturedVertexRgbTintColors == null
      ? null
      : ui.Vertices.raw(
          _vertexModeForLove(effectiveMode),
          positions,
          colors: texturedVertexRgbTintColors,
        );
  final texturedAlphaTintVertices = texturedVertexAlphaTintColors == null
      ? null
      : ui.Vertices.raw(
          _vertexModeForLove(effectiveMode),
          positions,
          colors: texturedVertexAlphaTintColors,
        );
  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = mesh.wireframe ? PaintingStyle.stroke : PaintingStyle.fill
    ..strokeWidth = mesh.lineWidth
    ..strokeJoin = _strokeJoinForLove(mesh.lineJoin)
    ..isAntiAlias = _isAntiAliasForLove(mesh.lineStyle);
  final texturedRgbTintOverlayPaint =
      rawTextureImage is ui.Image &&
          uniformTexturedTint != null &&
          !_isWhiteRgb(uniformTexturedTint)
      ? (Paint()
          ..color = _toFlutterColor(
            LoveColor(
              uniformTexturedTint.r,
              uniformTexturedTint.g,
              uniformTexturedTint.b,
              1,
            ),
          )
          ..blendMode = BlendMode.modulate
          ..isAntiAlias = false)
      : null;
  final texturedAlphaTintOverlayPaint =
      rawTextureImage is ui.Image &&
          uniformTexturedTint != null &&
          uniformTexturedTint.a < 0.999999
      ? (Paint()
          ..color = _toFlutterColor(LoveColor(1, 1, 1, uniformTexturedTint.a))
          ..blendMode = BlendMode.dstIn
          ..isAntiAlias = false)
      : null;
  final texturedVertexRgbTintOverlayPaint = texturedRgbTintVertices == null
      ? null
      : (Paint()
          ..color = const Color(0xFFFFFFFF)
          ..isAntiAlias = false);
  final texturedVertexAlphaTintOverlayPaint = texturedAlphaTintVertices == null
      ? null
      : (Paint()
          ..color = const Color(0xFFFFFFFF)
          ..isAntiAlias = false);
  final radialGradientOverlayPaint = rawTextureImage is ui.Image
      ? _radialGradientImageOverlayPaintForCommand(mesh)
      : null;
  if (rawTextureImage is ui.Image) {
    paint.shader = ui.ImageShader(
      rawTextureImage,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Float64List.fromList(vm.Matrix4.identity().storage),
    );
  } else {
    _configureShaderPaint(paint, mesh);
  }

  if ((texturedRgbTintOverlayPaint != null ||
          texturedAlphaTintOverlayPaint != null ||
          texturedVertexRgbTintOverlayPaint != null ||
          texturedVertexAlphaTintOverlayPaint != null ||
          radialGradientOverlayPaint != null) &&
      meshBounds != null) {
    for (var instance = 0; instance < mesh.instanceCount; instance++) {
      canvas.saveLayer(meshBounds, Paint());
      canvas.drawVertices(uiVertices, ui.BlendMode.srcOver, paint);
      if (texturedRgbTintOverlayPaint != null) {
        canvas.drawRect(meshBounds, texturedRgbTintOverlayPaint);
      }
      if (texturedVertexRgbTintOverlayPaint != null &&
          texturedRgbTintVertices != null) {
        canvas.drawVertices(
          texturedRgbTintVertices,
          ui.BlendMode.modulate,
          texturedVertexRgbTintOverlayPaint,
        );
      }
      if (texturedAlphaTintOverlayPaint != null) {
        canvas.drawRect(meshBounds, texturedAlphaTintOverlayPaint);
      }
      if (texturedVertexAlphaTintOverlayPaint != null &&
          texturedAlphaTintVertices != null) {
        canvas.saveLayer(meshBounds, Paint()..blendMode = BlendMode.dstIn);
        canvas.drawVertices(
          texturedAlphaTintVertices,
          ui.BlendMode.srcOver,
          texturedVertexAlphaTintOverlayPaint,
        );
        canvas.restore();
      }
      if (radialGradientOverlayPaint != null) {
        canvas.drawRect(meshBounds, radialGradientOverlayPaint);
      }
      canvas.restore();
    }
    return;
  }

  for (var instance = 0; instance < mesh.instanceCount; instance++) {
    canvas.drawVertices(uiVertices, ui.BlendMode.srcOver, paint);
  }
}

void _renderSoftwareMeshCommand(
  Canvas canvas, {
  required LoveMeshCommand mesh,
  required LoveMeshDrawMode effectiveMode,
  required List<LoveMeshVertex> effectiveVertices,
  required Rect? meshBounds,
  LoveImage? textureImage,
}) {
  final localBounds = switch (effectiveMode) {
    LoveMeshDrawMode.points => meshBounds?.inflate(
      math.max(0.5, mesh.pointSize * 0.5),
    ),
    _ when mesh.wireframe => meshBounds?.inflate(
      math.max(0.5, mesh.lineWidth * 0.5),
    ),
    _ => meshBounds,
  };
  if (localBounds == null) {
    return;
  }

  final pixelWidth = math.max(1, localBounds.width.ceil());
  final pixelHeight = math.max(1, localBounds.height.ceil());
  final fallbackMesh = LoveMesh(
    vertices: effectiveVertices,
    drawMode: effectiveMode,
    usage: mesh.mesh.usage,
    vertexFormat: mesh.mesh.vertexFormat,
  );
  if (textureImage != null) {
    fallbackMesh.setImageTexture(textureImage);
  }
  final fallbackCommand = LoveMeshCommand(
    color: mesh.color,
    lineWidth: mesh.lineWidth,
    lineStyle: mesh.lineStyle,
    lineJoin: mesh.lineJoin,
    blendMode: LoveGraphicsBlendMode.replace,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: mesh.wireframe,
    scissor: null,
    shader: _softwareMeshShader(mesh.shader, localBounds),
    transform: vm.Matrix4.translationValues(
      -localBounds.left,
      -localBounds.top,
      0,
    ),
    drawTransform: vm.Matrix4.identity(),
    mesh: fallbackMesh,
    pointSize: mesh.pointSize,
    frontFaceWinding: mesh.frontFaceWinding,
    cullMode: LoveGraphicsCullMode.none,
  );
  final rasterized = LoveCanvasRasterizer.rasterizeSurface(
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    format: 'rgba8',
    snapshot: LoveGraphicsSurfaceSnapshot(
      clearColor: const LoveColor(0, 0, 0, 0),
      clearColorMask: LoveGraphicsColorMask.all,
      clearStencil: 0,
      clearScissor: null,
      commands: <LoveDrawCommand>[fallbackCommand],
    ),
  );

  canvas.save();
  canvas.transform(mesh.drawTransform.storage);
  canvas.translate(localBounds.left, localBounds.top);
  for (var instance = 0; instance < mesh.instanceCount; instance++) {
    _renderImageData(canvas, rasterized);
  }
  canvas.restore();
}

LoveImage? _resolvedMeshTextureImage(LoveMesh mesh) {
  return switch (mesh.textureObject) {
    final LoveCanvas canvas => canvas.snapshot(),
    final LoveImage image => image,
    _ => null,
  };
}

Object? _resolvedMeshTextureNativeImage(LoveImage? image) {
  return switch (image) {
    LoveCanvasSnapshot() => null,
    _ => image?.nativeImage,
  };
}

List<LoveColor> _texturedMeshModulationColors(
  LoveMeshCommand mesh,
  List<LoveMeshVertex> vertices,
) {
  return List<LoveColor>.generate(
    vertices.length,
    (index) => _modulateLoveColor(vertices[index].color, mesh.color),
    growable: false,
  );
}

LoveColor? _uniformTexturedMeshTint(List<LoveColor> modulationColors) {
  LoveColor? uniformColor;
  for (final modulationColor in modulationColors) {
    if (uniformColor == null) {
      uniformColor = modulationColor;
      continue;
    }
    if (modulationColor != uniformColor) {
      return null;
    }
  }

  return uniformColor ?? LoveColor.white;
}

Int32List? _texturedMeshRgbModulationColors(List<LoveColor> modulationColors) {
  final colors = Int32List(modulationColors.length);
  const defaultColor = Color(0xFFFFFFFF);
  var anyNonWhite = false;
  for (var index = 0; index < modulationColors.length; index++) {
    final modulationColor = modulationColors[index];
    final rgbColor = LoveColor(
      modulationColor.r,
      modulationColor.g,
      modulationColor.b,
      1,
    );
    colors[index] = _isWhiteRgb(modulationColor)
        ? defaultColor.toARGB32()
        : _toFlutterColor(rgbColor).toARGB32();
    if (!_isWhiteRgb(modulationColor)) {
      anyNonWhite = true;
    }
  }

  return anyNonWhite ? colors : null;
}

Int32List? _texturedMeshAlphaModulationColors(
  List<LoveColor> modulationColors,
) {
  final colors = Int32List(modulationColors.length);
  const defaultColor = Color(0xFFFFFFFF);
  var anyNonOpaque = false;
  for (var index = 0; index < modulationColors.length; index++) {
    final modulationColor = modulationColors[index];
    colors[index] = modulationColor.a >= 0.999999
        ? defaultColor.toARGB32()
        : _toFlutterColor(LoveColor(1, 1, 1, modulationColor.a)).toARGB32();
    if (modulationColor.a < 0.999999) {
      anyNonOpaque = true;
    }
  }

  return anyNonOpaque ? colors : null;
}

bool _isWhiteRgb(LoveColor color) {
  return color.r >= 0.999999 && color.g >= 0.999999 && color.b >= 0.999999;
}

Rect? _meshLocalBounds(List<LoveMeshVertex> vertices) {
  if (vertices.isEmpty) {
    return null;
  }

  var minX = vertices.first.x;
  var maxX = vertices.first.x;
  var minY = vertices.first.y;
  var maxY = vertices.first.y;
  for (final vertex in vertices.skip(1)) {
    if (vertex.x < minX) {
      minX = vertex.x;
    }
    if (vertex.x > maxX) {
      maxX = vertex.x;
    }
    if (vertex.y < minY) {
      minY = vertex.y;
    }
    if (vertex.y > maxY) {
      maxY = vertex.y;
    }
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

LoveShader? _softwareMeshShader(LoveShader? shader, Rect localBounds) {
  if (shader == null) {
    return null;
  }

  return switch (shader.kind) {
    LoveShaderKind.radialGradient => _shiftedRadialGradientShader(
      shader,
      x: -localBounds.left,
      y: -localBounds.top,
    ),
    _ => null,
  };
}

LoveShader _shiftedRadialGradientShader(
  LoveShader shader, {
  required double x,
  required double y,
}) {
  final shifted = shader.snapshot();
  final center = loveShaderVectorUniform(shader, 'center', 2);
  if (center != null) {
    shifted.send('center', <Object?>[center[0] + x, center[1] + y]);
  }
  return shifted;
}

List<LoveMeshVertex> _meshVerticesAfterCulling(
  LoveMeshCommand mesh,
  List<LoveMeshVertex> vertices,
  vm.Matrix4 combinedTransform,
) {
  final output = <LoveMeshVertex>[];

  void addTriangle(LoveMeshVertex a, LoveMeshVertex b, LoveMeshVertex c) {
    if (_meshTriangleIsCulled(mesh, a, b, c, combinedTransform)) {
      return;
    }
    output.addAll(<LoveMeshVertex>[a, b, c]);
  }

  switch (mesh.mesh.drawMode) {
    case LoveMeshDrawMode.triangles:
      for (var i = 0; i + 2 < vertices.length; i += 3) {
        addTriangle(vertices[i], vertices[i + 1], vertices[i + 2]);
      }
    case LoveMeshDrawMode.fan:
      for (var i = 1; i + 1 < vertices.length; i++) {
        addTriangle(vertices[0], vertices[i], vertices[i + 1]);
      }
    case LoveMeshDrawMode.strip:
      for (var i = 0; i + 2 < vertices.length; i++) {
        final even = i.isEven;
        addTriangle(
          even ? vertices[i] : vertices[i + 1],
          even ? vertices[i + 1] : vertices[i],
          vertices[i + 2],
        );
      }
    case LoveMeshDrawMode.points:
      return vertices;
  }

  return output;
}

bool _meshTriangleIsCulled(
  LoveMeshCommand mesh,
  LoveMeshVertex a,
  LoveMeshVertex b,
  LoveMeshVertex c,
  vm.Matrix4 combinedTransform,
) {
  if (mesh.cullMode == LoveGraphicsCullMode.none) {
    return false;
  }

  final pa = _transformMeshVertex(combinedTransform, a);
  final pb = _transformMeshVertex(combinedTransform, b);
  final pc = _transformMeshVertex(combinedTransform, c);
  final signedArea =
      ((pb.x - pa.x) * (pc.y - pa.y)) - ((pb.y - pa.y) * (pc.x - pa.x));
  if (signedArea.abs() < 1e-10) {
    return true;
  }

  final isFrontFacing = switch (mesh.frontFaceWinding) {
    LoveGraphicsVertexWinding.ccw => signedArea < 0,
    LoveGraphicsVertexWinding.cw => signedArea > 0,
  };

  return switch (mesh.cullMode) {
    LoveGraphicsCullMode.none => false,
    LoveGraphicsCullMode.front => isFrontFacing,
    LoveGraphicsCullMode.back => !isFrontFacing,
  };
}

({double x, double y}) _transformMeshVertex(
  vm.Matrix4 transform,
  LoveMeshVertex vertex,
) {
  final point = transform.transformed3(vm.Vector3(vertex.x, vertex.y, 0));
  return (x: point.x, y: point.y);
}

LoveColor _modulateLoveColor(LoveColor color, LoveColor tint) {
  return LoveColor(
    color.r * tint.r,
    color.g * tint.g,
    color.b * tint.b,
    color.a * tint.a,
  ).clamped();
}

void _configureShaderPaint(Paint paint, LoveDrawCommand command) {
  final binding = _registeredFragmentShaderBindingForCommand(command);
  final registeredShader = binding?.boundShader;
  if (registeredShader != null) {
    _assignRegisteredFragmentShaderToPaint(paint, registeredShader, binding!);
    return;
  }

  final shader = _radialGradientShaderForCommand(command);
  if (shader == null) {
    return;
  }

  paint.shader = shader;
}

ui.Shader? _radialGradientShaderForCommand(LoveDrawCommand command) {
  final shader = command.shader;
  if (shader == null || shader.kind != LoveShaderKind.radialGradient) {
    return null;
  }

  final center = loveShaderVectorUniform(shader, 'center', 2);
  final innerRadius = loveShaderNumberUniform(shader, 'innerRadius') ?? 0;
  final outerRadius = loveShaderNumberUniform(shader, 'outerRadius') ?? 0;
  final colorInner =
      loveShaderColorUniform(shader, 'colorInner') ?? command.color;
  final colorOuter =
      loveShaderColorUniform(shader, 'colorOuter') ?? command.color;

  if (center == null || outerRadius <= 0) {
    return null;
  }

  final innerStop = (innerRadius / outerRadius).clamp(0.0, 1.0);
  return ui.Gradient.radial(
    Offset(center[0], center[1]),
    outerRadius,
    <Color>[
      _toFlutterColor(colorInner),
      _toFlutterColor(colorInner),
      _toFlutterColor(colorOuter),
    ],
    <double>[0.0, innerStop, 1.0],
  );
}

/// Builds a [Paint] for the registered fragment shader bound to [command].
///
/// Returns `null` while the backing fragment program is still warming or if
/// one of its sampler inputs cannot be resolved yet.
Paint? _registeredFragmentPaintForCommand(
  LoveDrawCommand command, {
  LoveImage? sourceImage,
}) {
  final binding = _registeredFragmentShaderBindingForCommand(
    command,
    sourceImage: sourceImage,
  );
  final shader = binding?.boundShader;
  if (shader == null) {
    return null;
  }

  final paint = Paint()..isAntiAlias = false;
  _assignRegisteredFragmentShaderToPaint(paint, shader, binding!);
  return paint;
}

/// Resolves a registered fragment shader binding for [command].
_RegisteredFragmentShaderBinding? _registeredFragmentShaderBindingForCommand(
  LoveDrawCommand command, {
  LoveImage? sourceImage,
}) {
  final shader = command.shader;
  final assetKey = shader?.flutterFragmentAssetKey;
  if (shader == null || assetKey == null) {
    return null;
  }

  final fragmentShader = loveFlameRegisteredFragmentShaderCache.shaderForAsset(
    assetKey,
  );
  if (fragmentShader == null) {
    return null;
  }

  return _bindRegisteredFragmentShaderUniforms(
    fragmentShader,
    shader,
    assetKey: assetKey,
    sourceImage: sourceImage,
  );
}

/// Copies the current [LoveShader] uniform state into [fragmentShader].
///
/// If the shader declares exactly one sampler and no explicit sampler uniform
/// value has been sent, [sourceImage] is used as the implicit input texture.
_RegisteredFragmentShaderBinding _bindRegisteredFragmentShaderUniforms(
  ui.FragmentShader fragmentShader,
  LoveShader shader, {
  required String assetKey,
  LoveImage? sourceImage,
}) {
  var floatIndex = 0;
  var samplerIndex = 0;
  final declarations = shader.uniformDeclarations.entries.toList(
    growable: false,
  );
  final declarationSummaries = <String>[
    for (final entry in declarations) '${entry.key}:${entry.value.typeName}',
  ];
  final samplerBindings = <String>[];
  final samplerCount = declarations
      .where(
        (entry) => entry.value.valueKind == LoveShaderUniformValueKind.sampler,
      )
      .length;

  for (final entry in declarations) {
    final name = entry.key;
    final declaration = entry.value;
    if (declaration.valueKind == LoveShaderUniformValueKind.sampler) {
      final explicitSamplerImage = loveShaderSamplerUniformImage(shader, name);
      final samplerImage =
          explicitSamplerImage ?? (samplerCount == 1 ? sourceImage : null);
      final samplerOrigin = switch ((explicitSamplerImage, samplerCount == 1)) {
        (final LoveImage _, _) => 'uniform',
        (null, true) => 'sourceImage',
        _ => 'missing',
      };
      final resolvedSampler = _resolveRegisteredFragmentSamplerImage(
        samplerImage,
      );
      if (resolvedSampler == null) {
        samplerBindings.add(
          '$name[$samplerOrigin]=${_describeRegisteredFragmentLoveImage(samplerImage)} -> unresolved',
        );
        return _RegisteredFragmentShaderBinding(
          assetKey: assetKey,
          shader: fragmentShader,
          bound: false,
          declarationSummaries: declarationSummaries,
          samplerBindings: samplerBindings,
          boundFloatCount: floatIndex,
          boundSamplerCount: samplerIndex,
          unresolvedSamplerName: name,
        );
      }
      fragmentShader.setImageSampler(samplerIndex, resolvedSampler);
      samplerBindings.add(
        '$name[$samplerOrigin]=${_describeRegisteredFragmentLoveImage(samplerImage)} -> ${_describeRegisteredFragmentUiImage(resolvedSampler)}',
      );
      samplerIndex++;
      continue;
    }

    final values = _registeredFragmentNumericPayload(
      shader.uniform(name),
      declaration,
    );
    for (final value in values) {
      fragmentShader.setFloat(floatIndex, value);
      floatIndex++;
    }
  }

  return _RegisteredFragmentShaderBinding(
    assetKey: assetKey,
    shader: fragmentShader,
    bound: true,
    declarationSummaries: declarationSummaries,
    samplerBindings: samplerBindings,
    boundFloatCount: floatIndex,
    boundSamplerCount: samplerIndex,
  );
}

/// Assigns [shader] to [paint] and augments Flutter validation failures with
/// LOVE-specific binding diagnostics.
void _assignRegisteredFragmentShaderToPaint(
  Paint paint,
  ui.FragmentShader shader,
  _RegisteredFragmentShaderBinding binding,
) {
  try {
    paint.shader = shader;
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StateError(
        'Invalid FragmentShader ${binding.assetKey}: $error\n'
        '${binding.describe()}',
      ),
      stackTrace,
    );
  }
}

/// The result of binding LOVE uniform state to a registered fragment shader.
class _RegisteredFragmentShaderBinding {
  const _RegisteredFragmentShaderBinding({
    required this.assetKey,
    required this.shader,
    required this.bound,
    required this.declarationSummaries,
    required this.samplerBindings,
    required this.boundFloatCount,
    required this.boundSamplerCount,
    this.unresolvedSamplerName,
  });

  final String assetKey;
  final ui.FragmentShader shader;
  final bool bound;
  final List<String> declarationSummaries;
  final List<String> samplerBindings;
  final int boundFloatCount;
  final int boundSamplerCount;
  final String? unresolvedSamplerName;

  ui.FragmentShader? get boundShader => bound ? shader : null;

  String describe() {
    final declarations = declarationSummaries.isEmpty
        ? '(none)'
        : declarationSummaries.join(', ');
    final samplers = samplerBindings.isEmpty
        ? '(none)'
        : samplerBindings.join('; ');
    final unresolved = unresolvedSamplerName == null
        ? 'none'
        : unresolvedSamplerName!;
    return 'LOVE binding diagnostics: '
        'declarations=[$declarations], '
        'boundFloats=$boundFloatCount, '
        'boundSamplers=$boundSamplerCount, '
        'unresolvedSampler=$unresolved, '
        'samplers=[$samplers]';
  }
}

String _describeRegisteredFragmentLoveImage(LoveImage? image) {
  if (image == null) {
    return 'null';
  }
  return '${image.runtimeType}(source=${image.source}, '
      'size=${image.width}x${image.height}, '
      'pixels=${image.pixelWidth}x${image.pixelHeight})';
}

String _describeRegisteredFragmentUiImage(ui.Image image) {
  return 'ui.Image(${image.width}x${image.height})';
}

List<double> _registeredFragmentNumericPayload(
  Object? value,
  LoveShaderUniformDescriptor declaration,
) {
  final expectedLength = _registeredFragmentExpectedFloatCount(declaration);
  final values = <double>[];
  _appendRegisteredFragmentNumericValues(values, value);

  if (expectedLength == 0) {
    return values;
  }

  if (values.length < expectedLength) {
    values.addAll(List<double>.filled(expectedLength - values.length, 0.0));
  } else if (values.length > expectedLength) {
    values.removeRange(expectedLength, values.length);
  }

  return values;
}

int _registeredFragmentExpectedFloatCount(
  LoveShaderUniformDescriptor declaration,
) {
  final arrayMultiplier = declaration.arrayLength ?? 1;
  if (declaration.squareMatrixDimension case final int dimension) {
    return dimension * dimension * arrayMultiplier;
  }
  if (declaration.componentCount case final int componentCount) {
    return componentCount * arrayMultiplier;
  }
  return 0;
}

void _appendRegisteredFragmentNumericValues(
  List<double> target,
  Object? value,
) {
  switch (value) {
    case final num number:
      target.add(number.toDouble());
    case final bool flag:
      target.add(flag ? 1.0 : 0.0);
    case final List<Object?> values:
      for (final entry in values) {
        _appendRegisteredFragmentNumericValues(target, entry);
      }
    case _:
      break;
  }
}

ui.Image? _resolveRegisteredFragmentSamplerImage(LoveImage? image) {
  if (image == null) {
    return null;
  }

  return switch (image) {
    final LoveCanvas canvas => _liveCanvasShaderSamplerImage(canvas),
    _ => _staticShaderSamplerImage(image),
  };
}

ui.Image? _staticShaderSamplerImage(LoveImage image) {
  final rawImage = image.nativeImage;
  if (rawImage is ui.Image) {
    return rawImage;
  }

  final cached = _staticShaderSamplerImages[image];
  if (cached != null) {
    return cached;
  }
  if (_pendingStaticShaderSamplerImages.contains(image)) {
    return null;
  }

  final imageData =
      image.imageData ??
      switch (image.compressedImageData) {
        final LoveCompressedImageData compressed =>
          rasterizeCompressedImageData(compressed, mipmap: 1),
        null => null,
      };
  if (imageData == null) {
    return null;
  }

  _pendingStaticShaderSamplerImages.add(image);
  _imageDataToUiImage(imageData)
      .then((resolvedImage) {
        _staticShaderSamplerImages[image] = resolvedImage;
      })
      .whenComplete(() {
        _pendingStaticShaderSamplerImages.remove(image);
      });
  return null;
}

ui.Image? _liveCanvasShaderSamplerImage(LoveCanvas canvas) {
  final cached = _liveCanvasShaderSamplerImages[canvas];
  if (_pendingLiveCanvasShaderSamplerImages.contains(canvas)) {
    return cached;
  }

  _pendingLiveCanvasShaderSamplerImages.add(canvas);
  final snapshot = canvas.snapshot();
  _canvasSnapshotToUiImage(snapshot)
      .then((resolvedImage) {
        final previous = _liveCanvasShaderSamplerImages[canvas];
        if (previous != null && !identical(previous, resolvedImage)) {
          previous.dispose();
        }
        _liveCanvasShaderSamplerImages[canvas] = resolvedImage;
      })
      .whenComplete(() {
        _pendingLiveCanvasShaderSamplerImages.remove(canvas);
      });
  return cached;
}

Future<ui.Image> _imageDataToUiImage(LoveImageData imageData) {
  final pixels = Uint8List(imageData.width * imageData.height * 4);
  for (var y = 0; y < imageData.height; y++) {
    for (var x = 0; x < imageData.width; x++) {
      final color = imageData.getPixel(x, y).clamped();
      final offset = ((y * imageData.width) + x) * 4;
      pixels[offset] = (color.r * 255).round();
      pixels[offset + 1] = (color.g * 255).round();
      pixels[offset + 2] = (color.b * 255).round();
      pixels[offset + 3] = (color.a * 255).round();
    }
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    imageData.width,
    imageData.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<ui.Image> _canvasSnapshotToUiImage(LoveCanvasSnapshot snapshot) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (snapshot.width > 0 && snapshot.height > 0) {
    canvas.scale(
      snapshot.pixelWidth / snapshot.width,
      snapshot.pixelHeight / snapshot.height,
    );
  }
  _renderSurfaceSnapshot(
    canvas,
    snapshot.surface,
    Size(snapshot.width.toDouble(), snapshot.height.toDouble()),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(snapshot.pixelWidth, snapshot.pixelHeight);
  } finally {
    picture.dispose();
  }
}

Paint? _radialGradientImageOverlayPaintForCommand(LoveDrawCommand command) {
  if (!_usesImageRadialGradientPath(command)) {
    return null;
  }

  final shader = _radialGradientShaderForCommand(command);
  if (shader == null) {
    return null;
  }

  return Paint()
    ..shader = shader
    ..blendMode = BlendMode.modulate
    ..isAntiAlias = false;
}

bool _usesImageRadialGradientPath(LoveDrawCommand command) {
  return switch (command) {
    LoveImageCommand() ||
    LoveSpriteBatchCommand() ||
    LoveParticleSystemCommand() => true,
    final LoveMeshCommand mesh => _resolvedMeshTextureImage(mesh.mesh) != null,
    _ => false,
  };
}

Paint? _radialGradientMaskPaintForCommand(LoveDrawCommand command) {
  if (!_usesMaskRadialGradientPath(command)) {
    return null;
  }

  final shader = _radialGradientShaderForCommand(command);
  if (shader == null) {
    return null;
  }

  return Paint()
    ..shader = shader
    ..blendMode = BlendMode.srcIn
    ..isAntiAlias = false;
}

bool _usesMaskRadialGradientPath(LoveDrawCommand command) {
  return switch (command) {
    LoveLineCommand() ||
    LovePointsCommand() ||
    LoveTextCommand() ||
    LoveTextObjectCommand() => true,
    _ => false,
  };
}

ui.ColorFilter? _desaturationTintColorFilter(LoveShader shader) {
  final tint = loveShaderColorUniform(shader, 'tint');
  final strength = loveShaderNumberUniform(shader, 'strength');
  if (tint == null || strength == null) {
    return null;
  }

  const lumaR = 0.299;
  const lumaG = 0.587;
  const lumaB = 0.114;
  final base = 1.0 - strength;

  return ui.ColorFilter.matrix(<double>[
    base + (strength * tint.r * lumaR),
    strength * tint.r * lumaG,
    strength * tint.r * lumaB,
    0,
    0,
    strength * tint.g * lumaR,
    base + (strength * tint.g * lumaG),
    strength * tint.g * lumaB,
    0,
    0,
    strength * tint.b * lumaR,
    strength * tint.b * lumaG,
    base + (strength * tint.b * lumaB),
    0,
    0,
    strength * tint.a * lumaR,
    strength * tint.a * lumaG,
    strength * tint.a * lumaB,
    base,
    0,
  ]);
}

void _renderSurfaceSnapshot(
  Canvas canvas,
  LoveGraphicsSurfaceSnapshot surface,
  Size viewportSize,
) {
  if (_surfaceRequiresSoftwareFallback(surface)) {
    final pixelWidth = viewportSize.width.ceil();
    final pixelHeight = viewportSize.height.ceil();
    if (pixelWidth <= 0 || pixelHeight <= 0) {
      return;
    }

    final imageData = LoveCanvasRasterizer.rasterizeSurface(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      format: 'rgba8',
      snapshot: surface,
    );
    _renderImageData(canvas, imageData);
    return;
  }

  if (viewportSize.width > 0 && viewportSize.height > 0) {
    final clearRect = surface.clearScissor == null
        ? Offset.zero & viewportSize
        : _rectForScissor(surface.clearScissor!);
    final clearLayerPaint = _layerPaintForBlendAndMask(
      blendMode: LoveGraphicsBlendMode.alpha,
      colorMask: surface.clearColorMask,
    );
    if (clearLayerPaint != null) {
      canvas.saveLayer(clearRect, clearLayerPaint);
    }
    canvas.drawRect(
      clearRect,
      Paint()..color = _toFlutterColor(surface.clearColor),
    );
    if (clearLayerPaint != null) {
      canvas.restore();
    }
  }

  for (final command in surface.commands) {
    _renderRecordedCommand(canvas, command);
  }
}

bool _surfaceRequiresSoftwareFallback(LoveGraphicsSurfaceSnapshot surface) {
  if (!surface.clearColorMask.allEnabled) {
    return true;
  }

  for (final command in surface.commands) {
    if (command is LoveStencilClearCommand ||
        command.writesStencil ||
        command.stencilCompare != LoveGraphicsCompareMode.always ||
        _commandRequiresSoftwareFallback(command)) {
      return true;
    }
  }

  return false;
}

bool _commandRequiresSoftwareFallback(LoveDrawCommand command) {
  return command.blendMode == LoveGraphicsBlendMode.add ||
      command.blendMode == LoveGraphicsBlendMode.subtract ||
      command.blendMode == LoveGraphicsBlendMode.multiply ||
      command.blendMode == LoveGraphicsBlendMode.screen ||
      command.blendMode == LoveGraphicsBlendMode.none ||
      command.blendAlphaMode == LoveGraphicsBlendAlphaMode.premultiplied ||
      _commandUsesTransformedRadialGradientShader(command) ||
      !command.colorMask.allEnabled;
}

bool _commandUsesTransformedRadialGradientShader(LoveDrawCommand command) {
  final shader = command.shader;
  if (shader == null || shader.kind != LoveShaderKind.radialGradient) {
    return false;
  }

  if (!_isIdentityMatrix(command.transform)) {
    return true;
  }

  return switch (command) {
    final LoveTextCommand text => !_isIdentityMatrix(text.textTransform),
    final LoveTextObjectCommand text =>
      !_isIdentityMatrix(text.drawTransform) ||
          text.textObject.entries.any(
            (entry) => !_isIdentityMatrix(entry.transform),
          ),
    final LoveImageCommand image => !_isIdentityMatrix(image.drawTransform),
    final LoveSpriteBatchCommand spriteBatch =>
      !_isIdentityMatrix(spriteBatch.drawTransform) ||
          spriteBatch.spriteBatch.spritesToDraw().any(
            (sprite) => !_isIdentityMatrix(sprite.transform),
          ),
    final LoveParticleSystemCommand particleSystem =>
      !_isIdentityMatrix(particleSystem.drawTransform) ||
          particleSystem.particleSystem.particles.any(
            (particle) => !_isIdentityMatrix(particle.transform),
          ),
    final LoveMeshCommand mesh => !_isIdentityMatrix(mesh.drawTransform),
    _ => false,
  };
}

bool _isIdentityMatrix(vm.Matrix4 matrix) {
  final storage = matrix.storage;
  return storage[0] == 1 &&
      storage[1] == 0 &&
      storage[2] == 0 &&
      storage[3] == 0 &&
      storage[4] == 0 &&
      storage[5] == 1 &&
      storage[6] == 0 &&
      storage[7] == 0 &&
      storage[8] == 0 &&
      storage[9] == 0 &&
      storage[10] == 1 &&
      storage[11] == 0 &&
      storage[12] == 0 &&
      storage[13] == 0 &&
      storage[14] == 0 &&
      storage[15] == 1;
}

void _renderImageData(Canvas canvas, LoveImageData imageData) {
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;

  for (var y = 0; y < imageData.height; y++) {
    LoveColor? runColor;
    var runStart = 0;

    void flushRun(int endX) {
      final color = runColor;
      if (color == null || color.a <= 0) {
        return;
      }

      paint.color = _toFlutterColor(color);
      canvas.drawRect(
        Rect.fromLTWH(
          runStart.toDouble(),
          y.toDouble(),
          (endX - runStart).toDouble(),
          1,
        ),
        paint,
      );
    }

    for (var x = 0; x < imageData.width; x++) {
      final color = imageData.getPixel(x, y);
      if (runColor == null) {
        runColor = color;
        runStart = x;
        continue;
      }

      if (color == runColor) {
        continue;
      }

      flushRun(x);
      runColor = color;
      runStart = x;
    }

    flushRun(imageData.width);
  }
}

Color _toFlutterColor(LoveColor color) {
  final clamped = color.clamped();
  return Color.fromRGBO(
    (clamped.r * 255).round(),
    (clamped.g * 255).round(),
    (clamped.b * 255).round(),
    clamped.a,
  );
}

PaintingStyle _shapeStyle(LoveGraphicsDrawMode mode, bool wireframe) {
  return wireframe || mode == LoveGraphicsDrawMode.line
      ? PaintingStyle.stroke
      : PaintingStyle.fill;
}

Paint? _layerPaintForCommand(LoveDrawCommand command) {
  return _layerPaintForBlendAndMask(
    blendMode: command.blendMode,
    colorMask: command.colorMask,
  );
}

Paint? _shaderLayerPaintForCommand(LoveDrawCommand command) {
  final shader = command.shader;
  if (shader == null) {
    return null;
  }

  return switch (shader.kind) {
    LoveShaderKind.desaturationTint => switch (_desaturationTintColorFilter(
      shader,
    )) {
      final ui.ColorFilter filter => Paint()..colorFilter = filter,
      null => null,
    },
    _ => null,
  };
}

Paint? _layerPaintForBlendAndMask({
  required LoveGraphicsBlendMode blendMode,
  required LoveGraphicsColorMask colorMask,
}) {
  final resolvedBlendMode = _blendModeForLove(blendMode);
  final colorFilter = _colorFilterForMask(colorMask);
  if (resolvedBlendMode == ui.BlendMode.srcOver && colorFilter == null) {
    return null;
  }

  return Paint()
    ..blendMode = resolvedBlendMode
    ..colorFilter = colorFilter;
}

ui.BlendMode _blendModeForLove(LoveGraphicsBlendMode mode) {
  return switch (mode) {
    LoveGraphicsBlendMode.alpha => ui.BlendMode.srcOver,
    LoveGraphicsBlendMode.add => ui.BlendMode.plus,
    LoveGraphicsBlendMode.subtract => ui.BlendMode.srcOver,
    LoveGraphicsBlendMode.multiply => ui.BlendMode.multiply,
    LoveGraphicsBlendMode.lighten => ui.BlendMode.lighten,
    LoveGraphicsBlendMode.darken => ui.BlendMode.darken,
    LoveGraphicsBlendMode.screen => ui.BlendMode.screen,
    LoveGraphicsBlendMode.replace => ui.BlendMode.src,
    LoveGraphicsBlendMode.none => ui.BlendMode.src,
  };
}

ui.ColorFilter? _colorFilterForMask(LoveGraphicsColorMask mask) {
  if (mask.allEnabled) {
    return null;
  }

  return ui.ColorFilter.matrix(<double>[
    mask.red ? 1 : 0,
    0,
    0,
    0,
    0,
    0,
    mask.green ? 1 : 0,
    0,
    0,
    0,
    0,
    0,
    mask.blue ? 1 : 0,
    0,
    0,
    0,
    0,
    0,
    mask.alpha ? 1 : 0,
    0,
  ]);
}

FilterQuality _filterQualityForLove(LoveGraphicsDefaultFilter filter) {
  return switch ((filter.min, filter.mag)) {
    (LoveGraphicsFilterMode.nearest, LoveGraphicsFilterMode.nearest) =>
      FilterQuality.none,
    _ => FilterQuality.low,
  };
}

TextAlign _textAlignForLove(String align) {
  return switch (align) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    'justify' => TextAlign.justify,
    _ => TextAlign.left,
  };
}

StrokeJoin _strokeJoinForLove(LoveGraphicsLineJoin join) {
  return switch (join) {
    LoveGraphicsLineJoin.none => StrokeJoin.bevel,
    LoveGraphicsLineJoin.miter => StrokeJoin.miter,
    LoveGraphicsLineJoin.bevel => StrokeJoin.bevel,
  };
}

bool _isAntiAliasForLove(LoveGraphicsLineStyle style) {
  return switch (style) {
    LoveGraphicsLineStyle.smooth => true,
    LoveGraphicsLineStyle.rough => false,
  };
}

ui.VertexMode _vertexModeForLove(LoveMeshDrawMode mode) {
  return switch (mode) {
    LoveMeshDrawMode.fan => ui.VertexMode.triangleFan,
    LoveMeshDrawMode.strip => ui.VertexMode.triangleStrip,
    LoveMeshDrawMode.triangles => ui.VertexMode.triangles,
    LoveMeshDrawMode.points => ui.VertexMode.triangles,
  };
}
