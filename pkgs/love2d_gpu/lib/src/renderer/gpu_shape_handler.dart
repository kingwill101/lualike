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
import 'gpu_stroke_tessellator.dart';

const double _kEpsilon = 1e-6;
const bool _kDefaultTypedGeneratedStrokes = bool.fromEnvironment(
  'LOVE2D_GPU_TYPED_GENERATED_STROKES',
  defaultValue: true,
);
const bool _kRuntimeStrokeTuning = bool.fromEnvironment(
  'LOVE2D_GPU_RUNTIME_STROKE_TUNING',
  defaultValue: false,
);
const bool _kRoughLinePixelSnap = bool.fromEnvironment(
  'LOVE2D_GPU_ROUGH_LINE_PIXEL_SNAP',
  defaultValue: true,
);
const bool _kRoughLineRasterization = bool.fromEnvironment(
  'LOVE2D_GPU_ROUGH_LINE_RASTERIZATION',
  defaultValue: false,
);
const bool _kRoughAxisRuns = bool.fromEnvironment(
  'LOVE2D_GPU_ROUGH_AXIS_RUNS',
  defaultValue: true,
);
const bool _kRuntimeRoughAxisRunTuning = bool.fromEnvironment(
  'LOVE2D_GPU_RUNTIME_ROUGH_AXIS_RUN_TUNING',
  defaultValue: false,
);
const bool _kSmoothLineOverdraw = bool.fromEnvironment(
  'LOVE2D_GPU_SMOOTH_LINE_OVERDRAW',
  defaultValue: true,
);
const bool _kDefaultRoughLineShader = bool.fromEnvironment(
  'LOVE2D_GPU_ROUGH_LINE_SHADER',
  defaultValue: true,
);
const bool _kRuntimeRoughLineShaderTuning = bool.fromEnvironment(
  'LOVE2D_GPU_RUNTIME_ROUGH_LINE_SHADER_TUNING',
  defaultValue: false,
);
const int _kMaxRoughLineRasterRuns = 16;
final Map<int, Float64List> _circleUnitPointCache = <int, Float64List>{};

Float64List _circleUnitPoints(int segments) {
  final cached = _circleUnitPointCache[segments];
  if (cached != null) return cached;
  if (_circleUnitPointCache.length >= 128) {
    _circleUnitPointCache.clear();
  }
  final points = Float64List((segments + 1) * 2);
  for (var index = 0; index <= segments; index++) {
    final angle = 2.0 * math.pi * index / segments;
    points[index * 2] = math.cos(angle);
    points[index * 2 + 1] = math.sin(angle);
  }
  _circleUnitPointCache[segments] = points;
  return points;
}

class GpuShapeHandler {
  GpuShapeHandler({
    required GpuPipelineCache pipelineCache,
    required GpuHostBufferPool hostBufferPool,
  }) : _pipelineCache = pipelineCache,
       _hostBufferPool = hostBufferPool;

  final GpuPipelineCache _pipelineCache;
  final GpuHostBufferPool _hostBufferPool;
  final GpuStrokeTessellator _strokeTessellator = GpuStrokeTessellator();
  final GpuRoughLineRasterizer _roughLineRasterizer = GpuRoughLineRasterizer();
  final GpuSmoothLineTessellator _smoothLineTessellator =
      GpuSmoothLineTessellator();
  final GpuRoughLineShaderGeometry _roughLineShaderGeometry =
      GpuRoughLineShaderGeometry();
  final vm.Matrix4 _identityTransform = vm.Matrix4.identity();
  int _roughX0 = 0;
  int _roughY0 = 0;
  int _roughX1 = 0;
  int _roughY1 = 0;
  bool _runtimeTypedGeneratedStrokes = _kDefaultTypedGeneratedStrokes;
  bool _runtimeRoughLineShader = _kDefaultRoughLineShader;
  bool _runtimeRoughAxisRuns = _kRoughAxisRuns;
  // Shape rendering is synchronous: _drawRaw uploads the used prefix before
  // the next command can overwrite this scratch storage. Reusing it avoids a
  // typed-list allocation for every circle, arc, rectangle, and line.
  Float32List _vertexScratch = Float32List(0);
  int _vertexScratchLength = 0;
  Float64List _pointXScratch = Float64List(0);
  Float64List _pointYScratch = Float64List(0);
  final List<({double x, double y})> _pointScratch = <({double x, double y})>[];
  final List<({double x, double y})> _pathScratch = <({double x, double y})>[];

