import 'dart:math' as math;
import 'dart:typed_data';

import 'package:love2d/love2d.dart';

const double _kStrokeEpsilon = 1e-6;
const double _kMiterLimit = 4.0;

/// Tessellates LOVE polylines without allocating geometry for every frame.
///
/// Miter strokes share the exact same pair of vertices at each join. This
/// avoids the pinholes produced by rendering every curved segment as an
/// independent quad. Bevel joins retain the segment quads and fill only the
/// outer wedge; `none` deliberately leaves segments disconnected.
final class GpuStrokeTessellator {
  Float32List _vertices = Float32List(0);
  Float64List _pointX = Float64List(0);
  Float64List _pointY = Float64List(0);
  Float64List _normalX = Float64List(0);
  Float64List _normalY = Float64List(0);
  Float64List _leftX = Float64List(0);
  Float64List _leftY = Float64List(0);
  Float64List _rightX = Float64List(0);
  Float64List _rightY = Float64List(0);
  int _vertexOffset = 0;

  int get floatLength => _vertexOffset;

  Float32List tessellate(
    List<({double x, double y})> points,
    double lineWidth, {
    required LoveGraphicsLineJoin lineJoin,
    bool closed = false,
  }) {
    if (points.length < 2 || lineWidth <= 0) {
      _vertexOffset = 0;
      return _vertices;
    }

    _ensurePointCapacity(points.length);
    var pointCount = 0;
    for (final point in points) {
      if (pointCount > 0 &&
          _near(_pointX[pointCount - 1], point.x) &&
          _near(_pointY[pointCount - 1], point.y)) {
        continue;
      }
      _pointX[pointCount] = point.x;
      _pointY[pointCount] = point.y;
      pointCount++;
    }
    return _tessellatePrepared(
      pointCount,
      lineWidth,
      lineJoin: lineJoin,
      closed: closed,
    );
  }

  /// Tessellates a reusable coordinate-buffer prefix.
  ///
  /// Shape generators can populate typed scratch storage directly instead of
  /// allocating one Dart record for every point of every animated circle or
  /// arc. Coordinates are copied into this tessellator's reusable work arrays
  /// before the caller can reuse its buffers; duplicate filtering and all
  /// subsequent geometry math are shared with [tessellate].
  Float32List tessellateCoordinates(
    Float64List x,
    Float64List y,
    int count,
    double lineWidth, {
    required LoveGraphicsLineJoin lineJoin,
    bool closed = false,
  }) {
    if (count < 0 || count > x.length || count > y.length) {
      throw RangeError.range(count, 0, math.min(x.length, y.length), 'count');
    }
    if (count < 2 || lineWidth <= 0) {
      _vertexOffset = 0;
      return _vertices;
    }

    _ensurePointCapacity(count);
    var pointCount = 0;
    for (var index = 0; index < count; index++) {
      final pointX = x[index];
      final pointY = y[index];
      if (pointCount > 0 &&
          _near(_pointX[pointCount - 1], pointX) &&
          _near(_pointY[pointCount - 1], pointY)) {
        continue;
      }
      _pointX[pointCount] = pointX;
      _pointY[pointCount] = pointY;
      pointCount++;
    }
    return _tessellatePrepared(
      pointCount,
      lineWidth,
      lineJoin: lineJoin,
      closed: closed,
    );
  }

