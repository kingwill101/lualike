import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'gpu_api_compat.dart';
import 'gpu_draw_state.dart';
import 'gpu_host_buffer_pool.dart';
import 'gpu_pipeline_cache.dart';

const int _kCircleSegments = 48;
const double _kEpsilon = 1e-6;
final List<({double cos, double sin})> _kCircleUnitPoints =
    List<({double cos, double sin})>.unmodifiable(
      List<({double cos, double sin})>.generate(_kCircleSegments + 1, (index) {
        final angle = 2.0 * math.pi * index / _kCircleSegments;
        return (cos: math.cos(angle), sin: math.sin(angle));
      }, growable: false),
    );

class GpuShapeHandler {
  GpuShapeHandler({
    required GpuPipelineCache pipelineCache,
    required GpuHostBufferPool hostBufferPool,
  }) : _pipelineCache = pipelineCache,
       _hostBufferPool = hostBufferPool;

  final GpuPipelineCache _pipelineCache;
  final GpuHostBufferPool _hostBufferPool;

  bool renderRectangle(
    gpu.RenderPass pass,
    LoveRectangleCommand cmd,
    ui.Size viewportSize,
  ) {
    final isLine = cmd.mode == LoveGraphicsDrawMode.line;
    final vertices = _rectangleVertices(
      cmd.x,
      cmd.y,
      cmd.width,
      cmd.height,
      cmd.cornerRadiusX,
      cmd.cornerRadiusY,
      isLine: isLine,
      lineWidth: isLine ? cmd.lineWidth : 0,
    );
    if (vertices.isEmpty) return false;
    final transform = vm.Matrix4.fromList(cmd.transform.storage.toList());
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
    return true;
  }

  bool renderCircle(
    gpu.RenderPass pass,
    LoveCircleCommand cmd,
    ui.Size viewportSize,
  ) {
    final isLine = cmd.mode == LoveGraphicsDrawMode.line;
    final vertices = _ellipseVertices(
      cmd.x,
      cmd.y,
      cmd.radius,
      cmd.radius,
      isLine: isLine,
      lineWidth: isLine ? cmd.lineWidth : 0,
    );
    if (vertices.isEmpty) return false;
    final transform = vm.Matrix4.fromList(cmd.transform.storage.toList());
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
    return true;
  }

  bool renderEllipse(
    gpu.RenderPass pass,
    LoveEllipseCommand cmd,
    ui.Size viewportSize,
  ) {
    final isLine = cmd.mode == LoveGraphicsDrawMode.line;
    final vertices = _ellipseVertices(
      cmd.x,
      cmd.y,
      cmd.radiusX,
      cmd.radiusY,
      isLine: isLine,
      lineWidth: isLine ? cmd.lineWidth : 0,
    );
    if (vertices.isEmpty) return false;
    final transform = vm.Matrix4.fromList(cmd.transform.storage.toList());
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
    return true;
  }

  bool renderLine(
    gpu.RenderPass pass,
    LoveLineCommand cmd,
    ui.Size viewportSize,
  ) {
    final pts = cmd.points;
    if (pts.length < 2) return false;
    final vertices = _lineVertices(pts, cmd.lineWidth);
    if (vertices.isEmpty) return false;
    final transform = vm.Matrix4.fromList(cmd.transform.storage.toList());
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
    return true;
  }

  bool renderPolygon(
    gpu.RenderPass pass,
    LovePolygonCommand cmd,
    ui.Size viewportSize,
  ) {
    final pts = cmd.points;
    if (pts.length < 3) return false;
    final isLine = cmd.mode == LoveGraphicsDrawMode.line;
    final vertices = _polygonVertices(
      pts,
      isLine: isLine,
      lineWidth: isLine ? cmd.lineWidth : 0,
    );
    if (vertices.isEmpty) return false;
    final transform = vm.Matrix4.fromList(cmd.transform.storage.toList());
    _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
    return true;
  }

