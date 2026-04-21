import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../love_runtime.dart';
import 'love_flame_host.dart';

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

  void Function(double dt)? onTick;

  @override
  Color backgroundColor() => const Color(0xFF050816);

  @override
  void update(double dt) {
    super.update(dt);
    onTick?.call(dt);
  }

  @override
  void render(Canvas canvas) {
    final viewportSize = Size(canvasSize.x, canvasSize.y);
    if (viewportSize.width > 0 && viewportSize.height > 0) {
      final scissor = host.graphics.clearScissor;
      final clearRect = scissor == null
          ? Offset.zero & viewportSize
          : _rectForScissor(scissor);
      final clearLayerPaint = _layerPaintForBlendAndMask(
        blendMode: LoveGraphicsBlendMode.alpha,
        colorMask: host.graphics.clearColorMask,
      );
      if (clearLayerPaint != null) {
        canvas.saveLayer(clearRect, clearLayerPaint);
      }
      canvas.drawRect(
        clearRect,
        Paint()..color = _toFlutterColor(host.graphics.clearColor),
      );
      if (clearLayerPaint != null) {
        canvas.restore();
      }
    }

    super.render(canvas);

    for (final command in host.graphics.commands) {
      _renderRecordedCommand(canvas, command);
    }
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
  if (layerPaint != null) {
    canvas.saveLayer(null, layerPaint);
  }
  canvas.transform(command.transform.storage);

  switch (command) {
    case LoveParticleSystemCommand():
      break;
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
      final painter = TextPainter(
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
      )..layout(maxWidth: text.limit ?? double.infinity);
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
          maxWidth: entry.wrapLimit != null && entry.wrapLimit! > 0
              ? entry.wrapLimit!
              : double.infinity,
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
    image: image.image,
    quad: image.quad,
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
      image: spriteBatchCommand.spriteBatch.texture,
      quad: entry.quad,
      drawTransform: entry.transform,
      tint: entry.color == null
          ? spriteBatchCommand.color
          : spriteBatchCommand.color.modulate(entry.color!),
    );
  }
  canvas.restore();
}

// ignore: unused_element
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
  required LoveImage image,
  required LoveQuad? quad,
  required vm.Matrix4 drawTransform,
  required LoveColor tint,
}) {
  final sourceRect = quad == null
      ? Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
      : Rect.fromLTWH(quad.x, quad.y, quad.width, quad.height);
  final destinationRect = Rect.fromLTWH(
    0,
    0,
    sourceRect.width,
    sourceRect.height,
  );

  canvas.save();
  canvas.transform(drawTransform.storage);

  switch (image) {
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
      final rawImage = image.nativeImage;
      final imageData = image.imageData;
      final shouldRenderImageData =
          imageData != null &&
          (image.preferImageDataRendering || rawImage is! ui.Image);
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
        canvas.restore();
        return;
      }
      if (rawImage is! ui.Image) {
        canvas.restore();
        return;
      }

      final paint = Paint()
        ..filterQuality = _filterQualityForLove(image.filter);
      if (tint != LoveColor.white) {
        paint.colorFilter = ColorFilter.mode(
          _toFlutterColor(tint),
          BlendMode.modulate,
        );
      }
      canvas.drawImageRect(rawImage, sourceRect, destinationRect, paint);
  }
  canvas.restore();
}

void _renderMeshCommand(Canvas canvas, LoveMeshCommand mesh) {
  final vertices = mesh.mesh.verticesForDraw();
  if (vertices.isEmpty) {
    return;
  }

  canvas.transform(mesh.drawTransform.storage);
  final combinedTransform = vm.Matrix4.copy(mesh.transform)
    ..multiply(mesh.drawTransform);
  final effectiveMode = mesh.cullMode == LoveGraphicsCullMode.none
      ? mesh.mesh.drawMode
      : LoveMeshDrawMode.triangles;
  final effectiveVertices = mesh.cullMode == LoveGraphicsCullMode.none
      ? vertices
      : _meshVerticesAfterCulling(mesh, vertices, combinedTransform);
  if (effectiveVertices.isEmpty) {
    return;
  }

  final positions = Float32List(effectiveVertices.length * 2);
  final colors = Int32List(effectiveVertices.length);
  for (var index = 0; index < effectiveVertices.length; index++) {
    final vertex = effectiveVertices[index];
    positions[index * 2] = vertex.x;
    positions[(index * 2) + 1] = vertex.y;
    colors[index] = _toFlutterColor(
      _modulateLoveColor(vertex.color, mesh.color),
    ).toARGB32();
  }

  final uiVertices = ui.Vertices.raw(
    _vertexModeForLove(effectiveMode),
    positions,
    colors: colors,
  );
  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = mesh.wireframe ? PaintingStyle.stroke : PaintingStyle.fill
    ..strokeWidth = mesh.lineWidth
    ..strokeJoin = _strokeJoinForLove(mesh.lineJoin)
    ..isAntiAlias = _isAntiAliasForLove(mesh.lineStyle);
  _configureShaderPaint(paint, mesh);

  canvas.drawVertices(uiVertices, ui.BlendMode.srcOver, paint);
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
  final shader = command.shader;
  if (shader == null || shader.kind != LoveShaderKind.radialGradient) {
    return;
  }

  final center = _shaderVectorUniform(shader, 'center', 2);
  final innerRadius = _shaderNumberUniform(shader, 'innerRadius') ?? 0;
  final outerRadius = _shaderNumberUniform(shader, 'outerRadius') ?? 0;
  final colorInner = _shaderColorUniform(shader, 'colorInner') ?? command.color;
  final colorOuter = _shaderColorUniform(shader, 'colorOuter') ?? command.color;

  if (center == null || outerRadius <= 0) {
    return;
  }

  final innerStop = (innerRadius / outerRadius).clamp(0.0, 1.0);
  paint.shader = ui.Gradient.radial(
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

double? _shaderNumberUniform(LoveShader shader, String name) {
  final value = shader.uniform(name);
  return switch (value) {
    final num number => number.toDouble(),
    final List<Object?> values when values.length == 1 && values.first is num =>
      (values.first as num).toDouble(),
    _ => null,
  };
}

List<double>? _shaderVectorUniform(LoveShader shader, String name, int length) {
  final value = shader.uniform(name);
  if (value is! List<Object?> || value.length < length) {
    return null;
  }

  final result = <double>[];
  for (var index = 0; index < length; index++) {
    final entry = value[index];
    if (entry is! num) {
      return null;
    }
    result.add(entry.toDouble());
  }
  return result;
}

LoveColor? _shaderColorUniform(LoveShader shader, String name) {
  final value = shader.uniform(name);
  if (value is LoveColor) {
    return value;
  }

  if (value is! List<Object?> || value.length < 3) {
    return null;
  }

  final components = <double>[];
  for (final entry in value.take(4)) {
    if (entry is! num) {
      return null;
    }
    components.add(entry.toDouble());
  }
  while (components.length < 4) {
    components.add(1.0);
  }

  return LoveColor(components[0], components[1], components[2], components[3]);
}

void _renderSurfaceSnapshot(
  Canvas canvas,
  LoveGraphicsSurfaceSnapshot surface,
  Size viewportSize,
) {
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