  Float32List _tessellatePrepared(
    int pointCount,
    double lineWidth, {
    required LoveGraphicsLineJoin lineJoin,
    required bool closed,
  }) {
    if (closed &&
        pointCount > 1 &&
        _near(_pointX[0], _pointX[pointCount - 1]) &&
        _near(_pointY[0], _pointY[pointCount - 1])) {
      pointCount--;
    }
    if (pointCount < 2) {
      _vertexOffset = 0;
      return _vertices;
    }

    final segmentCount = closed ? pointCount : pointCount - 1;
    _ensureSegmentCapacity(segmentCount);
    for (var index = 0; index < segmentCount; index++) {
      final next = (index + 1) % pointCount;
      final dx = _pointX[next] - _pointX[index];
      final dy = _pointY[next] - _pointY[index];
      final length = math.sqrt(dx * dx + dy * dy);
      if (length <= _kStrokeEpsilon) {
        _normalX[index] = 0;
        _normalY[index] = 0;
      } else {
        _normalX[index] = -dy / length;
        _normalY[index] = dx / length;
      }
    }

    return switch (lineJoin) {
      LoveGraphicsLineJoin.miter => _tessellateMiter(
        pointCount,
        segmentCount,
        lineWidth * 0.5,
        closed: closed,
      ),
      LoveGraphicsLineJoin.bevel => _tessellateSegmentQuads(
        pointCount,
        segmentCount,
        lineWidth * 0.5,
        closed: closed,
        addBevelJoins: true,
      ),
      LoveGraphicsLineJoin.none => _tessellateSegmentQuads(
        pointCount,
        segmentCount,
        lineWidth * 0.5,
        closed: closed,
        addBevelJoins: false,
      ),
    };
  }

  Float32List _tessellateMiter(
    int pointCount,
    int segmentCount,
    double halfWidth, {
    required bool closed,
  }) {
    _prepareVertices(segmentCount * 6 * 8);
    for (var index = 0; index < pointCount; index++) {
      final isStart = !closed && index == 0;
      final isEnd = !closed && index == pointCount - 1;
      final previousSegment = index == 0 ? segmentCount - 1 : index - 1;
      final nextSegment = closed
          ? index
          : (index == pointCount - 1 ? segmentCount - 1 : index);

      var offsetX = 0.0;
      var offsetY = 0.0;
      if (isStart) {
        offsetX = _normalX[0] * halfWidth;
        offsetY = _normalY[0] * halfWidth;
      } else if (isEnd) {
        offsetX = _normalX[segmentCount - 1] * halfWidth;
        offsetY = _normalY[segmentCount - 1] * halfWidth;
      } else {
        final sumX = _normalX[previousSegment] + _normalX[nextSegment];
        final sumY = _normalY[previousSegment] + _normalY[nextSegment];
        final sumLength = math.sqrt(sumX * sumX + sumY * sumY);
        if (sumLength <= _kStrokeEpsilon) {
          offsetX = _normalX[nextSegment] * halfWidth;
          offsetY = _normalY[nextSegment] * halfWidth;
        } else {
          final miterX = sumX / sumLength;
          final miterY = sumY / sumLength;
          final denominator =
              miterX * _normalX[nextSegment] + miterY * _normalY[nextSegment];
          final unclamped = denominator.abs() <= _kStrokeEpsilon
              ? halfWidth
              : halfWidth / denominator;
          final limit = halfWidth * _kMiterLimit;
          final scale = unclamped.clamp(-limit, limit).toDouble();
          offsetX = miterX * scale;
          offsetY = miterY * scale;
        }
      }

      _leftX[index] = _pointX[index] + offsetX;
      _leftY[index] = _pointY[index] + offsetY;
      _rightX[index] = _pointX[index] - offsetX;
      _rightY[index] = _pointY[index] - offsetY;
    }

    for (var index = 0; index < segmentCount; index++) {
      final next = (index + 1) % pointCount;
      _writeQuad(
        _leftX[index],
        _leftY[index],
        _rightX[index],
        _rightY[index],
        _leftX[next],
        _leftY[next],
        _rightX[next],
        _rightY[next],
      );
    }
    return _vertices;
  }