  bool renderArc(
    gpu.RenderPass pass,
    LoveArcCommand cmd,
    ui.Size viewportSize,
  ) {
    final pts = _arcPoints(cmd.x, cmd.y, cmd.radius, cmd.angle1, cmd.angle2);
    if (pts.length < 2) return false;
    final isLine = cmd.drawMode == LoveGraphicsDrawMode.line;
    final transform = vm.Matrix4.fromList(cmd.transform.storage.toList());

    if (isLine) {
      // Line mode — use outline-to-quads for the arc path
      List<({double x, double y})> outlinePts;
      switch (cmd.arcMode) {
        case LoveGraphicsArcMode.open:
          outlinePts = pts;
        case LoveGraphicsArcMode.closed:
          outlinePts = [...pts, pts.first];
        case LoveGraphicsArcMode.pie:
          outlinePts = [(x: cmd.x, y: cmd.y), ...pts, (x: cmd.x, y: cmd.y)];
      }
      final vertices = _outlineToQuads(outlinePts, cmd.lineWidth);
      if (vertices.isEmpty) return false;
      applyGpuDrawState(pass, cmd, viewportSize);
      _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
      return true;
    }

    // Fill mode — triangle fan
    switch (cmd.arcMode) {
      case LoveGraphicsArcMode.open:
        // Open arc has no interior, draw as thin line
        final vertices = _outlineToQuads(pts, cmd.lineWidth);
        if (vertices.isEmpty) return false;
        applyGpuDrawState(pass, cmd, viewportSize);
        _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
        return true;
      case LoveGraphicsArcMode.closed:
        // Closed arc: fan from first point
        {
          final vertices = Float32List((pts.length - 1) * 3 * 8);
          var offset = 0;
          void write(double vx, double vy) {
            vertices[offset++] = vx;
            vertices[offset++] = vy;
            vertices[offset++] = 0;
            vertices[offset++] = 0;
            vertices[offset++] = 1;
            vertices[offset++] = 1;
            vertices[offset++] = 1;
            vertices[offset++] = 1;
          }

          for (var i = 1; i < pts.length; i++) {
            write(pts[0].x, pts[0].y);
            write(pts[i].x, pts[i].y);
            write(pts[(i + 1) % pts.length].x, pts[(i + 1) % pts.length].y);
          }
          applyGpuDrawState(pass, cmd, viewportSize);
          _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
          return true;
        }
      case LoveGraphicsArcMode.pie:
        // Pie: fan from center
        {
          final vertices = Float32List((pts.length - 1) * 3 * 8);
          var offset = 0;
          void write(double vx, double vy) {
            vertices[offset++] = vx;
            vertices[offset++] = vy;
            vertices[offset++] = 0;
            vertices[offset++] = 0;
            vertices[offset++] = 1;
            vertices[offset++] = 1;
            vertices[offset++] = 1;
            vertices[offset++] = 1;
          }

          for (var i = 1; i < pts.length; i++) {
            write(cmd.x, cmd.y);
            write(pts[i - 1].x, pts[i - 1].y);
            write(pts[i].x, pts[i].y);
          }
          applyGpuDrawState(pass, cmd, viewportSize);
          _drawVertices(pass, vertices, transform, viewportSize, cmd.color);
          return true;
        }
    }
  }

  List<({double x, double y})> _arcPoints(
    double cx,
    double cy,
    double r,
    double a1,
    double a2,
  ) {
    var sweep = a2 - a1;
    if (sweep.abs() > 2 * math.pi) sweep = sweep.sign * 2 * math.pi;
    final steps = math.max(8, (r.abs() * sweep.abs() * 2).ceil());
    final pts = <({double x, double y})>[];
    for (var i = 0; i <= steps; i++) {
      final angle = a1 + sweep * i / steps;
      pts.add((x: cx + math.cos(angle) * r, y: cy + math.sin(angle) * r));
    }
    return pts;
  }