  bool get usesTypedGeneratedStrokes => _kRuntimeStrokeTuning
      ? _runtimeTypedGeneratedStrokes
      : _kDefaultTypedGeneratedStrokes;

  bool get supportsRuntimeStrokeTuning => _kRuntimeStrokeTuning;

  bool get usesRoughLineShader => _kRuntimeRoughLineShaderTuning
      ? _runtimeRoughLineShader
      : _kDefaultRoughLineShader;

  bool get supportsRuntimeRoughLineShaderTuning =>
      _kRuntimeRoughLineShaderTuning;

  bool get usesRoughAxisRuns =>
      _kRuntimeRoughAxisRunTuning ? _runtimeRoughAxisRuns : _kRoughAxisRuns;

  bool get supportsRuntimeRoughAxisRunTuning => _kRuntimeRoughAxisRunTuning;

  void setRoughAxisRunsForDiagnostics(bool enabled) {
    if (!_kRuntimeRoughAxisRunTuning) {
      throw StateError(
        'Runtime rough-axis-run tuning requires '
        'LOVE2D_GPU_RUNTIME_ROUGH_AXIS_RUN_TUNING=true',
      );
    }
    _runtimeRoughAxisRuns = enabled;
  }

  void setRoughLineShaderForDiagnostics(bool enabled) {
    if (!_kRuntimeRoughLineShaderTuning) {
      throw StateError(
        'Runtime rough-line shader tuning requires '
        'LOVE2D_GPU_RUNTIME_ROUGH_LINE_SHADER_TUNING=true',
      );
    }
    _runtimeRoughLineShader = enabled;
  }

  void setTypedGeneratedStrokesForDiagnostics(bool enabled) {
    if (!_kRuntimeStrokeTuning) {
      throw StateError(
        'Runtime stroke tuning requires '
        'LOVE2D_GPU_RUNTIME_STROKE_TUNING=true',
      );
    }
    _runtimeTypedGeneratedStrokes = enabled;
  }