  Float32List _tessellateSegmentQuads(
    int pointCount,
    int segmentCount,
    double halfWidth, {
    required bool closed,
    required bool addBevelJoins,
  }) {
    final joinCount = addBevelJoins
        ? (closed ? pointCount : math.max(0, pointCount - 2))
        : 0;
    _prepareVertices((segmentCount * 6 + joinCount * 3) * 8);

    for (var index = 0; index < segmentCount; index++) {
      final next = (index + 1) % pointCount;
      final nx = _normalX[index] * halfWidth;
      final ny = _normalY[index] * halfWidth;
      _writeQuad(
        _pointX[index] + nx,
        _pointY[index] + ny,
        _pointX[index] - nx,
        _pointY[index] - ny,
        _pointX[next] + nx,
        _pointY[next] + ny,
        _pointX[next] - nx,
        _pointY[next] - ny,
      );
    }

    if (addBevelJoins) {
      final first = closed ? 0 : 1;
      final end = closed ? pointCount : pointCount - 1;
      for (var index = first; index < end; index++) {
        final previousSegment = index == 0 ? segmentCount - 1 : index - 1;
        final nextSegment = closed
            ? index
            : (index == pointCount - 1 ? segmentCount - 1 : index);
        final cross =
            _normalX[previousSegment] * _normalY[nextSegment] -
            _normalY[previousSegment] * _normalX[nextSegment];
        if (cross.abs() <= _kStrokeEpsilon) continue;
        final outerSign = cross > 0 ? -1.0 : 1.0;
        _writeVertex(_pointX[index], _pointY[index]);
        _writeVertex(
          _pointX[index] + _normalX[previousSegment] * halfWidth * outerSign,
          _pointY[index] + _normalY[previousSegment] * halfWidth * outerSign,
        );
        _writeVertex(
          _pointX[index] + _normalX[nextSegment] * halfWidth * outerSign,
          _pointY[index] + _normalY[nextSegment] * halfWidth * outerSign,
        );
      }
    }
    return _vertices;
  }

  void _writeQuad(
    double startLeftX,
    double startLeftY,
    double startRightX,
    double startRightY,
    double endLeftX,
    double endLeftY,
    double endRightX,
    double endRightY,
  ) {
    _writeVertex(startLeftX, startLeftY);
    _writeVertex(startRightX, startRightY);
    _writeVertex(endLeftX, endLeftY);
    _writeVertex(startRightX, startRightY);
    _writeVertex(endRightX, endRightY);
    _writeVertex(endLeftX, endLeftY);
  }

  void _writeVertex(double x, double y) {
    _vertices[_vertexOffset++] = x;
    _vertices[_vertexOffset++] = y;
    _vertices[_vertexOffset++] = 0;
    _vertices[_vertexOffset++] = 0;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
  }

  void _prepareVertices(int requiredLength) {
    if (_vertices.length < requiredLength) {
      var capacity = _vertices.isEmpty ? 256 : _vertices.length;
      while (capacity < requiredLength) {
        capacity *= 2;
      }
      _vertices = Float32List(capacity);
    }
    _vertexOffset = 0;
  }

  void _ensurePointCapacity(int requiredLength) {
    if (_pointX.length >= requiredLength) return;
    final capacity = _grownCapacity(_pointX.length, requiredLength);
    _pointX = Float64List(capacity);
    _pointY = Float64List(capacity);
    _leftX = Float64List(capacity);
    _leftY = Float64List(capacity);
    _rightX = Float64List(capacity);
    _rightY = Float64List(capacity);
  }

  void _ensureSegmentCapacity(int requiredLength) {
    if (_normalX.length >= requiredLength) return;
    final capacity = _grownCapacity(_normalX.length, requiredLength);
    _normalX = Float64List(capacity);
    _normalY = Float64List(capacity);
  }

  int _grownCapacity(int current, int required) {
    var capacity = current == 0 ? 32 : current;
    while (capacity < required) {
      capacity *= 2;
    }
    return capacity;
  }

  bool _near(double a, double b) => (a - b).abs() <= _kStrokeEpsilon;
}

