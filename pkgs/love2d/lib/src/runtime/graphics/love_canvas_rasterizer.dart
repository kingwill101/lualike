part of '../love_runtime.dart';

/// A CPU-based rasterizer that replays LOVE draw commands into image data.
///
/// This is used for software readback paths such as `Canvas:newImageData`.
/// Compared to the GPU pipeline, shader support is limited, text rendering is
/// approximate, MSAA is not applied, some rounded-rectangle cases fall back to
/// polygon approximations, and unsupported blend modes degrade to `alpha`.
class LoveCanvasRasterizer {
  /// Creates a software rasterizer seeded with the target surface clear state.
  LoveCanvasRasterizer({
    required this.pixelWidth,
    required this.pixelHeight,
    required this.format,
    required LoveColor clearColor,
    this.originX = 0,
    this.originY = 0,
    LoveGraphicsColorMask clearColorMask = LoveGraphicsColorMask.all,
    int clearStencil = 0,
    LoveScissorRect? clearScissor,
  }) : _data = LoveImageData(
         width: pixelWidth,
         height: pixelHeight,
         format: format,
       ),
       _stencil = Uint8List(pixelWidth * pixelHeight) {
    _applyClear(clearColor.clamped(), clearColorMask, clearScissor);
    _applyStencilClear(clearStencil, clearScissor);
  }

  /// The output width in pixels.
  final int pixelWidth;

  /// The output height in pixels.
  final int pixelHeight;

  /// The LOVE pixel format used for the destination image.
  final String format;

  /// The global X origin represented by the rasterized output.
  final int originX;

  /// The global Y origin represented by the rasterized output.
  final int originY;

  /// The image data receiving rasterized draw output.
  final LoveImageData _data;

  /// The software stencil buffer tracked alongside [_data].
  final Uint8List _stencil;

  /// Per-snapshot rasterisation cache for canvas-in-canvas scenarios.
  final Map<Object, LoveImageData> _snapshotCache = {};

  /// The cache of decoded compressed images used during rasterization.
  final Map<LoveCompressedImageData, LoveImageData?> _compressedImageCache =
      HashMap<LoveCompressedImageData, LoveImageData?>.identity();

  /// The completed [LoveImageData] – call after [rasterize].
  LoveImageData get result => _data;

  /// Rasterizes a surface snapshot into a new [LoveImageData].
  static LoveImageData rasterizeSurface({
    required int pixelWidth,
    required int pixelHeight,
    required String format,
    required LoveGraphicsSurfaceSnapshot snapshot,
  }) {
    final rasterizer = LoveCanvasRasterizer(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      format: format,
      clearColor: snapshot.clearColor,
      clearColorMask: snapshot.clearColorMask,
      clearStencil: snapshot.clearStencil,
      clearScissor: snapshot.clearScissor,
    );
    rasterizer.rasterize(snapshot);
    return rasterizer.result;
  }

  /// Rasterizes a clipped region of a surface snapshot into a new [LoveImageData].
  static LoveImageData rasterizeSurfaceRegion({
    required int left,
    required int top,
    required int pixelWidth,
    required int pixelHeight,
    required String format,
    required LoveGraphicsSurfaceSnapshot snapshot,
  }) {
    final rasterizer = LoveCanvasRasterizer(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      format: format,
      clearColor: snapshot.clearColor,
      clearColorMask: snapshot.clearColorMask,
      clearStencil: snapshot.clearStencil,
      clearScissor: snapshot.clearScissor,
      originX: left,
      originY: top,
    );
    rasterizer.rasterize(snapshot);
    return rasterizer.result;
  }

  // --------------------------------------------------------------------------
  // Entry point
  // --------------------------------------------------------------------------

  /// Rasterizes all commands in [snapshot] into [result].
  void rasterize(LoveGraphicsSurfaceSnapshot snapshot) {
    for (final cmd in snapshot.commands) {
      _dispatch(cmd);
    }
  }