  Float32List _prepareVertices(int requiredLength) {
    if (requiredLength <= 0) {
      _vertexScratchLength = 0;
      return _vertexScratch;
    }
    if (_vertexScratch.length < requiredLength) {
      var capacity = _vertexScratch.isEmpty ? 256 : _vertexScratch.length;
      while (capacity < requiredLength) {
        capacity *= 2;
      }
      _vertexScratch = Float32List(capacity);
    }
    _vertexScratchLength = 0;
    return _vertexScratch;
  }

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
      lineJoin: cmd.lineJoin,
      pixelScale: _transformPixelScale(cmd.transform),
      pointCount: cmd.pointCount,
    );
    if (_vertexScratchLength == 0) return false;
    final transform = vm.Matrix4.copy(cmd.transform);
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(
      pass,
      vertices,
      transform,
      viewportSize,
      cmd.color,
      floatLength: _vertexScratchLength,
    );
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
      lineJoin: cmd.lineJoin,
      pixelScale: _transformPixelScale(cmd.transform),
      pointCount: cmd.pointCount,
    );
    if (_vertexScratchLength == 0) return false;
    final transform = vm.Matrix4.copy(cmd.transform);
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(
      pass,
      vertices,
      transform,
      viewportSize,
      cmd.color,
      floatLength: _vertexScratchLength,
    );
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
      lineJoin: cmd.lineJoin,
      pixelScale: _transformPixelScale(cmd.transform),
      pointCount: cmd.pointCount,
    );
    if (_vertexScratchLength == 0) return false;
    final transform = vm.Matrix4.copy(cmd.transform);
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(
      pass,
      vertices,
      transform,
      viewportSize,
      cmd.color,
      floatLength: _vertexScratchLength,
    );
    return true;
  }

  bool renderLine(
    gpu.RenderPass pass,
    LoveLineCommand cmd,
    ui.Size viewportSize, {
    required bool singleSample,
  }) {
    final pts = cmd.points;
    if (pts.length < 2) return false;
    if (_prepareSmoothLine(cmd, singleSample: singleSample)) {
      applyGpuDrawState(pass, cmd, viewportSize);
      _drawVertices(
        pass,
        _smoothLineTessellator.tessellateSegment(
          x0: pts[0].x,
          y0: pts[0].y,
          x1: pts[1].x,
          y1: pts[1].y,
          lineWidth: cmd.lineWidth,
        ),
        cmd.transform,
        viewportSize,
        cmd.color,
        floatLength: _smoothLineTessellator.floatLength,
      );
      return true;
    }
    final roughLineWidth = _prepareRoughLine(cmd, singleSample: singleSample);
    if (usesRoughLineShader &&
        roughLineWidth != null &&
        // Axis-aligned lines take the exact one-run rectangle path below.
        // Reserve the fragment shader for slopes where triangle coverage
        // diverges badly.
        _roughX0 != _roughX1 &&
        _roughY0 != _roughY1) {
      applyGpuDrawState(pass, cmd, viewportSize);
      _drawRoughLineShader(
        pass,
        viewportSize,
        cmd.color,
        lineWidth: roughLineWidth,
      );
      return true;
    }
    final axisAlignedRoughLine =
        usesRoughAxisRuns && (_roughX0 == _roughX1 || _roughY0 == _roughY1);
    final diagnosticRoughRasterization =
        _kRoughLineRasterization &&
        math.min((_roughX1 - _roughX0).abs(), (_roughY1 - _roughY0).abs()) <=
            _kMaxRoughLineRasterRuns;
    if (roughLineWidth != null &&
        (axisAlignedRoughLine || diagnosticRoughRasterization)) {
      final roughVertices = _roughLineRasterizer.rasterizeSegment(
        x0: _roughX0,
        y0: _roughY0,
        x1: _roughX1,
        y1: _roughY1,
        lineWidth: roughLineWidth,
      );
      applyGpuDrawState(pass, cmd, viewportSize);
      _drawVertices(
        pass,
        roughVertices,
        _identityTransform,
        viewportSize,
        cmd.color,
        floatLength: _roughLineRasterizer.floatLength,
      );
      return true;
    }
    final vertices = _lineVertices(pts, cmd.lineWidth, cmd.lineJoin);
    if (_vertexScratchLength == 0) return false;
    final transform = vm.Matrix4.copy(cmd.transform);
    if (_kRoughLinePixelSnap) {
      final snapAxes = loveRoughLinePixelSnapAxes(
        cmd.lineStyle,
        cmd.lineWidth,
        cmd.points,
        cmd.transform,
      );
      if (snapAxes != 0) {
        // LÖVE positions graphics coordinates at pixel corners. Flutter GPU's
        // triangle rasterization otherwise splits an odd-width rough stroke
        // across both neighboring pixel rows. Adjust the final device-space
        // translation so a 1:1 rough stroke occupies the same upper/left row
        // as native LÖVE, independent of the command's local scale/rotation.
        if (snapAxes & loveRoughLinePixelSnapX != 0) {
          transform.storage[12] -= 0.5;
        }
        if (snapAxes & loveRoughLinePixelSnapY != 0) {
          transform.storage[13] -= 0.5;
        }
      }
    }
    applyGpuDrawState(pass, cmd, viewportSize);
    _drawVertices(
      pass,
      vertices,
      transform,
      viewportSize,
      cmd.color,
      floatLength: _vertexScratchLength,
    );
    return true;
  }

  bool _prepareSmoothLine(
    LoveLineCommand command, {
    required bool singleSample,
  }) {
    if (!_kSmoothLineOverdraw ||
        !singleSample ||
        command.lineStyle != LoveGraphicsLineStyle.smooth ||
        command.lineJoin == LoveGraphicsLineJoin.none ||
        command.points.length != 2 ||
        !command.lineWidth.isFinite ||
        command.lineWidth <= 0.6) {
      return false;
    }

    // LOVE tracks one physical pixel separately from its transform matrix.
    // The command stream does not retain that stack value, so only use this
    // exact 1:1 path when the matrix is a pure translation. Scaled, sheared,
    // perspective, and multisampled lines retain the established fallback.
    final matrix = command.transform.storage;
    return (matrix[0] - 1).abs() <= _kEpsilon &&
        matrix[1].abs() <= _kEpsilon &&
        matrix[2].abs() <= _kEpsilon &&
        matrix[3].abs() <= _kEpsilon &&
        matrix[4].abs() <= _kEpsilon &&
        (matrix[5] - 1).abs() <= _kEpsilon &&
        matrix[6].abs() <= _kEpsilon &&
        matrix[7].abs() <= _kEpsilon &&
        matrix[8].abs() <= _kEpsilon &&
        matrix[9].abs() <= _kEpsilon &&
        (matrix[10] - 1).abs() <= _kEpsilon &&
        matrix[11].abs() <= _kEpsilon &&
        (matrix[15] - 1).abs() <= _kEpsilon;
  }

  int? _prepareRoughLine(
    LoveLineCommand command, {
    required bool singleSample,
  }) {
    if (!singleSample ||
        command.lineStyle != LoveGraphicsLineStyle.rough ||
        command.points.length != 2 ||
        !command.lineWidth.isFinite) {
      return null;
    }
    final lineWidth = command.lineWidth.round();
    if ((command.lineWidth - lineWidth).abs() > _kEpsilon ||
        lineWidth <= 0 ||
        lineWidth.isEven) {
      return null;
    }

    final matrix = command.transform.storage;
    if ((matrix[0] - 1).abs() > _kEpsilon ||
        matrix[1].abs() > _kEpsilon ||
        matrix[4].abs() > _kEpsilon ||
        (matrix[5] - 1).abs() > _kEpsilon ||
        matrix[3].abs() > _kEpsilon ||
        matrix[7].abs() > _kEpsilon) {
      return null;
    }
    final first = command.points[0];
    final last = command.points[1];
    final x0 = first.x + matrix[12];
    final y0 = first.y + matrix[13];
    final x1 = last.x + matrix[12];
    final y1 = last.y + matrix[13];
    final ix0 = x0.round();
    final iy0 = y0.round();
    final ix1 = x1.round();
    final iy1 = y1.round();
    if ((x0 - ix0).abs() > _kEpsilon ||
        (y0 - iy0).abs() > _kEpsilon ||
        (x1 - ix1).abs() > _kEpsilon ||
        (y1 - iy1).abs() > _kEpsilon) {
      return null;
    }
    if (ix0 == ix1 && iy0 == iy1) {
      return null;
    }
    _roughX0 = ix0;
    _roughY0 = iy0;
    _roughX1 = ix1;
    _roughY1 = iy1;
    return lineWidth;
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
      lineJoin: cmd.lineJoin,
    );
    if (_vertexScratchLength == 0) return false;
    final transform = vm.Matrix4.copy(cmd.transform);
    _drawVertices(
      pass,
      vertices,
      transform,
      viewportSize,
      cmd.color,
      floatLength: _vertexScratchLength,
    );
    return true;
  }

  bool renderArc(
    gpu.RenderPass pass,
    LoveArcCommand cmd,
    ui.Size viewportSize,
  ) {
    final pointCount = _prepareArcCoordinates(
      cmd.x,
      cmd.y,
      cmd.radius,
      cmd.angle1,
      cmd.angle2,
      pixelScale: _transformPixelScale(cmd.transform),
      pointCount: cmd.pointCount,
    );
    if (pointCount < 2) return false;
    final isLine = cmd.drawMode == LoveGraphicsDrawMode.line;
    final transform = vm.Matrix4.copy(cmd.transform);

    if (isLine) {
      var closed = false;
      switch (cmd.arcMode) {
        case LoveGraphicsArcMode.open:
          break;
        case LoveGraphicsArcMode.closed:
          closed = true;
        case LoveGraphicsArcMode.pie:
          _prependCoordinate(cmd.x, cmd.y, pointCount);
          closed = true;
      }
      final outlineCount = cmd.arcMode == LoveGraphicsArcMode.pie
          ? pointCount + 1
          : pointCount;
      final vertices = _strokeGeneratedVertices(
        outlineCount,
        cmd.lineWidth,
        cmd.lineJoin,
        closed: closed,
      );
      if (_vertexScratchLength == 0) return false;
      applyGpuDrawState(pass, cmd, viewportSize);
      _drawVertices(
        pass,
        vertices,
        transform,
        viewportSize,
        cmd.color,
        floatLength: _vertexScratchLength,
      );
      return true;
    }

    // Fill mode — triangle fan
    switch (cmd.arcMode) {
      case LoveGraphicsArcMode.open:
      case LoveGraphicsArcMode.closed:
        // LOVE converts filled open arcs to closed arcs so the final chord is
        // part of the polygon. Both modes therefore fan from the first point.
        {
          final vertices = _prepareVertices((pointCount - 1) * 3 * 8);
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

          for (var i = 1; i < pointCount; i++) {
            write(_generatedPointX(0), _generatedPointY(0));
            write(_generatedPointX(i), _generatedPointY(i));
            final next = (i + 1) % pointCount;
            write(_generatedPointX(next), _generatedPointY(next));
          }
          _vertexScratchLength = offset;
          applyGpuDrawState(pass, cmd, viewportSize);
          _drawVertices(
            pass,
            vertices,
            transform,
            viewportSize,
            cmd.color,
            floatLength: _vertexScratchLength,
          );
          return true;
        }
      case LoveGraphicsArcMode.pie:
        // Pie: fan from center
        {
          final vertices = _prepareVertices((pointCount - 1) * 3 * 8);
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

          for (var i = 1; i < pointCount; i++) {
            write(cmd.x, cmd.y);
            write(_generatedPointX(i - 1), _generatedPointY(i - 1));
            write(_generatedPointX(i), _generatedPointY(i));
          }
          _vertexScratchLength = offset;
          applyGpuDrawState(pass, cmd, viewportSize);
          _drawVertices(
            pass,
            vertices,
            transform,
            viewportSize,
            cmd.color,
            floatLength: _vertexScratchLength,
          );
          return true;
        }
    }
  }

  int _prepareArcCoordinates(
    double cx,
    double cy,
    double r,
    double a1,
    double a2, {
    required double pixelScale,
    int? pointCount,
  }) {
    var sweep = a2 - a1;
    if (sweep.abs() > 2 * math.pi) sweep = sweep.sign * 2 * math.pi;
    final steps =
        pointCount ?? gpuArcSegmentCount(r, sweep, pixelScale: pixelScale);
    if (steps <= 0) return 0;
    if (!usesTypedGeneratedStrokes) {
      final points = _pointScratch..clear();
      for (var index = 0; index <= steps; index++) {
        final angle = a1 + sweep * index / steps;
        points.add((x: cx + math.cos(angle) * r, y: cy + math.sin(angle) * r));
      }
      return points.length;
    }

    _ensurePointScratchCapacity(steps + 1);
    for (var i = 0; i <= steps; i++) {
      final angle = a1 + sweep * i / steps;
      _pointXScratch[i] = cx + math.cos(angle) * r;
      _pointYScratch[i] = cy + math.sin(angle) * r;
    }
    return steps + 1;
  }

  void _prependCoordinate(double x, double y, int count) {
    if (!usesTypedGeneratedStrokes) {
      _pointScratch.insert(0, (x: x, y: y));
      return;
    }
    _ensurePointScratchCapacity(count + 1);
    for (var index = count; index > 0; index--) {
      _pointXScratch[index] = _pointXScratch[index - 1];
      _pointYScratch[index] = _pointYScratch[index - 1];
    }
    _pointXScratch[0] = x;
    _pointYScratch[0] = y;
  }

  void _ensurePointScratchCapacity(int requiredLength) {
    if (_pointXScratch.length >= requiredLength) return;
    var capacity = _pointXScratch.isEmpty ? 64 : _pointXScratch.length;
    while (capacity < requiredLength) {
      capacity *= 2;
    }
    _pointXScratch = Float64List(capacity);
    _pointYScratch = Float64List(capacity);
  }

  double _generatedPointX(int index) => usesTypedGeneratedStrokes
      ? _pointXScratch[index]
      : _pointScratch[index].x;

  double _generatedPointY(int index) => usesTypedGeneratedStrokes
      ? _pointYScratch[index]
      : _pointScratch[index].y;

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
    final transform = vm.Matrix4.copy(cmd.transform);
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
    required LoveGraphicsLineJoin lineJoin,
    required double pixelScale,
    int? pointCount,
  }) {
    if (w <= 0 || h <= 0) {
      _vertexScratchLength = 0;
      return _vertexScratch;
    }

    if (isLine) {
      final path = _roundedRectanglePath(
        x,
        y,
        w,
        h,
        rx,
        ry,
        pixelScale: pixelScale,
        pointCount: pointCount,
      );
      return _strokeVertices(path, lineWidth, lineJoin, closed: true);
    }

    final path = _roundedRectanglePath(
      x,
      y,
      w,
      h,
      rx,
      ry,
      pixelScale: pixelScale,
      pointCount: pointCount,
    );
    final vertices = _prepareVertices(path.length * 3 * 8);
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

    final centerX = x + w * 0.5;
    final centerY = y + h * 0.5;
    for (var index = 0; index < path.length; index++) {
      final current = path[index];
      final next = path[(index + 1) % path.length];
      // Triangle fan with white per-vertex color (shader multiplies by the
      // command's uniform color).
      write(centerX, centerY);
      write(current.x, current.y);
      write(next.x, next.y);
    }
    _vertexScratchLength = offset;
    return vertices;
  }

  List<({double x, double y})> _roundedRectanglePath(
    double x,
    double y,
    double w,
    double h,
    double radiusX,
    double radiusY, {
    required double pixelScale,
    int? pointCount,
  }) {
    var rx = radiusX;
    var ry = radiusY;
    if (rx <= _kEpsilon || ry <= _kEpsilon) {
      return _pathScratch
        ..clear()
        ..add((x: x, y: y))
        ..add((x: x + w, y: y))
        ..add((x: x + w, y: y + h))
        ..add((x: x, y: y + h));
    }
    final cornerPointCount = gpuRoundedRectanglePointsPerCorner(
      rx,
      ry,
      w,
      h,
      pixelScale: pixelScale,
      pointCount: pointCount,
    );
    if (w >= 0.02) rx = math.min(rx, w * 0.5 - 0.01);
    if (h >= 0.02) ry = math.min(ry, h * 0.5 - 0.01);
    final angleStep = (math.pi * 0.5) / (cornerPointCount - 1);

    final points = _pathScratch..clear();
    void addCorner(double cx, double cy, double startAngle) {
      for (var index = 0; index < cornerPointCount; index++) {
        final angle = startAngle + angleStep * index;
        points.add((
          x: cx + math.cos(angle) * rx,
          y: cy + math.sin(angle) * ry,
        ));
      }
    }

    addCorner(x + rx, y + ry, math.pi);
    addCorner(x + w - rx, y + ry, math.pi * 1.5);
    addCorner(x + w - rx, y + h - ry, 0);
    addCorner(x + rx, y + h - ry, math.pi * 0.5);
    return points;
  }

  Float32List _ellipseVertices(
    double cx,
    double cy,
    double rx,
    double ry, {
    required bool isLine,
    double lineWidth = 0,
    required LoveGraphicsLineJoin lineJoin,
    required double pixelScale,
    int? pointCount,
  }) {
    if (rx <= 0 || ry <= 0) {
      _vertexScratchLength = 0;
      return _vertexScratch;
    }
    final segments = pointCount == null
        ? gpuEllipseSegmentCount(rx, ry, pixelScale: pixelScale)
        : math.max(pointCount, 1);
    final unitPoints = _circleUnitPoints(segments);

    if (isLine) {
      if (!usesTypedGeneratedStrokes) {
        final points = _pointScratch..clear();
        for (var index = 0; index < segments; index++) {
          points.add((
            x: cx + rx * unitPoints[index * 2],
            y: cy + ry * unitPoints[index * 2 + 1],
          ));
        }
        return _strokeVertices(points, lineWidth, lineJoin, closed: true);
      }

      _ensurePointScratchCapacity(segments);
      for (var i = 0; i < segments; i++) {
        _pointXScratch[i] = cx + rx * unitPoints[i * 2];
        _pointYScratch[i] = cy + ry * unitPoints[i * 2 + 1];
      }
      return _strokeGeneratedVertices(
        segments,
        lineWidth,
        lineJoin,
        closed: true,
      );
    }

    // Triangle fan from center
    final vertices = _prepareVertices(segments * 3 * 8);
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
      final p1 = i * 2;
      final p2 = (i + 1) * 2;
      write(cx, cy);
      write(cx + rx * unitPoints[p1], cy + ry * unitPoints[p1 + 1]);
      write(cx + rx * unitPoints[p2], cy + ry * unitPoints[p2 + 1]);
    }
    _vertexScratchLength = offset;
    return vertices;
  }

  double _transformPixelScale(vm.Matrix4 transform) {
    final matrix = transform.storage;
    final scaleX = math.sqrt(matrix[0] * matrix[0] + matrix[1] * matrix[1]);
    final scaleY = math.sqrt(matrix[4] * matrix[4] + matrix[5] * matrix[5]);
    final scale = (scaleX + scaleY) * 0.5;
    return scale.isFinite && scale > _kEpsilon ? scale : 1;
  }

  Float32List _lineVertices(
    List<({double x, double y})> points,
    double lineWidth,
    LoveGraphicsLineJoin lineJoin,
  ) {
    return _strokeVertices(points, lineWidth, lineJoin);
  }

  Float32List _polygonVertices(
    List<({double x, double y})> points, {
    required bool isLine,
    double lineWidth = 0,
    required LoveGraphicsLineJoin lineJoin,
  }) {
    if (points.length < 3) {
      _vertexScratchLength = 0;
      return _vertexScratch;
    }
    if (isLine) {
      return _strokeVertices(points, lineWidth, lineJoin, closed: true);
    }
    // Triangle fan from first vertex (convex polygons only)
    final vertices = _prepareVertices((points.length - 2) * 3 * 8);
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
    _vertexScratchLength = offset;
    return vertices;
  }

  Float32List _strokeVertices(
    List<({double x, double y})> points,
    double lineWidth,
    LoveGraphicsLineJoin lineJoin, {
    bool closed = false,
  }) {
    final vertices = _strokeTessellator.tessellate(
      points,
      lineWidth,
      lineJoin: lineJoin,
      closed: closed,
    );
    _vertexScratchLength = _strokeTessellator.floatLength;
    return vertices;
  }

  Float32List _strokeGeneratedVertices(
    int count,
    double lineWidth,
    LoveGraphicsLineJoin lineJoin, {
    bool closed = false,
  }) {
    final vertices = usesTypedGeneratedStrokes
        ? _strokeTessellator.tessellateCoordinates(
            _pointXScratch,
            _pointYScratch,
            count,
            lineWidth,
            lineJoin: lineJoin,
            closed: closed,
          )
        : _strokeTessellator.tessellate(
            _pointScratch,
            lineWidth,
            lineJoin: lineJoin,
            closed: closed,
          );
    _vertexScratchLength = _strokeTessellator.floatLength;
    return vertices;
  }

  // ---------------------------------------------------------------------------
  // Drawing helpers
  // ---------------------------------------------------------------------------

  void _drawRoughLineShader(
    gpu.RenderPass pass,
    ui.Size viewportSize,
    LoveColor color, {
    required int lineWidth,
  }) {
    _roughLineShaderGeometry.prepare(
      x0: _roughX0,
      y0: _roughY0,
      x1: _roughX1,
      y1: _roughY1,
      lineWidth: lineWidth,
      color: color,
      viewportWidth: viewportSize.width,
      viewportHeight: viewportSize.height,
    );
    final pipeline = _pipelineCache.getRoughLinePipeline();
    pass.bindPipeline(pipeline);
    bindVertexBufferCompat(
      pass,
      _hostBufferPool.emplaceFloat32List(_roughLineShaderGeometry.vertices),
    );
    pass.bindUniform(
      pipeline.fragmentShader.getUniformSlot('RoughLineInfo'),
      _hostBufferPool.emplaceFloat32List(_roughLineShaderGeometry.lineInfo),
    );
    drawVerticesCompat(pass, 6);
  }

  void _drawVertices(
    gpu.RenderPass pass,
    Float32List floats,
    vm.Matrix4 transform,
    ui.Size viewportSize,
    LoveColor color, {
    required int floatLength,
  }) {
    final mvp = _buildMVP(transform, viewportSize);
    _drawRaw(pass, floats, mvp, color, floatLength: floatLength);
  }

  void _drawRaw(
    gpu.RenderPass pass,
    Float32List floats,
    vm.Matrix4 mvp,
    LoveColor color, {
    int? floatLength,
  }) {
    final usedLength = floatLength ?? floats.length;
    if (usedLength <= 0 || usedLength > floats.length) return;
    if (usedLength % 8 != 0) return;

    final vertexBuffer = _hostBufferPool.emplaceFloat32List(
      floats,
      length: usedLength,
    );
    final vertexCount = usedLength ~/ 8;

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