/// Tessellates LOVE's one-pixel alpha overdraw for a smooth line segment.
///
/// LOVE 11.5 draws a reduced opaque core, then surrounds it with a triangle
/// strip whose vertices alternate between full and zero alpha. The outer
/// vertices extend one physical pixel beyond both sides and both open caps.
/// Keeping the converted triangle list in reusable typed storage avoids a
/// shader-specific pipeline and per-command geometry allocations.
final class GpuSmoothLineTessellator {
  static const int _coreVertexCount = 6;
  static const int _overdrawStripVertexCount = 10;
  static const int _overdrawTriangleCount = _overdrawStripVertexCount - 2;
  static const int _floatCount =
      (_coreVertexCount + _overdrawTriangleCount * 3) * 8;

  final Float32List _vertices = Float32List(_floatCount);
  final Float64List _overdrawX = Float64List(_overdrawStripVertexCount);
  final Float64List _overdrawY = Float64List(_overdrawStripVertexCount);
  int _vertexOffset = 0;

  int get floatLength => _vertexOffset;

  Float32List tessellateSegment({
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double lineWidth,
    double pixelSize = 1,
  }) {
    _vertexOffset = 0;
    if (!x0.isFinite ||
        !y0.isFinite ||
        !x1.isFinite ||
        !y1.isFinite ||
        !lineWidth.isFinite ||
        !pixelSize.isFinite ||
        lineWidth <= 0 ||
        pixelSize <= 0) {
      return _vertices;
    }

    final dx = x1 - x0;
    final dy = y1 - y0;
    final length = math.sqrt(dx * dx + dy * dy);
    final coreHalfWidth = lineWidth * 0.5 - pixelSize * 0.3;
    if (length <= _kStrokeEpsilon || coreHalfWidth <= _kStrokeEpsilon) {
      return _vertices;
    }

    final tangentX = dx / length;
    final tangentY = dy / length;
    final normalX = -tangentY;
    final normalY = tangentX;
    final coreOffsetX = normalX * coreHalfWidth;
    final coreOffsetY = normalY * coreHalfWidth;
    final overdrawOffsetX = normalX * pixelSize;
    final overdrawOffsetY = normalY * pixelSize;
    final capOffsetX = tangentX * pixelSize;
    final capOffsetY = tangentY * pixelSize;

    final startLeftX = x0 + coreOffsetX;
    final startLeftY = y0 + coreOffsetY;
    final startRightX = x0 - coreOffsetX;
    final startRightY = y0 - coreOffsetY;
    final endLeftX = x1 + coreOffsetX;
    final endLeftY = y1 + coreOffsetY;
    final endRightX = x1 - coreOffsetX;
    final endRightY = y1 - coreOffsetY;

    _writeQuad(
      startLeftX,
      startLeftY,
      startRightX,
      startRightY,
      endLeftX,
      endLeftY,
      endRightX,
      endRightY,
    );

    _setOverdraw(0, startLeftX, startLeftY);
    _setOverdraw(
      1,
      startLeftX + overdrawOffsetX - capOffsetX,
      startLeftY + overdrawOffsetY - capOffsetY,
    );
    _setOverdraw(2, endLeftX, endLeftY);
    _setOverdraw(
      3,
      endLeftX + overdrawOffsetX + capOffsetX,
      endLeftY + overdrawOffsetY + capOffsetY,
    );
    _setOverdraw(4, endRightX, endRightY);
    _setOverdraw(
      5,
      endRightX - overdrawOffsetX + capOffsetX,
      endRightY - overdrawOffsetY + capOffsetY,
    );
    _setOverdraw(6, startRightX, startRightY);
    _setOverdraw(
      7,
      startRightX - overdrawOffsetX - capOffsetX,
      startRightY - overdrawOffsetY - capOffsetY,
    );
    _setOverdraw(8, startLeftX, startLeftY);
    _setOverdraw(
      9,
      startLeftX + overdrawOffsetX - capOffsetX,
      startLeftY + overdrawOffsetY - capOffsetY,
    );

    for (var index = 0; index < _overdrawTriangleCount; index++) {
      // Triangle strips reverse winding on every other triangle. Preserve a
      // consistent winding after conversion to the pipeline's triangle list.
      if (index.isEven) {
        _writeOverdrawVertex(index);
        _writeOverdrawVertex(index + 1);
      } else {
        _writeOverdrawVertex(index + 1);
        _writeOverdrawVertex(index);
      }
      _writeOverdrawVertex(index + 2);
    }
    return _vertices;
  }

