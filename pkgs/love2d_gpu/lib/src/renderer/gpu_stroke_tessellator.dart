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

/// Chooses enough arc segments to keep the geometric chord error subpixel.
///
/// The previous radius-times-sweep rule emitted hundreds of independent quads
/// for ordinary HUD rings. This bound keeps a 68px full circle near 52
/// segments while preserving a maximum 0.125 logical-pixel sagitta error.
int gpuArcSegmentCount(double radius, double sweep) {
  final resolvedRadius = radius.abs();
  final resolvedSweep = sweep.abs().clamp(0.0, math.pi * 2).toDouble();
  if (resolvedRadius <= _kStrokeEpsilon || resolvedSweep <= _kStrokeEpsilon) {
    return 8;
  }
  const maxError = 0.125;
  final cosine = (1 - maxError / resolvedRadius).clamp(-1.0, 1.0);
  final maxAngle = 2 * math.acos(cosine);
  if (!maxAngle.isFinite || maxAngle <= _kStrokeEpsilon) return 256;
  return (resolvedSweep / maxAngle).ceil().clamp(8, 256);
}