  /// Applies the surface clear color to the raster output.
  void _applyClear(
    LoveColor clearColor,
    LoveGraphicsColorMask clearMask,
    LoveScissorRect? clearScissor,
  ) {
    final left = clearScissor == null
        ? 0
        : math.max(0, clearScissor.x.floor() - originX);
    final top = clearScissor == null
        ? 0
        : math.max(0, clearScissor.y.floor() - originY);
    final right = clearScissor == null
        ? pixelWidth
        : math.min(
            pixelWidth,
            (clearScissor.x + clearScissor.width).ceil() - originX,
          );
    final bottom = clearScissor == null
        ? pixelHeight
        : math.min(
            pixelHeight,
            (clearScissor.y + clearScissor.height).ceil() - originY,
          );

    if (left >= right || top >= bottom) {
      return;
    }

    for (var py = top; py < bottom; py++) {
      for (var px = left; px < right; px++) {
        final dst = _data.getPixel(px, py);
        _data.setPixel(
          px,
          py,
          LoveColor(
            clearMask.red ? clearColor.r : dst.r,
            clearMask.green ? clearColor.g : dst.g,
            clearMask.blue ? clearColor.b : dst.b,
            clearMask.alpha ? clearColor.a : dst.a,
          ),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // Command dispatch
  // --------------------------------------------------------------------------

  /// Dispatches [cmd] to the matching software rasterization path.
  void _dispatch(LoveDrawCommand cmd) {
    switch (cmd) {
      case final LoveColorClearCommand c:
        _applyClear(c.color, c.colorMask, c.scissor);
      case final LoveStencilClearCommand c:
        _applyStencilClear(c.value, c.scissor);
      case final LoveRectangleCommand c:
        _renderRectangle(c);
      case final LoveCircleCommand c:
        _renderCircle(c);
      case final LoveEllipseCommand c:
        _renderEllipse(c);
      case final LoveArcCommand c:
        _renderArc(c);
      case final LoveLineCommand c:
        _renderLine(c);
      case final LovePolygonCommand c:
        _renderPolygon(c);
      case final LovePointsCommand c:
        _renderPoints(c);
      case final LoveImageCommand c:
        _renderImage(c);
      case LoveVideoCommand():
        break;
      case final LoveSpriteBatchCommand c:
        _renderSpriteBatch(c);
      case final LoveParticleSystemCommand c:
        _renderParticleSystem(c);
      case final LoveMeshCommand c:
        _renderMesh(c);
      case final LoveTextCommand c:
        _renderTextApprox(c);
      case final LoveTextObjectCommand c:
        _renderTextObjectApprox(c);
    }
  }

  // --------------------------------------------------------------------------
  // Shape commands
  // --------------------------------------------------------------------------

  void _renderRectangle(LoveRectangleCommand cmd) {
    final pts = _mapPoints(cmd.transform, [
      (x: cmd.x, y: cmd.y),
      (x: cmd.x + cmd.width, y: cmd.y),
      (x: cmd.x + cmd.width, y: cmd.y + cmd.height),
      (x: cmd.x, y: cmd.y + cmd.height),
    ]);

    if (cmd.mode == LoveGraphicsDrawMode.fill) {
      if (cmd.cornerRadiusX <= 0 && cmd.cornerRadiusY <= 0) {
        _fillPolygon(cmd, pts, cmd.color);
      } else {
        // Generate a polygon that approximates the rounded corners.
        _fillPolygon(cmd, _roundedRectPts(cmd), cmd.color);
      }
    } else {
      _strokePolyline(cmd, pts, cmd.color, closed: true);
    }
  }

  void _renderCircle(LoveCircleCommand cmd) {
    final c = _mapPt(cmd.transform, cmd.x, cmd.y);
    final r = cmd.radius * _scaleX(cmd.transform);

    if (cmd.mode == LoveGraphicsDrawMode.fill) {
      _fillCircle(cmd, c.x, c.y, r, cmd.color);
    } else {
      _strokeRing(cmd, c.x, c.y, r, cmd.color);
    }
  }

  void _renderEllipse(LoveEllipseCommand cmd) {
    final c = _mapPt(cmd.transform, cmd.x, cmd.y);
    final rx = cmd.radiusX * _scaleX(cmd.transform);
    final ry = cmd.radiusY * _scaleY(cmd.transform);

    if (cmd.mode == LoveGraphicsDrawMode.fill) {
      _fillEllipse(cmd, c.x, c.y, rx, ry, cmd.color);
    } else {
      _strokeEllipseBand(cmd, c.x, c.y, rx, ry, cmd.color);
    }
  }

  void _renderArc(LoveArcCommand cmd) {
    final c = _mapPt(cmd.transform, cmd.x, cmd.y);
    final r = cmd.radius * _scaleX(cmd.transform);

    if (cmd.drawMode == LoveGraphicsDrawMode.fill) {
      _fillArcPoly(
        cmd,
        c.x,
        c.y,
        r,
        cmd.angle1,
        cmd.angle2,
        cmd.arcMode,
        cmd.color,
      );
    } else {
      _strokeArcPath(
        cmd,
        c.x,
        c.y,
        r,
        cmd.angle1,
        cmd.angle2,
        cmd.arcMode,
        cmd.color,
      );
    }
  }

  void _renderLine(LoveLineCommand cmd) {
    final pts = _mapPoints(cmd.transform, cmd.points);
    for (var i = 0; i < pts.length - 1; i++) {
      _thickLine(
        cmd,
        pts[i].x,
        pts[i].y,
        pts[i + 1].x,
        pts[i + 1].y,
        cmd.color,
      );
    }
  }

  void _renderPolygon(LovePolygonCommand cmd) {
    final pts = _mapPoints(cmd.transform, cmd.points);
    if (cmd.mode == LoveGraphicsDrawMode.fill) {
      _fillPolygon(cmd, pts, cmd.color);
    } else {
      _strokePolyline(cmd, pts, cmd.color, closed: true);
    }
  }

  void _renderPoints(LovePointsCommand cmd) {
    final half = cmd.pointSize * 0.5;
    for (final pt in cmd.points) {
      final cp = _mapPt(cmd.transform, pt.x, pt.y);
      final color = pt.color ?? cmd.color;
      _fillAARect(
        cmd,
        (cp.x - half).round(),
        (cp.y - half).round(),
        (cp.x + half).ceil(),
        (cp.y + half).ceil(),
        color,
      );
    }
  }

  // --------------------------------------------------------------------------
  // Image / SpriteBatch / ParticleSystem / Mesh
  // --------------------------------------------------------------------------

  void _renderImage(LoveImageCommand cmd) {
    final combined = Matrix4.copy(cmd.transform)..multiply(cmd.drawTransform);
    _blitImage(
      cmd: cmd,
      fullTransform: combined,
      image: cmd.image,
      quad: cmd.quad,
      layer: cmd.layer,
      tint: cmd.color,
    );
  }

  void _renderSpriteBatch(LoveSpriteBatchCommand cmd) {
    final batchBase = Matrix4.copy(cmd.transform)..multiply(cmd.drawTransform);
    for (final sprite in cmd.spriteBatch.spritesToDraw()) {
      final spriteTint = sprite.color == null
          ? cmd.color
          : LoveColor(
              cmd.color.r * sprite.color!.r,
              cmd.color.g * sprite.color!.g,
              cmd.color.b * sprite.color!.b,
              cmd.color.a * sprite.color!.a,
            );
      final fullTx = Matrix4.copy(batchBase)..multiply(sprite.transform);
      _blitImage(
        cmd: cmd,
        fullTransform: fullTx,
        image: cmd.spriteBatch.texture,
        quad: sprite.quad,
        layer: sprite.layer,
        tint: spriteTint,
      );
    }
  }

  void _renderParticleSystem(LoveParticleSystemCommand cmd) {
    final base = Matrix4.copy(cmd.transform)..multiply(cmd.drawTransform);
    for (final particle in cmd.particleSystem.particles) {
      final tint = LoveColor(
        cmd.color.r * particle.color.r,
        cmd.color.g * particle.color.g,
        cmd.color.b * particle.color.b,
        cmd.color.a * particle.color.a,
      );
      final fullTx = Matrix4.copy(base)..multiply(particle.transform);
      _blitImage(
        cmd: cmd,
        fullTransform: fullTx,
        image: cmd.particleSystem.texture,
        quad: particle.quad,
        tint: tint,
      );
    }
  }

  void _renderMesh(LoveMeshCommand cmd) {
    final verts = cmd.mesh.verticesForDraw();
    if (verts.isEmpty || cmd.instanceCount <= 0) return;

    final fullTx = Matrix4.copy(cmd.transform)..multiply(cmd.drawTransform);
    final textureImage = _resolvedMeshTextureImage(cmd.mesh);

    if (cmd.wireframe && cmd.mesh.drawMode != LoveMeshDrawMode.points) {
      for (var instance = 0; instance < cmd.instanceCount; instance++) {
        switch (cmd.mesh.drawMode) {
          case LoveMeshDrawMode.triangles:
            for (var i = 0; i + 2 < verts.length; i += 3) {
              _rasterWireframeTriangle(
                cmd,
                fullTx,
                textureImage,
                verts[i],
                verts[i + 1],
                verts[i + 2],
              );
            }
          case LoveMeshDrawMode.fan:
            for (var i = 1; i + 1 < verts.length; i++) {
              _rasterWireframeTriangle(
                cmd,
                fullTx,
                textureImage,
                verts[0],
                verts[i],
                verts[i + 1],
              );
            }
          case LoveMeshDrawMode.strip:
            for (var i = 0; i + 2 < verts.length; i++) {
              final even = i.isEven;
              _rasterWireframeTriangle(
                cmd,
                fullTx,
                textureImage,
                even ? verts[i] : verts[i + 1],
                even ? verts[i + 1] : verts[i],
                verts[i + 2],
              );
            }
          case LoveMeshDrawMode.points:
            break;
        }
      }
      return;
    }

    for (var instance = 0; instance < cmd.instanceCount; instance++) {
      switch (cmd.mesh.drawMode) {
        case LoveMeshDrawMode.triangles:
          for (var i = 0; i + 2 < verts.length; i += 3) {
            _rasterTriangle(cmd, fullTx, verts[i], verts[i + 1], verts[i + 2]);
          }
        case LoveMeshDrawMode.fan:
          for (var i = 1; i + 1 < verts.length; i++) {
            _rasterTriangle(cmd, fullTx, verts[0], verts[i], verts[i + 1]);
          }
        case LoveMeshDrawMode.strip:
          for (var i = 0; i + 2 < verts.length; i++) {
            final even = i.isEven;
            _rasterTriangle(
              cmd,
              fullTx,
              even ? verts[i] : verts[i + 1],
              even ? verts[i + 1] : verts[i],
              verts[i + 2],
            );
          }
        case LoveMeshDrawMode.points:
          for (final v in verts) {
            _rasterMeshPoint(cmd, fullTx, textureImage, v);
          }
      }
    }
  }

  // --------------------------------------------------------------------------
  // Text approximation
  // --------------------------------------------------------------------------

  void _renderTextApprox(LoveTextCommand cmd) {
    // Approximate: filled bounding box in the text colour.
    // Proper glyph rendering would need font metrics not available here.
    final approxW = cmd.text.length * cmd.font.size * 0.6;
    final approxH = cmd.font.size.toDouble();

    final fullTx = Matrix4.copy(cmd.transform)..multiply(cmd.textTransform);
    final pts = _mapPoints(fullTx, [
      (x: cmd.x, y: cmd.y),
      (x: cmd.x + approxW, y: cmd.y),
      (x: cmd.x + approxW, y: cmd.y + approxH),
      (x: cmd.x, y: cmd.y + approxH),
    ]);
    _fillPolygon(cmd, pts, cmd.color);
  }

  void _renderTextObjectApprox(LoveTextObjectCommand cmd) {
    for (final entry in cmd.textObject.entries) {
      if (entry.spans.isEmpty) continue;

      final entryTx = Matrix4.copy(cmd.transform)
        ..multiply(cmd.drawTransform)
        ..multiply(entry.transform);

      for (final span in entry.spans) {
        final approxW = span.text.length * cmd.textObject.font.size * 0.6;
        final approxH = cmd.textObject.font.size.toDouble();
        final pts = _mapPoints(entryTx, [
          (x: 0.0, y: 0.0),
          (x: approxW, y: 0.0),
          (x: approxW, y: approxH),
          (x: 0.0, y: approxH),
        ]);
        final color = span.color == null
            ? cmd.color
            : LoveColor(
                cmd.color.r * span.color!.r,
                cmd.color.g * span.color!.g,
                cmd.color.b * span.color!.b,
                cmd.color.a * span.color!.a,
              );
        _fillPolygon(cmd, pts, color);
      }
    }
  }

  // --------------------------------------------------------------------------
  // Image blit (core)
  // --------------------------------------------------------------------------

  void _blitImage({
    required LoveDrawCommand cmd,
    required Matrix4 fullTransform,
    required LoveImage image,
    required LoveQuad? quad,
    int? layer,
    required LoveColor tint,
  }) {
    final resolvedImage = resolveDrawableImageForLayer(image, layer: layer);
    if (resolvedImage == null) {
      return;
    }

    final srcX = quad?.x ?? 0.0;
    final srcY = quad?.y ?? 0.0;
    final srcW = quad?.width ?? resolvedImage.width.toDouble();
    final srcH = quad?.height ?? resolvedImage.height.toDouble();

    if (srcW <= 0 || srcH <= 0) return;

    // Destination quad corners in canvas-pixel space.
    final corners = _mapPoints(fullTransform, [
      (x: 0.0, y: 0.0),
      (x: srcW, y: 0.0),
      (x: srcW, y: srcH),
      (x: 0.0, y: srcH),
    ]);

    var mnX = double.infinity;
    var mnY = double.infinity;
    var mxX = double.negativeInfinity;
    var mxY = double.negativeInfinity;
    for (final p in corners) {
      if (p.x < mnX) mnX = p.x;
      if (p.y < mnY) mnY = p.y;
      if (p.x > mxX) mxX = p.x;
      if (p.y > mxY) mxY = p.y;
    }

    final ix0 = math.max(mnX.floor(), 0);
    final iy0 = math.max(mnY.floor(), 0);
    final ix1 = math.min(mxX.ceil(), pixelWidth - 1);
    final iy1 = math.min(mxY.ceil(), pixelHeight - 1);

    if (ix1 < ix0 || iy1 < iy0) return;

    // Invert transform to map canvas pixels → draw-local space.
    final invTx = Matrix4.copy(fullTransform);
    if (invTx.invert() == 0) return;

    for (var py = iy0; py <= iy1; py++) {
      for (var px = ix0; px <= ix1; px++) {
        // Scissor test.
        final globalPx = px + originX;
        final globalPy = py + originY;
        if (cmd.scissor != null &&
            (globalPx < cmd.scissor!.x ||
                globalPx >= cmd.scissor!.x + cmd.scissor!.width ||
                globalPy < cmd.scissor!.y ||
                globalPy >= cmd.scissor!.y + cmd.scissor!.height)) {
          continue;
        }

        // Map pixel centre back to draw-local space.
        final local = invTx.transformed3(Vector3(px + 0.5, py + 0.5, 0));

        // Cull pixels outside the destination quad.
        if (local.x < 0 || local.y < 0 || local.x > srcW || local.y > srcH) {
          continue;
        }

        // Sample source image.
        final sampled = _sampleImage(
          resolvedImage,
          srcX + local.x,
          srcY + local.y,
        );
        if (sampled == null) continue;

        final tinted = LoveColor(
          sampled.r * tint.r,
          sampled.g * tint.g,
          sampled.b * tint.b,
          sampled.a * tint.a,
        );

        _writeFragment(cmd, px, py, tinted);
      }
    }
  }

  /// Nearest-neighbour sample of [image] at pixel coordinates (x, y).
  /// Returns null when no pixel data is available for the image.
  LoveColor? _sampleImage(LoveImage image, double x, double y) {
    if (image is LoveCanvasSnapshot) {
      return _sampleCanvasSnapshot(image, x, y);
    }
    final data = image.imageData ?? _sampleableCompressedImageData(image);
    if (data == null) return null;
    final ix = x.floor().clamp(0, data.width - 1);
    final iy = y.floor().clamp(0, data.height - 1);
    return data.getPixel(ix, iy);
  }

  LoveImageData? _sampleableCompressedImageData(LoveImage image) {
    final compressed = image.compressedImageData;
    if (compressed == null) {
      return null;
    }

    if (_compressedImageCache.containsKey(compressed)) {
      return _compressedImageCache[compressed];
    }

    final rasterized = rasterizeCompressedImageData(compressed);
    _compressedImageCache[compressed] = rasterized;
    return rasterized;
  }

  /// On-demand rasterises a [LoveCanvasSnapshot] and caches the result.
  LoveColor? _sampleCanvasSnapshot(
    LoveCanvasSnapshot snapshot,
    double x,
    double y,
  ) {
    var cached = _snapshotCache[snapshot];
    if (cached == null) {
      cached = snapshot.rasterizedImageData();
      _snapshotCache[snapshot] = cached;
    }
    final ix = x.floor().clamp(0, cached.width - 1);
    final iy = y.floor().clamp(0, cached.height - 1);
    return cached.getPixel(ix, iy);
  }

  // --------------------------------------------------------------------------
  // Triangle rasterisation (for Mesh)
  // --------------------------------------------------------------------------

  void _rasterTriangle(
    LoveMeshCommand cmd,
    Matrix4 fullTx,
    LoveMeshVertex a,
    LoveMeshVertex b,
    LoveMeshVertex c,
  ) {
    final textureImage = _resolvedMeshTextureImage(cmd.mesh);
    final pa = _mapPt(fullTx, a.x, a.y);
    final pb = _mapPt(fullTx, b.x, b.y);
    final pc = _mapPt(fullTx, c.x, c.y);
    if (_meshTriangleIsCulled(cmd, pa, pb, pc)) {
      return;
    }

    final mnX = math.max(math.min(pa.x, math.min(pb.x, pc.x)).floor(), 0);
    final mnY = math.max(math.min(pa.y, math.min(pb.y, pc.y)).floor(), 0);
    final mxX = math.min(
      math.max(pa.x, math.max(pb.x, pc.x)).ceil(),
      pixelWidth - 1,
    );
    final mxY = math.min(
      math.max(pa.y, math.max(pb.y, pc.y)).ceil(),
      pixelHeight - 1,
    );

    for (var py = mnY; py <= mxY; py++) {
      for (var px = mnX; px <= mxX; px++) {
        final bary = _baryCoords(
          px + 0.5,
          py + 0.5,
          pa.x,
          pa.y,
          pb.x,
          pb.y,
          pc.x,
          pc.y,
        );
        if (bary == null) continue;
        final (u, v, w) = bary;
        var color = LoveColor(
          cmd.color.r * (u * a.color.r + v * b.color.r + w * c.color.r),
          cmd.color.g * (u * a.color.g + v * b.color.g + w * c.color.g),
          cmd.color.b * (u * a.color.b + v * b.color.b + w * c.color.b),
          cmd.color.a * (u * a.color.a + v * b.color.a + w * c.color.a),
        );
        if (textureImage != null) {
          final textureU = (u * a.u) + (v * b.u) + (w * c.u);
          final textureV = (u * a.v) + (v * b.v) + (w * c.v);
          final sampled = _sampleImage(
            textureImage,
            textureU * textureImage.width,
            textureV * textureImage.height,
          );
          if (sampled != null) {
            color = color.modulate(sampled);
          }
        }
        _putPixel(cmd, px, py, color);
      }
    }
  }

  LoveImage? _resolvedMeshTextureImage(LoveMesh mesh) {
    return switch (mesh.textureObject) {
      final LoveCanvas canvas => canvas.snapshot(),
      final LoveImage image => image,
      _ => null,
    };
  }

  bool _meshTriangleIsCulled(
    LoveMeshCommand cmd,
    ({double x, double y}) a,
    ({double x, double y}) b,
    ({double x, double y}) c,
  ) {
    if (cmd.cullMode == LoveGraphicsCullMode.none) {
      return false;
    }

    final signedArea =
        ((b.x - a.x) * (c.y - a.y)) - ((b.y - a.y) * (c.x - a.x));
    if (signedArea.abs() < 1e-10) {
      return true;
    }

    // LOVE flips the effective front face winding when rendering to a Canvas.
    final effectiveWinding = switch (cmd.frontFaceWinding) {
      LoveGraphicsVertexWinding.ccw => LoveGraphicsVertexWinding.cw,
      LoveGraphicsVertexWinding.cw => LoveGraphicsVertexWinding.ccw,
    };
    final isFrontFacing = switch (effectiveWinding) {
      LoveGraphicsVertexWinding.ccw => signedArea < 0,
      LoveGraphicsVertexWinding.cw => signedArea > 0,
    };

    return switch (cmd.cullMode) {
      LoveGraphicsCullMode.none => false,
      LoveGraphicsCullMode.front => isFrontFacing,
      LoveGraphicsCullMode.back => !isFrontFacing,
    };
  }

  /// Barycentric coordinates for point (px,py) in triangle (ax,ay)-(bx,by)-(cx,cy).
  /// Returns null if the point is outside the triangle.
  (double, double, double)? _baryCoords(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
  ) {
    final denom = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy);
    if (denom.abs() < 1e-10) return null;
    final u = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / denom;
    final v = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / denom;
    final w = 1.0 - u - v;
    if (u < 0 || v < 0 || w < 0) return null;
    return (u, v, w);
  }

  // --------------------------------------------------------------------------
  // Filled shape primitives
  // --------------------------------------------------------------------------

  /// Scan-line fill for an arbitrary (possibly non-convex) polygon.
  void _fillPolygon(
    LoveDrawCommand cmd,
    List<({double x, double y})> verts,
    LoveColor color,
  ) {
    if (verts.length < 3) return;

    var mnY = double.infinity;
    var mxY = double.negativeInfinity;
    for (final v in verts) {
      if (v.y < mnY) mnY = v.y;
      if (v.y > mxY) mxY = v.y;
    }

    final iy0 = math.max(mnY.floor(), 0);
    final iy1 = math.min(mxY.ceil(), pixelHeight - 1);
    final n = verts.length;

    for (var py = iy0; py <= iy1; py++) {
      final fy = py + 0.5;
      final xCrossings = <double>[];

      for (var i = 0; i < n; i++) {
        final v0 = verts[i];
        final v1 = verts[(i + 1) % n];
        if ((v0.y <= fy && v1.y > fy) || (v1.y <= fy && v0.y > fy)) {
          final t = (fy - v0.y) / (v1.y - v0.y);
          xCrossings.add(v0.x + t * (v1.x - v0.x));
        }
      }

      xCrossings.sort();

      for (var i = 0; i + 1 < xCrossings.length; i += 2) {
        final x0 = math.max(xCrossings[i].floor(), 0);
        final x1 = math.min(xCrossings[i + 1].floor(), pixelWidth - 1);
        for (var px = x0; px <= x1; px++) {
          _putPixel(cmd, px, py, color);
        }
      }
    }
  }

  void _rasterWireframeTriangle(
    LoveMeshCommand cmd,
    Matrix4 fullTx,
    LoveImage? textureImage,
    LoveMeshVertex a,
    LoveMeshVertex b,
    LoveMeshVertex c,
  ) {
    final pa = _mapPt(fullTx, a.x, a.y);
    final pb = _mapPt(fullTx, b.x, b.y);
    final pc = _mapPt(fullTx, c.x, c.y);
    if (_meshTriangleIsCulled(cmd, pa, pb, pc)) {
      return;
    }

    _rasterMeshEdge(cmd, textureImage, pa, pb, a, b);
    _rasterMeshEdge(cmd, textureImage, pb, pc, b, c);
    _rasterMeshEdge(cmd, textureImage, pc, pa, c, a);
  }

  void _rasterMeshEdge(
    LoveMeshCommand cmd,
    LoveImage? textureImage,
    ({double x, double y}) p0,
    ({double x, double y}) p1,
    LoveMeshVertex a,
    LoveMeshVertex b,
  ) {
    final dx = p1.x - p0.x;
    final dy = p1.y - p0.y;
    final lengthSquared = (dx * dx) + (dy * dy);
    if (lengthSquared < 1e-10) {
      var color = _modulateVertexColorForMesh(cmd, a);
      if (textureImage != null) {
        final sampled = _sampleImage(
          textureImage,
          a.u * textureImage.width,
          a.v * textureImage.height,
        );
        if (sampled != null) {
          color = color.modulate(sampled);
        }
      }
      _putPixel(cmd, p0.x.round(), p0.y.round(), color);
      return;
    }

    final halfWidth = math.max(0.5, cmd.lineWidth * 0.5);
    final minX = math.max(0, (math.min(p0.x, p1.x) - halfWidth).floor());
    final maxX = math.min(
      pixelWidth - 1,
      (math.max(p0.x, p1.x) + halfWidth).ceil(),
    );
    final minY = math.max(0, (math.min(p0.y, p1.y) - halfWidth).floor());
    final maxY = math.min(
      pixelHeight - 1,
      (math.max(p0.y, p1.y) + halfWidth).ceil(),
    );

    for (var py = minY; py <= maxY; py++) {
      final centerY = py + 0.5;
      for (var px = minX; px <= maxX; px++) {
        final centerX = px + 0.5;
        final projection =
            (((centerX - p0.x) * dx) + ((centerY - p0.y) * dy)) / lengthSquared;
        final t = projection.clamp(0.0, 1.0);
        final closestX = p0.x + (dx * t);
        final closestY = p0.y + (dy * t);
        final distX = centerX - closestX;
        final distY = centerY - closestY;
        if ((distX * distX) + (distY * distY) > (halfWidth * halfWidth)) {
          continue;
        }

        var color = LoveColor(
          cmd.color.r * _lerpDouble(a.color.r, b.color.r, t),
          cmd.color.g * _lerpDouble(a.color.g, b.color.g, t),
          cmd.color.b * _lerpDouble(a.color.b, b.color.b, t),
          cmd.color.a * _lerpDouble(a.color.a, b.color.a, t),
        );
        if (textureImage != null) {
          final sampled = _sampleImage(
            textureImage,
            _lerpDouble(a.u, b.u, t) * textureImage.width,
            _lerpDouble(a.v, b.v, t) * textureImage.height,
          );
          if (sampled != null) {
            color = color.modulate(sampled);
          }
        }
        _putPixel(cmd, px, py, color);
      }
    }
  }

  void _rasterMeshPoint(
    LoveMeshCommand cmd,
    Matrix4 fullTx,
    LoveImage? textureImage,
    LoveMeshVertex vertex,
  ) {
    final point = _mapPt(fullTx, vertex.x, vertex.y);
    var color = _modulateVertexColorForMesh(cmd, vertex);
    if (textureImage != null) {
      final sampled = _sampleImage(
        textureImage,
        vertex.u * textureImage.width,
        vertex.v * textureImage.height,
      );
      if (sampled != null) {
        color = color.modulate(sampled);
      }
    }

    final half = cmd.pointSize * 0.5;
    final x0 = (point.x - half).floor();
    final y0 = (point.y - half).floor();
    final x1 = (point.x + half).ceil() - 1;
    final y1 = (point.y + half).ceil() - 1;
    for (var py = y0; py <= y1; py++) {
      for (var px = x0; px <= x1; px++) {
        _writeFragment(cmd, px, py, color);
      }
    }
  }

  LoveColor _modulateVertexColorForMesh(
    LoveMeshCommand cmd,
    LoveMeshVertex vertex,
  ) {
    return LoveColor(
      cmd.color.r * vertex.color.r,
      cmd.color.g * vertex.color.g,
      cmd.color.b * vertex.color.b,
      cmd.color.a * vertex.color.a,
    );
  }

  double _lerpDouble(double a, double b, double t) => a + ((b - a) * t);

  void _fillAARect(
    LoveDrawCommand cmd,
    int x0,
    int y0,
    int x1,
    int y1,
    LoveColor color,
  ) {
    final sx = math.max(x0, 0);
    final sy = math.max(y0, 0);
    final ex = math.min(x1, pixelWidth - 1);
    final ey = math.min(y1, pixelHeight - 1);
    for (var py = sy; py <= ey; py++) {
      for (var px = sx; px <= ex; px++) {
        _putPixel(cmd, px, py, color);
      }
    }
  }

  void _fillCircle(
    LoveDrawCommand cmd,
    double cx,
    double cy,
    double r,
    LoveColor color,
  ) {
    final x0 = math.max((cx - r).floor(), 0);
    final y0 = math.max((cy - r).floor(), 0);
    final x1 = math.min((cx + r).ceil(), pixelWidth - 1);
    final y1 = math.min((cy + r).ceil(), pixelHeight - 1);
    final r2 = r * r;
    for (var py = y0; py <= y1; py++) {
      for (var px = x0; px <= x1; px++) {
        final dx = px + 0.5 - cx;
        final dy = py + 0.5 - cy;
        if (dx * dx + dy * dy <= r2) _putPixel(cmd, px, py, color);
      }
    }
  }

  void _fillEllipse(
    LoveDrawCommand cmd,
    double cx,
    double cy,
    double rx,
    double ry,
    LoveColor color,
  ) {
    if (rx <= 0 || ry <= 0) return;
    final x0 = math.max((cx - rx).floor(), 0);
    final y0 = math.max((cy - ry).floor(), 0);
    final x1 = math.min((cx + rx).ceil(), pixelWidth - 1);
    final y1 = math.min((cy + ry).ceil(), pixelHeight - 1);
    for (var py = y0; py <= y1; py++) {
      for (var px = x0; px <= x1; px++) {
        final dx = (px + 0.5 - cx) / rx;
        final dy = (py + 0.5 - cy) / ry;
        if (dx * dx + dy * dy <= 1.0) _putPixel(cmd, px, py, color);
      }
    }
  }

  /// Polygon-based filled arc – generates a polygon approximation and fills it.
  void _fillArcPoly(
    LoveDrawCommand cmd,
    double cx,
    double cy,
    double r,
    double a1,
    double a2,
    LoveGraphicsArcMode arcMode,
    LoveColor color,
  ) {
    final pts = _arcPoints(cx, cy, r, a1, a2);
    switch (arcMode) {
      case LoveGraphicsArcMode.open:
      case LoveGraphicsArcMode.closed:
        // Fill with a chord (straight line between endpoints).
        _fillPolygon(cmd, pts, color);
      case LoveGraphicsArcMode.pie:
        // Pie wedge: include the centre point.
        _fillPolygon(cmd, [(x: cx, y: cy), ...pts], color);
    }
  }

  // --------------------------------------------------------------------------
  // Stroke primitives
  // --------------------------------------------------------------------------

  void _strokeRing(
    LoveDrawCommand cmd,
    double cx,
    double cy,
    double r,
    LoveColor color,
  ) {
    final hw = math.max(0.5, cmd.lineWidth * 0.5);
    final ro2 = (r + hw) * (r + hw);
    final ri = math.max(0.0, r - hw);
    final ri2 = ri * ri;

    final x0 = math.max((cx - r - hw).floor(), 0);
    final y0 = math.max((cy - r - hw).floor(), 0);
    final x1 = math.min((cx + r + hw).ceil(), pixelWidth - 1);
    final y1 = math.min((cy + r + hw).ceil(), pixelHeight - 1);

    for (var py = y0; py <= y1; py++) {
      for (var px = x0; px <= x1; px++) {
        final dx = px + 0.5 - cx;
        final dy = py + 0.5 - cy;
        final d2 = dx * dx + dy * dy;
        if (d2 >= ri2 && d2 <= ro2) _putPixel(cmd, px, py, color);
      }
    }
  }

  void _strokeEllipseBand(
    LoveDrawCommand cmd,
    double cx,
    double cy,
    double rx,
    double ry,
    LoveColor color,
  ) {
    if (rx <= 0 || ry <= 0) return;
    final hw = math.max(0.5, cmd.lineWidth * 0.5);
    final rxO = rx + hw;
    final ryO = ry + hw;
    final rxI = math.max(0.0, rx - hw);
    final ryI = math.max(0.0, ry - hw);

    final x0 = math.max((cx - rxO).floor(), 0);
    final y0 = math.max((cy - ryO).floor(), 0);
    final x1 = math.min((cx + rxO).ceil(), pixelWidth - 1);
    final y1 = math.min((cy + ryO).ceil(), pixelHeight - 1);

    for (var py = y0; py <= y1; py++) {
      for (var px = x0; px <= x1; px++) {
        final dx = px + 0.5 - cx;
        final dy = py + 0.5 - cy;
        final outerD = (dx / rxO) * (dx / rxO) + (dy / ryO) * (dy / ryO);
        final innerD = (rxI > 0 && ryI > 0)
            ? (dx / rxI) * (dx / rxI) + (dy / ryI) * (dy / ryI)
            : 2.0;
        if (outerD <= 1.0 && innerD >= 1.0) _putPixel(cmd, px, py, color);
      }
    }
  }

  void _strokeArcPath(
    LoveDrawCommand cmd,
    double cx,
    double cy,
    double r,
    double a1,
    double a2,
    LoveGraphicsArcMode arcMode,
    LoveColor color,
  ) {
    final pts = _arcPoints(cx, cy, r, a1, a2);
    _strokePolyline(cmd, pts, color, closed: false);

    switch (arcMode) {
      case LoveGraphicsArcMode.open:
        break;
      case LoveGraphicsArcMode.closed:
        _thickLine(
          cmd,
          pts.first.x,
          pts.first.y,
          pts.last.x,
          pts.last.y,
          color,
        );
      case LoveGraphicsArcMode.pie:
        _thickLine(cmd, cx, cy, pts.first.x, pts.first.y, color);
        _thickLine(cmd, cx, cy, pts.last.x, pts.last.y, color);
    }
  }

  void _strokePolyline(
    LoveDrawCommand cmd,
    List<({double x, double y})> pts,
    LoveColor color, {
    required bool closed,
  }) {
    if (pts.length < 2) return;
    final n = closed ? pts.length : pts.length - 1;
    for (var i = 0; i < n; i++) {
      final p0 = pts[i];
      final p1 = pts[(i + 1) % pts.length];
      _thickLine(cmd, p0.x, p0.y, p1.x, p1.y, color);
    }
  }

  /// Draws a thick line as a filled quad.
  void _thickLine(
    LoveDrawCommand cmd,
    double x0,
    double y0,
    double x1,
    double y1,
    LoveColor color,
  ) {
    final dx = x1 - x0;
    final dy = y1 - y0;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
      _putPixel(cmd, x0.round(), y0.round(), color);
      return;
    }

    final hw = math.max(0.5, cmd.lineWidth * 0.5);
    final nx = (-dy / len) * hw;
    final ny = (dx / len) * hw;

    _fillPolygon(cmd, [
      (x: x0 + nx, y: y0 + ny),
      (x: x1 + nx, y: y1 + ny),
      (x: x1 - nx, y: y1 - ny),
      (x: x0 - nx, y: y0 - ny),
    ], color);
  }

  // --------------------------------------------------------------------------
  // Arc point list helper
  // --------------------------------------------------------------------------

  List<({double x, double y})> _arcPoints(
    double cx,
    double cy,
    double r,
    double a1,
    double a2,
  ) {
    var sweep = a2 - a1;
    // Clamp to a full circle at most.
    if (sweep.abs() > 2 * math.pi) sweep = sweep.sign * 2 * math.pi;

    final steps = math.max(8, (r.abs() * sweep.abs() * 2).ceil());
    final pts = <({double x, double y})>[];
    for (var i = 0; i <= steps; i++) {
      final angle = a1 + sweep * i / steps;
      pts.add((x: cx + math.cos(angle) * r, y: cy + math.sin(angle) * r));
    }
    return pts;
  }

  // --------------------------------------------------------------------------
  // Rounded rectangle polygon approximation
  // --------------------------------------------------------------------------

  List<({double x, double y})> _roundedRectPts(LoveRectangleCommand cmd) {
    final rx = cmd.cornerRadiusX;
    final ry = cmd.cornerRadiusY;
    const steps = 6; // arc segments per corner

    List<({double x, double y})> cornerArc(
      double cx,
      double cy,
      double startAngle,
    ) {
      final pts = <({double x, double y})>[];
      for (var i = 0; i <= steps; i++) {
        final a = startAngle + (math.pi / 2) * i / steps;
        pts.add((x: cx + math.cos(a) * rx, y: cy + math.sin(a) * ry));
      }
      return pts;
    }

    final l = cmd.x + rx;
    final t = cmd.y + ry;
    final r = cmd.x + cmd.width - rx;
    final b = cmd.y + cmd.height - ry;

    final pts = <({double x, double y})>[
      ...cornerArc(r, t, -math.pi / 2), // top-right
      ...cornerArc(r, b, 0), // bottom-right
      ...cornerArc(l, b, math.pi / 2), // bottom-left
      ...cornerArc(l, t, math.pi), // top-left
    ];

    return _mapPoints(cmd.transform, pts);
  }

  // --------------------------------------------------------------------------
  // Pixel write
  // --------------------------------------------------------------------------

  void _putPixel(LoveDrawCommand cmd, int px, int py, LoveColor color) {
    _writeFragment(cmd, px, py, color);
  }

  void _writeFragment(LoveDrawCommand cmd, int px, int py, LoveColor src) {
    if (!_passesStencilTest(cmd, px, py)) {
      return;
    }

    if (cmd.stencilAction case final action?) {
      _applyStencilAction(px, py, action, cmd.stencilWriteValue);
    }

    if (!cmd.colorMask.noneEnabled) {
      final shaded = _applyShaderToFragment(cmd, px, py, src);
      _rawWrite(
        px,
        py,
        shaded,
        cmd.blendMode,
        cmd.blendAlphaMode,
        cmd.colorMask,
        cmd.scissor,
      );
    }
  }

  bool _passesStencilTest(LoveDrawCommand cmd, int px, int py) {
    if (px < 0 || px >= pixelWidth || py < 0 || py >= pixelHeight) {
      return false;
    }

    final stencilValue = _stencil[(py * pixelWidth) + px];
    final compareValue = cmd.stencilValue;
    return switch (cmd.stencilCompare) {
      LoveGraphicsCompareMode.equal => stencilValue == compareValue,
      LoveGraphicsCompareMode.notequal => stencilValue != compareValue,
      LoveGraphicsCompareMode.less => stencilValue < compareValue,
      LoveGraphicsCompareMode.lequal => stencilValue <= compareValue,
      LoveGraphicsCompareMode.gequal => stencilValue >= compareValue,
      LoveGraphicsCompareMode.greater => stencilValue > compareValue,
      LoveGraphicsCompareMode.never => false,
      LoveGraphicsCompareMode.always => true,
    };
  }

  void _applyStencilAction(
    int px,
    int py,
    LoveGraphicsStencilAction action,
    int value,
  ) {
    if (px < 0 || px >= pixelWidth || py < 0 || py >= pixelHeight) {
      return;
    }

    final index = (py * pixelWidth) + px;
    final current = _stencil[index];
    _stencil[index] = switch (action) {
      LoveGraphicsStencilAction.replace => _clampStencilValue(value),
      LoveGraphicsStencilAction.increment => math.min(255, current + 1),
      LoveGraphicsStencilAction.decrement => math.max(0, current - 1),
      LoveGraphicsStencilAction.incrementWrap => (current + 1) & 0xff,
      LoveGraphicsStencilAction.decrementWrap => (current - 1) & 0xff,
      LoveGraphicsStencilAction.invert => current ^ 0xff,
    };
  }

  int _clampStencilValue(int value) => value.clamp(0, 255);

  LoveColor _applyShaderToFragment(
    LoveDrawCommand cmd,
    int px,
    int py,
    LoveColor src,
  ) {
    final shader = cmd.shader;
    if (shader == null) {
      return src;
    }

    return switch (shader.kind) {
      LoveShaderKind.desaturationTint =>
        loveShaderDesaturationTintColor(shader, src) ?? src,
      LoveShaderKind.radialGradient => _applyRadialGradientToFragment(
        cmd,
        shader,
        px,
        py,
        src,
      ),
      _ => src,
    };
  }

  LoveColor _applyRadialGradientToFragment(
    LoveDrawCommand cmd,
    LoveShader shader,
    int px,
    int py,
    LoveColor src,
  ) {
    final gradientColor = loveShaderRadialGradientColorAt(
      shader,
      fallbackColor: cmd.color,
      x: px + originX + 0.5,
      y: py + originY + 0.5,
    );
    if (gradientColor == null) {
      return src;
    }

    if (_usesImageRadialGradientPath(cmd)) {
      return src.modulate(gradientColor);
    }
    if (_usesRasterizedRadialGradientPath(cmd)) {
      return gradientColor;
    }
    return src;
  }

  bool _usesRasterizedRadialGradientPath(LoveDrawCommand cmd) {
    return switch (cmd) {
      LoveRectangleCommand() ||
      LoveCircleCommand() ||
      LovePolygonCommand() ||
      LoveEllipseCommand() ||
      LoveArcCommand() ||
      LoveLineCommand() ||
      LovePointsCommand() ||
      LoveTextCommand() ||
      LoveTextObjectCommand() => true,
      final LoveMeshCommand mesh => !_meshUsesImageRadialGradientPath(mesh),
      _ => false,
    };
  }

  bool _usesImageRadialGradientPath(LoveDrawCommand cmd) {
    return switch (cmd) {
      LoveImageCommand() ||
      LoveSpriteBatchCommand() ||
      LoveParticleSystemCommand() => true,
      final LoveMeshCommand mesh => _meshUsesImageRadialGradientPath(mesh),
      _ => false,
    };
  }

  bool _meshUsesImageRadialGradientPath(LoveMeshCommand mesh) {
    return _resolvedMeshTextureImage(mesh.mesh) != null;
  }

  void _applyStencilClear(int value, LoveScissorRect? clearScissor) {
    final left = clearScissor == null
        ? 0
        : math.max(0, clearScissor.x.floor() - originX);
    final top = clearScissor == null
        ? 0
        : math.max(0, clearScissor.y.floor() - originY);
    final right = clearScissor == null
        ? pixelWidth
        : math.min(
            pixelWidth,
            (clearScissor.x + clearScissor.width).ceil() - originX,
          );
    final bottom = clearScissor == null
        ? pixelHeight
        : math.min(
            pixelHeight,
            (clearScissor.y + clearScissor.height).ceil() - originY,
          );

    if (left >= right || top >= bottom) {
      return;
    }

    final clampedValue = _clampStencilValue(value);
    for (var py = top; py < bottom; py++) {
      for (var px = left; px < right; px++) {
        _stencil[(py * pixelWidth) + px] = clampedValue;
      }
    }
  }

  void _rawWrite(
    int px,
    int py,
    LoveColor src,
    LoveGraphicsBlendMode blendMode,
    LoveGraphicsBlendAlphaMode alphaMode,
    LoveGraphicsColorMask mask,
    LoveScissorRect? scissor,
  ) {
    if (px < 0 || px >= pixelWidth || py < 0 || py >= pixelHeight) return;
    final globalPx = px + originX;
    final globalPy = py + originY;
    if (scissor != null &&
        (globalPx < scissor.x ||
            globalPx >= scissor.x + scissor.width ||
            globalPy < scissor.y ||
            globalPy >= scissor.y + scissor.height)) {
      return;
    }

    final dst = _data.getPixel(px, py);
    final blended = _blend(src, dst, blendMode, alphaMode);
    _data.setPixel(
      px,
      py,
      LoveColor(
        mask.red ? blended.r : dst.r,
        mask.green ? blended.g : dst.g,
        mask.blue ? blended.b : dst.b,
        mask.alpha ? blended.a : dst.a,
      ).clamped(),
    );
  }

  // --------------------------------------------------------------------------
  // Blending
  // --------------------------------------------------------------------------

  LoveColor _blend(
    LoveColor src,
    LoveColor dst,
    LoveGraphicsBlendMode mode,
    LoveGraphicsBlendAlphaMode alphaMode,
  ) {
    // For the standard (multiplicative / 'alphamultiply') alpha mode, LOVE
    // pre-multiplies the RGB by alpha before blending.  In 'premultiplied'
    // mode the source is already pre-multiplied.
    final LoveColor s;
    if (alphaMode == LoveGraphicsBlendAlphaMode.premultiplied) {
      s = src;
    } else {
      s = LoveColor(src.r * src.a, src.g * src.a, src.b * src.a, src.a);
    }

    return switch (mode) {
      LoveGraphicsBlendMode.alpha => _alphaOver(s, dst),
      LoveGraphicsBlendMode.replace => s,
      LoveGraphicsBlendMode.none => src,
      LoveGraphicsBlendMode.add => LoveColor(
        dst.r + s.r,
        dst.g + s.g,
        dst.b + s.b,
        dst.a,
      ),
      LoveGraphicsBlendMode.subtract => LoveColor(
        dst.r - s.r,
        dst.g - s.g,
        dst.b - s.b,
        dst.a,
      ),
      LoveGraphicsBlendMode.multiply => LoveColor(
        dst.r * src.r,
        dst.g * src.g,
        dst.b * src.b,
        dst.a * src.a,
      ),
      LoveGraphicsBlendMode.screen => LoveColor(
        dst.r * (1 - src.r) + s.r,
        dst.g * (1 - src.g) + s.g,
        dst.b * (1 - src.b) + s.b,
        dst.a * (1 - src.a) + src.a,
      ),
      LoveGraphicsBlendMode.lighten => LoveColor(
        math.max(dst.r, s.r),
        math.max(dst.g, s.g),
        math.max(dst.b, s.b),
        math.max(dst.a, s.a),
      ),
      LoveGraphicsBlendMode.darken => LoveColor(
        math.min(dst.r, s.r),
        math.min(dst.g, s.g),
        math.min(dst.b, s.b),
        math.min(dst.a, s.a),
      ),
    };
  }

  /// Porter-Duff 'source-over' with pre-multiplied source.
  LoveColor _alphaOver(LoveColor sPremult, LoveColor dst) {
    final inv = 1.0 - sPremult.a;
    return LoveColor(
      sPremult.r + dst.r * inv,
      sPremult.g + dst.g * inv,
      sPremult.b + dst.b * inv,
      sPremult.a + dst.a * inv,
    );
  }

  // --------------------------------------------------------------------------
  // Transform helpers
  // --------------------------------------------------------------------------

  ({double x, double y}) _mapPt(Matrix4 m, double lx, double ly) {
    final v = m.transformed3(Vector3(lx, ly, 0));
    return (x: v.x - originX, y: v.y - originY);
  }

  List<({double x, double y})> _mapPoints(
    Matrix4 m,
    List<({double x, double y})> pts,
  ) => pts.map((p) => _mapPt(m, p.x, p.y)).toList(growable: false);

  /// Approximate X-axis scale factor of [m].
  double _scaleX(Matrix4 m) {
    final o = m.transformed3(Vector3(0, 0, 0));
    final s = m.transformed3(Vector3(1, 0, 0));
    final dx = s.x - o.x;
    final dy = s.y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Approximate Y-axis scale factor of [m].
  double _scaleY(Matrix4 m) {
    final o = m.transformed3(Vector3(0, 0, 0));
    final s = m.transformed3(Vector3(0, 1, 0));
    final dx = s.x - o.x;
    final dy = s.y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}