  void _setOverdraw(int index, double x, double y) {
    _overdrawX[index] = x;
    _overdrawY[index] = y;
  }

  void _writeQuad(
    double startLeftX,
    double startLeftY,
    double startRightX,
    double startRightY,
    double endLeftX,
    double endLeftY,
    double endRightX,
    double endRightY,
  ) {
    _writeVertex(startLeftX, startLeftY, 1);
    _writeVertex(startRightX, startRightY, 1);
    _writeVertex(endLeftX, endLeftY, 1);
    _writeVertex(startRightX, startRightY, 1);
    _writeVertex(endRightX, endRightY, 1);
    _writeVertex(endLeftX, endLeftY, 1);
  }

  void _writeOverdrawVertex(int index) {
    _writeVertex(_overdrawX[index], _overdrawY[index], index.isEven ? 1 : 0);
  }

  void _writeVertex(double x, double y, double alpha) {
    _vertices[_vertexOffset++] = x;
    _vertices[_vertexOffset++] = y;
    _vertices[_vertexOffset++] = 0;
    _vertices[_vertexOffset++] = 0;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = alpha;
  }
}

/// Rasterizes native-style odd-width rough segments into pixel-aligned runs.
///
/// LÖVE's single-sample rough line path follows the major pixel axis and uses
/// floor selection on the minor axis. Coalescing adjacent pixels into one
/// rectangle preserves that occupancy without allocating one quad per pixel.
final class GpuRoughLineRasterizer {
  Float32List _vertices = Float32List(0);
  int _vertexOffset = 0;

  int get floatLength => _vertexOffset;

  Float32List rasterizeSegment({
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int lineWidth,
  }) {
    if (lineWidth <= 0 || lineWidth.isEven || (x0 == x1 && y0 == y1)) {
      _vertexOffset = 0;
      return _vertices;
    }

    final dx = x1 - x0;
    final dy = y1 - y0;
    final halfWidth = lineWidth ~/ 2;
    if (dx.abs() >= dy.abs()) {
      if (x1 < x0) {
        return rasterizeSegment(
          x0: x1,
          y0: y1,
          x1: x0,
          y1: y0,
          lineWidth: lineWidth,
        );
      }
      _rasterizeShallow(x0: x0, y0: y0, x1: x1, y1: y1, halfWidth: halfWidth);
    } else {
      if (y1 < y0) {
        return rasterizeSegment(
          x0: x1,
          y0: y1,
          x1: x0,
          y1: y0,
          lineWidth: lineWidth,
        );
      }
      _rasterizeSteep(x0: x0, y0: y0, x1: x1, y1: y1, halfWidth: halfWidth);
    }
    return _vertices;
  }

  void _rasterizeShallow({
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int halfWidth,
  }) {
    final majorLength = x1 - x0;
    final minorDelta = y1 - y0;
    final runCount = _runCount(minorDelta);
    _prepareVertices(runCount * 6 * 8);
    var runStart = x0;
    for (var run = 0; run < runCount; run++) {
      final runMinor = minorDelta > 0 ? y0 + run : y0 - run - 1;
      final runEndOffset = _runEndOffset(
        run: run,
        majorLength: majorLength,
        minorDelta: minorDelta,
      );
      _writeRect(
        runStart.toDouble(),
        (runMinor - halfWidth).toDouble(),
        (x0 + runEndOffset).toDouble(),
        (runMinor + halfWidth + 1).toDouble(),
      );
      runStart = x0 + runEndOffset;
    }
  }