  bool renderPoints(
    gpu.RenderPass pass,
    LovePointsCommand cmd,
    ui.Size viewportSize,
  ) {
    final pts = cmd.points;
    if (pts.isEmpty) return false;
    final r = cmd.pointSize / 2.0;
    final vertices = Float32List(pts.length * 6 * 8);
    var offset = 0;
    void write(double vx, double vy, LoveColor c) {
      vertices[offset++] = vx;
      vertices[offset++] = vy;
      vertices[offset++] = 0;
      vertices[offset++] = 0;
      vertices[offset++] = c.r;
      vertices[offset++] = c.g;
      vertices[offset++] = c.b;
      vertices[offset++] = c.a;
    }

    for (final p in pts) {
      final c = p.color ?? cmd.color;
      final cx = p.x;
      final cy = p.y;
      write(cx - r, cy - r, c);
      write(cx + r, cy - r, c);
      write(cx - r, cy + r, c);
      write(cx + r, cy + r, c);
      write(cx - r, cy + r, c);
      write(cx + r, cy - r, c);
    }
    if (vertices.isEmpty) return false;
    final transform = vm.Matrix4.fromList(cmd.transform.storage.toList());
    applyGpuDrawState(pass, cmd, viewportSize);
    final mvp = _buildMVP(transform, viewportSize);
    _drawRaw(pass, vertices, mvp, cmd.color);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Geometry generators — return a flat list of floats (8 per vertex)
  // ---------------------------------------------------------------------------

  Float32List _rectangleVertices(
    double x,
    double y,
    double w,
    double h,
    double rx,
    double ry, {
    required bool isLine,
    double lineWidth = 0,
  }) {
    if (w <= 0 || h <= 0) return Float32List(0);

    if (isLine) {
      return _outlineToQuads([
        (x: x, y: y),
        (x: x + w, y: y),
        (x: x + w, y: y + h),
        (x: x, y: y + h),
        (x: x, y: y),
      ], lineWidth);
    }

    final vertices = Float32List(6 * 8);
    var offset = 0;
    void write(double vx, double vy) {
      vertices[offset++] = vx;
      vertices[offset++] = vy;
      vertices[offset++] = 0;
      vertices[offset++] = 0;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
    }

    // Two triangles with white per-vertex color (shader multiplies by uniform)
    write(x, y);
    write(x + w, y);
    write(x, y + h);
    write(x + w, y);
    write(x + w, y + h);
    write(x, y + h);
    return vertices;
  }

  Float32List _ellipseVertices(
    double cx,
    double cy,
    double rx,
    double ry, {
    required bool isLine,
    double lineWidth = 0,
  }) {
    if (rx <= 0 || ry <= 0) return Float32List(0);
    final segments = _kCircleSegments;

    if (isLine) {
      final pts = <({double x, double y})>[];
      for (var i = 0; i <= segments; i++) {
        final unit = _kCircleUnitPoints[i];
        pts.add((x: cx + rx * unit.cos, y: cy + ry * unit.sin));
      }
      return _outlineToQuads(pts, lineWidth);
    }

    // Triangle fan from center
    final vertices = Float32List(segments * 3 * 8);
    var offset = 0;
    void write(double vx, double vy) {
      vertices[offset++] = vx;
      vertices[offset++] = vy;
      vertices[offset++] = 0;
      vertices[offset++] = 0;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
    }

    for (var i = 0; i < segments; i++) {
      final p1 = _kCircleUnitPoints[i];
      final p2 = _kCircleUnitPoints[i + 1];
      write(cx, cy);
      write(cx + rx * p1.cos, cy + ry * p1.sin);
      write(cx + rx * p2.cos, cy + ry * p2.sin);
    }
    return vertices;
  }

  Float32List _lineVertices(
    List<({double x, double y})> points,
    double lineWidth,
  ) {
    return _outlineToQuads(points, lineWidth);
  }

  Float32List _polygonVertices(
    List<({double x, double y})> points, {
    required bool isLine,
    double lineWidth = 0,
  }) {
    if (points.length < 3) return Float32List(0);
    if (isLine) {
      return _outlineToQuads([...points, points[0]], lineWidth);
    }
    // Triangle fan from first vertex (convex polygons only)
    final vertices = Float32List((points.length - 2) * 3 * 8);
    var offset = 0;
    void write(double vx, double vy) {
      vertices[offset++] = vx;
      vertices[offset++] = vy;
      vertices[offset++] = 0;
      vertices[offset++] = 0;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
    }

    for (var i = 1; i < points.length - 1; i++) {
      write(points[0].x, points[0].y);
      write(points[i].x, points[i].y);
      write(points[i + 1].x, points[i + 1].y);
    }
    return vertices;
  }

  /// Converts a polyline to thin quads (2 triangles per segment).
  Float32List _outlineToQuads(
    List<({double x, double y})> points,
    double lineWidth,
  ) {
    if (points.length < 2 || lineWidth <= 0) return Float32List(0);
    final half = lineWidth / 2.0;
    final vertices = Float32List((points.length - 1) * 6 * 8);
    var offset = 0;
    void write(double vx, double vy) {
      vertices[offset++] = vx;
      vertices[offset++] = vy;
      vertices[offset++] = 0;
      vertices[offset++] = 0;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
      vertices[offset++] = 1;
    }

    for (var i = 1; i < points.length; i++) {
      final dx = points[i].x - points[i - 1].x;
      final dy = points[i].y - points[i - 1].y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < _kEpsilon) continue;

      final nx = -dy / len * half;
      final ny = dx / len * half;

      final ax = points[i - 1].x + nx;
      final ay = points[i - 1].y + ny;
      final bx = points[i - 1].x - nx;
      final by = points[i - 1].y - ny;
      final cx = points[i].x + nx;
      final cy = points[i].y + ny;
      final dx2 = points[i].x - nx;
      final dy2 = points[i].y - ny;

      write(ax, ay);
      write(bx, by);
      write(cx, cy);
      write(bx, by);
      write(dx2, dy2);
      write(cx, cy);
    }
    return vertices;
  }

  // ---------------------------------------------------------------------------
  // Drawing helpers
  // ---------------------------------------------------------------------------

  void _drawVertices(
    gpu.RenderPass pass,
    Float32List floats,
    vm.Matrix4 transform,
    ui.Size viewportSize,
    LoveColor color,
  ) {
    final mvp = _buildMVP(transform, viewportSize);
    _drawRaw(pass, floats, mvp, color);
  }

  void _drawRaw(
    gpu.RenderPass pass,
    Float32List floats,
    vm.Matrix4 mvp,
    LoveColor color,
  ) {
    if (floats.isEmpty) return;
    if (floats.length % 8 != 0) return;

    final vertexBuffer = _hostBufferPool.emplaceFloats(floats);
    final vertexCount = floats.length ~/ 8;

    final pipeline = _pipelineCache.get(
      const PipelineKey(vertexStride: 32, isTextured: false),
    );
    pass.bindPipeline(pipeline);
    bindVertexBufferCompat(pass, vertexBuffer);

    final vcolor = vm.Vector4(color.r, color.g, color.b, color.a);
    final vertInfo = _hostBufferPool.emplaceVertInfo(mvp, vcolor);
    final vertInfoSlot = pipeline.vertexShader.getUniformSlot('VertInfo');
    pass.bindUniform(vertInfoSlot, vertInfo);

    drawVerticesCompat(pass, vertexCount);
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