  void _rasterizeSteep({
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int halfWidth,
  }) {
    final majorLength = y1 - y0;
    final minorDelta = x1 - x0;
    final runCount = _runCount(minorDelta);
    _prepareVertices(runCount * 6 * 8);
    var runStart = y0;
    for (var run = 0; run < runCount; run++) {
      final runMinor = minorDelta > 0 ? x0 + run : x0 - run - 1;
      final runEndOffset = _runEndOffset(
        run: run,
        majorLength: majorLength,
        minorDelta: minorDelta,
      );
      _writeRect(
        (runMinor - halfWidth).toDouble(),
        runStart.toDouble(),
        (runMinor + halfWidth + 1).toDouble(),
        (y0 + runEndOffset).toDouble(),
      );
      runStart = y0 + runEndOffset;
    }
  }

  int _runCount(int minorDelta) => minorDelta == 0 ? 1 : minorDelta.abs();

  int _runEndOffset({
    required int run,
    required int majorLength,
    required int minorDelta,
  }) {
    if (minorDelta == 0) return majorLength;
    final magnitude = minorDelta.abs();
    final numerator = 2 * (run + 1) * majorLength - magnitude;
    final denominator = 2 * magnitude;
    if (minorDelta > 0) {
      // floor(boundary - 0.5) + 1 preserves the upper/left tie break.
      return numerator ~/ denominator + 1;
    }
    // ceil(boundary - 0.5) is asymmetric at exact pixel boundaries.
    return (numerator + denominator - 1) ~/ denominator;
  }

  void _writeRect(double left, double top, double right, double bottom) {
    _writeVertex(left, top);
    _writeVertex(right, top);
    _writeVertex(left, bottom);
    _writeVertex(right, top);
    _writeVertex(right, bottom);
    _writeVertex(left, bottom);
  }

  void _writeVertex(double x, double y) {
    _vertices[_vertexOffset++] = x;
    _vertices[_vertexOffset++] = y;
    _vertices[_vertexOffset++] = 0;
    _vertices[_vertexOffset++] = 0;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
    _vertices[_vertexOffset++] = 1;
  }

  void _prepareVertices(int requiredLength) {
    if (_vertices.length < requiredLength) {
      var capacity = _vertices.isEmpty ? 256 : _vertices.length;
      while (capacity < requiredLength) {
        capacity *= 2;
      }
      _vertices = Float32List(capacity);
    }
    _vertexOffset = 0;
  }
}

/// Builds the constant-size quad and uniform payload used by the rough-line
/// fragment shader.
final class GpuRoughLineShaderGeometry {
  final Float32List vertices = Float32List(6 * 8);
  final Float32List lineInfo = Float32List(12);

  void prepare({
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int lineWidth,
    required LoveColor color,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    assert(lineWidth > 0 && lineWidth.isOdd);
    assert(viewportWidth > 0 && viewportHeight > 0);
    final shallow = (x1 - x0).abs() >= (y1 - y0).abs();
    if ((shallow && x1 < x0) || (!shallow && y1 < y0)) {
      final oldX0 = x0;
      final oldY0 = y0;
      x0 = x1;
      y0 = y1;
      x1 = oldX0;
      y1 = oldY0;
    }

    final halfWidth = lineWidth ~/ 2;
    final left = shallow ? x0 : math.min(x0, x1) - halfWidth - 1;
    final top = shallow ? math.min(y0, y1) - halfWidth - 1 : y0;
    final right = shallow ? x1 : math.max(x0, x1) + halfWidth + 1;
    final bottom = shallow ? math.max(y0, y1) + halfWidth + 1 : y1;

    var offset = 0;
    offset = _writeVertex(
      vertices,
      offset,
      left,
      top,
      viewportWidth,
      viewportHeight,
    );
    offset = _writeVertex(
      vertices,
      offset,
      right,
      top,
      viewportWidth,
      viewportHeight,
    );
    offset = _writeVertex(
      vertices,
      offset,
      left,
      bottom,
      viewportWidth,
      viewportHeight,
    );
    offset = _writeVertex(
      vertices,
      offset,
      right,
      top,
      viewportWidth,
      viewportHeight,
    );
    offset = _writeVertex(
      vertices,
      offset,
      right,
      bottom,
      viewportWidth,
      viewportHeight,
    );
    _writeVertex(vertices, offset, left, bottom, viewportWidth, viewportHeight);

    lineInfo[0] = x0.toDouble();
    lineInfo[1] = y0.toDouble();
    lineInfo[2] = x1.toDouble();
    lineInfo[3] = y1.toDouble();
    lineInfo[4] = lineWidth * 0.5;
    lineInfo[5] = shallow ? 1 : 0;
    lineInfo[6] = 0;
    lineInfo[7] = 0;
    lineInfo[8] = color.r;
    lineInfo[9] = color.g;
    lineInfo[10] = color.b;
    lineInfo[11] = color.a;
  }

  static int _writeVertex(
    Float32List target,
    int offset,
    int x,
    int y,
    double viewportWidth,
    double viewportHeight,
  ) {
    target[offset++] = x.toDouble();
    target[offset++] = y.toDouble();
    target[offset++] = 2 * x / viewportWidth - 1;
    target[offset++] = 1 - 2 * y / viewportHeight;
    target[offset++] = 1;
    target[offset++] = 1;
    target[offset++] = 1;
    target[offset++] = 1;
    return offset;
  }
}

/// Mirrors LOVE 11.5's default ellipse point-count calculation.
///
/// LOVE scales tessellation density with the current transform scale. Matching
/// the native count is both cheaper than a fixed high-density approximation
/// for ordinary game shapes and preserves the same single-sample edge pixels.
int gpuEllipseSegmentCount(
  double radiusX,
  double radiusY, {
  double pixelScale = 1,
}) {
  if (!radiusX.isFinite ||
      !radiusY.isFinite ||
      !pixelScale.isFinite ||
      radiusX <= 0 ||
      radiusY <= 0 ||
      pixelScale <= 0) {
    return 8;
  }
  final meanRadius = (radiusX + radiusY) * 0.5;
  return math.max(8, math.sqrt(meanRadius * 20 * pixelScale).floor());
}

/// Mirrors LOVE 11.5's default arc point-count calculation.
int gpuArcSegmentCount(double radius, double sweep, {double pixelScale = 1}) {
  if (!radius.isFinite ||
      !sweep.isFinite ||
      radius <= 0 ||
      sweep == 0 ||
      !pixelScale.isFinite ||
      pixelScale <= 0) {
    return 0;
  }
  var points = gpuEllipseSegmentCount(
    radius,
    radius,
    pixelScale: pixelScale,
  ).toDouble();
  final angle = sweep.abs();
  if (angle < math.pi * 2) {
    points *= angle / (math.pi * 2);
  }
  return (points + 0.5).floor();
}

/// Mirrors LOVE 11.5's rounded-rectangle point-count subdivision.
///
/// LOVE first chooses an ellipse point count, divides it between four
/// corners, and retains both tangent endpoints for each corner.
int gpuRoundedRectanglePointsPerCorner(
  double radiusX,
  double radiusY,
  double width,
  double height, {
  double pixelScale = 1,
  int? pointCount,
}) {
  final resolvedPointCount =
      pointCount ??
      gpuEllipseSegmentCount(
        math.min(radiusX, (width * 0.5).abs()),
        math.min(radiusY, (height * 0.5).abs()),
        pixelScale: pixelScale,
      );
  return math.max(resolvedPointCount ~/ 4, 1) + 2;
}
