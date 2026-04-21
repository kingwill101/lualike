part of '../love_runtime.dart';

typedef LoveMathPoint = ({double x, double y});
typedef LoveMathTriangle = ({
  LoveMathPoint a,
  LoveMathPoint b,
  LoveMathPoint c,
});

class LoveBezierCurve {
  LoveBezierCurve(Iterable<LoveMathPoint> controlPoints)
    : _controlPoints = List<LoveMathPoint>.from(controlPoints, growable: true);

  final List<LoveMathPoint> _controlPoints;

  int getDegree() => _controlPoints.length - 1;

  LoveBezierCurve getDerivative() {
    if (getDegree() < 1) {
      throw StateError('Cannot derive a curve of degree < 1.');
    }

    final degree = getDegree().toDouble();
    final derivative = <LoveMathPoint>[];
    for (var i = 0; i < _controlPoints.length - 1; i++) {
      derivative.add((
        x: (_controlPoints[i + 1].x - _controlPoints[i].x) * degree,
        y: (_controlPoints[i + 1].y - _controlPoints[i].y) * degree,
      ));
    }

    return LoveBezierCurve(derivative);
  }

  LoveMathPoint getControlPoint(int index) {
    if (_controlPoints.isEmpty) {
      throw StateError('Curve contains no control points.');
    }

    return _controlPoints[_wrappedControlPointIndex(index)];
  }

  int getControlPointCount() => _controlPoints.length;

  void insertControlPoint(LoveMathPoint point, [int position = -1]) {
    if (_controlPoints.isEmpty) {
      position = 0;
    }

    while (position < 0) {
      position += _controlPoints.length;
    }

    while (position > _controlPoints.length) {
      position -= _controlPoints.length;
    }

    _controlPoints.insert(position, point);
  }

  void removeControlPoint(int index) {
    if (_controlPoints.isEmpty) {
      throw StateError('No control points to remove.');
    }

    _controlPoints.removeAt(_wrappedControlPointIndex(index));
  }

  List<LoveMathPoint> render([int accuracy = 4]) {
    if (_controlPoints.length < 2) {
      throw StateError('Invalid Bezier curve: Not enough control points.');
    }

    final vertices = List<LoveMathPoint>.from(_controlPoints, growable: true);
    _subdivideBezier(vertices, accuracy);
    return List<LoveMathPoint>.unmodifiable(vertices);
  }

  List<LoveMathPoint> renderSegment(
    double start,
    double end, [
    int accuracy = 4,
  ]) {
    if (_controlPoints.length < 2) {
      throw StateError('Invalid Bezier curve: Not enough control points.');
    }

    final vertices = List<LoveMathPoint>.from(_controlPoints, growable: true);
    _subdivideBezier(vertices, accuracy);

    if (start == end) {
      return const <LoveMathPoint>[];
    }

    if (start < end) {
      final startIndex = (start * vertices.length).toInt();
      final endIndex = (end * vertices.length + 0.5).toInt();
      return List<LoveMathPoint>.unmodifiable(
        vertices.sublist(startIndex, endIndex),
      );
    }

    return List<LoveMathPoint>.unmodifiable(vertices);
  }

  void rotate(double angle, {double originX = 0.0, double originY = 0.0}) {
    final cosine = math.cos(angle);
    final sine = math.sin(angle);

    for (var i = 0; i < _controlPoints.length; i++) {
      final point = _controlPoints[i];
      final dx = point.x - originX;
      final dy = point.y - originY;
      _controlPoints[i] = (
        x: cosine * dx - sine * dy + originX,
        y: sine * dx + cosine * dy + originY,
      );
    }
  }

  void scale(double factor, {double originX = 0.0, double originY = 0.0}) {
    for (var i = 0; i < _controlPoints.length; i++) {
      final point = _controlPoints[i];
      _controlPoints[i] = (
        x: (point.x - originX) * factor + originX,
        y: (point.y - originY) * factor + originY,
      );
    }
  }

  LoveBezierCurve getSegment(double t1, double t2) {
    if (t1 < 0.0 || t2 > 1.0) {
      throw StateError('Invalid segment parameters: must be between 0 and 1');
    }

    if (t2 <= t1) {
      throw StateError(
        'Invalid segment parameters: t1 must be smaller than t2',
      );
    }

    final points = List<LoveMathPoint>.from(_controlPoints, growable: true);
    final left = <LoveMathPoint>[];
    final right = <LoveMathPoint>[];

    for (var step = 1; step < points.length; step++) {
      left.add(points.first);
      for (var i = 0; i < points.length - step; i++) {
        points[i] = (
          x: points[i].x + (points[i + 1].x - points[i].x) * t2,
          y: points[i].y + (points[i + 1].y - points[i].y) * t2,
        );
      }
    }
    left.add(points.first);

    final segmentFactor = t1 / t2;
    for (var step = 1; step < left.length; step++) {
      right.add(left[left.length - step]);
      for (var i = 0; i < left.length - step; i++) {
        left[i] = (
          x: left[i].x + (left[i + 1].x - left[i].x) * segmentFactor,
          y: left[i].y + (left[i + 1].y - left[i].y) * segmentFactor,
        );
      }
    }
    right.add(left.first);

    return LoveBezierCurve(right.reversed);
  }

  void setControlPoint(int index, LoveMathPoint point) {
    if (_controlPoints.isEmpty) {
      throw StateError('Curve contains no control points.');
    }

    _controlPoints[_wrappedControlPointIndex(index)] = point;
  }

  void translate(double dx, double dy) {
    for (var i = 0; i < _controlPoints.length; i++) {
      final point = _controlPoints[i];
      _controlPoints[i] = (x: point.x + dx, y: point.y + dy);
    }
  }

  LoveMathPoint evaluate(double t) {
    if (t < 0.0 || t > 1.0) {
      throw StateError('Invalid evaluation parameter: must be between 0 and 1');
    }

    if (_controlPoints.length < 2) {
      throw StateError('Invalid Bezier curve: Not enough control points.');
    }

    final points = List<LoveMathPoint>.from(_controlPoints, growable: true);
    for (var step = 1; step < _controlPoints.length; step++) {
      for (var i = 0; i < _controlPoints.length - step; i++) {
        points[i] = (
          x: points[i].x * (1.0 - t) + points[i + 1].x * t,
          y: points[i].y * (1.0 - t) + points[i + 1].y * t,
        );
      }
    }

    return points.first;
  }

  int _wrappedControlPointIndex(int index) {
    while (index < 0) {
      index += _controlPoints.length;
    }

    while (index >= _controlPoints.length) {
      index -= _controlPoints.length;
    }

    return index;
  }
}

double loveClamp01(double value) => value.clamp(0.0, 1.0);

double loveGammaToLinear(double value) {
  if (value <= 0.04045) {
    return value / 12.92;
  }

  return math.pow((value + 0.055) / 1.055, 2.4).toDouble();
}

bool loveIsConvex(List<LoveMathPoint> polygon) {
  if (polygon.length < 3) {
    return false;
  }

  var i = polygon.length - 2;
  var j = polygon.length - 1;
  var k = 0;

  var px = polygon[j].x - polygon[i].x;
  var py = polygon[j].y - polygon[i].y;
  var qx = polygon[k].x - polygon[j].x;
  var qy = polygon[k].y - polygon[j].y;
  final winding = _cross(px, py, qx, qy);

  while (k + 1 < polygon.length) {
    i = j;
    j = k;
    k++;

    px = polygon[j].x - polygon[i].x;
    py = polygon[j].y - polygon[i].y;
    qx = polygon[k].x - polygon[j].x;
    qy = polygon[k].y - polygon[j].y;

    if (_cross(px, py, qx, qy) * winding < 0.0) {
      return false;
    }
  }

  return true;
}

double loveLinearToGamma(double value) {
  if (value <= 0.0031308) {
    return value * 12.92;
  }

  return 1.055 * math.pow(value, 1.0 / 2.4).toDouble() - 0.055;
}

double loveNoise(List<double> coordinates) {
  if (coordinates.isEmpty) {
    throw ArgumentError('love.math.noise expects at least one coordinate');
  }

  return switch (coordinates.length) {
    1 => _simplexNoise1(coordinates[0]) * 0.5 + 0.5,
    2 => _simplexNoise2(coordinates[0], coordinates[1]) * 0.5 + 0.5,
    3 =>
      _perlinNoise3(coordinates[0], coordinates[1], coordinates[2]) * 0.5 + 0.5,
    _ =>
      _perlinNoise4(
                coordinates[0],
                coordinates[1],
                coordinates[2],
                coordinates[3],
              ) *
              0.5 +
          0.5,
  };
}

List<LoveMathTriangle> loveTriangulate(List<LoveMathPoint> polygon) {
  if (polygon.length < 3) {
    throw StateError('Not a polygon');
  }

  if (polygon.length == 3) {
    return <LoveMathTriangle>[(a: polygon[0], b: polygon[1], c: polygon[2])];
  }

  final nextIndex = List<int>.generate(
    polygon.length,
    (index) => index + 1,
    growable: false,
  );
  final previousIndex = List<int>.generate(
    polygon.length,
    (index) => index - 1,
    growable: false,
  );

  var leftmostIndex = 0;
  for (var i = 0; i < polygon.length; i++) {
    final leftmost = polygon[leftmostIndex];
    final point = polygon[i];
    if (point.x < leftmost.x ||
        (point.x == leftmost.x && point.y < leftmost.y)) {
      leftmostIndex = i;
    }
  }

  nextIndex[nextIndex.length - 1] = 0;
  previousIndex[0] = previousIndex.length - 1;

  if (!_isOrientedCcw(
    polygon[previousIndex[leftmostIndex]],
    polygon[leftmostIndex],
    polygon[nextIndex[leftmostIndex]],
  )) {
    for (var i = 0; i < nextIndex.length; i++) {
      final next = nextIndex[i];
      nextIndex[i] = previousIndex[i];
      previousIndex[i] = next;
    }
  }

  final concaveIndices = <int>{};
  for (var i = 0; i < polygon.length; i++) {
    if (!_isOrientedCcw(
      polygon[previousIndex[i]],
      polygon[i],
      polygon[nextIndex[i]],
    )) {
      concaveIndices.add(i);
    }
  }

  final triangles = <LoveMathTriangle>[];
  var vertexCount = polygon.length;
  var current = 1;
  var skipped = 0;

  while (vertexCount > 3) {
    final next = nextIndex[current];
    final previous = previousIndex[current];
    final a = polygon[previous];
    final b = polygon[current];
    final c = polygon[next];

    if (_isEar(a, b, c, polygon, concaveIndices)) {
      triangles.add((a: a, b: b, c: c));
      nextIndex[previous] = next;
      previousIndex[next] = previous;
      concaveIndices.remove(current);
      vertexCount--;
      skipped = 0;
    } else if (++skipped > vertexCount) {
      throw StateError('Cannot triangulate polygon.');
    }

    current = next;
  }

  final next = nextIndex[current];
  final previous = previousIndex[current];
  triangles.add((a: polygon[previous], b: polygon[current], c: polygon[next]));

  return List<LoveMathTriangle>.unmodifiable(triangles);
}

double _cross(double ax, double ay, double bx, double by) => ax * by - ay * bx;

double _fade(double value) {
  return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
}

int _fastFloor(double value) {
  return value > 0.0 ? value.toInt() : value.toInt() - 1;
}

double _grad1(int hash, double x) {
  final h = hash & 15;
  var gradient = 1.0 + (h & 7);
  if ((h & 8) != 0) {
    gradient = -gradient;
  }
  return gradient * x;
}

double _grad2(int hash, double x, double y) {
  final h = hash & 7;
  final u = h < 4 ? x : y;
  final v = h < 4 ? y : x;
  return ((h & 1) != 0 ? -u : u) + ((h & 2) != 0 ? -2.0 * v : 2.0 * v);
}

double _grad3(int hash, double x, double y, double z) {
  final h = hash & 15;
  final u = h < 8 ? x : y;
  final v = h < 4 ? y : (h == 12 || h == 14 ? x : z);
  return ((h & 1) != 0 ? -u : u) + ((h & 2) != 0 ? -v : v);
}

double _grad4(int hash, double x, double y, double z, double w) {
  final h = hash & 31;
  final u = h < 24 ? x : y;
  final v = h < 16 ? y : z;
  final t = h < 8 ? z : w;
  return ((h & 1) != 0 ? -u : u) +
      ((h & 2) != 0 ? -v : v) +
      ((h & 4) != 0 ? -t : t);
}

LoveMathPoint _midpoint(LoveMathPoint a, LoveMathPoint b) {
  return (x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5);
}

bool _isEar(
  LoveMathPoint a,
  LoveMathPoint b,
  LoveMathPoint c,
  List<LoveMathPoint> polygon,
  Set<int> concaveIndices,
) {
  return _isOrientedCcw(a, b, c) &&
      !_anyPointInTriangle(polygon, concaveIndices, a, b, c);
}

bool _isOrientedCcw(LoveMathPoint a, LoveMathPoint b, LoveMathPoint c) {
  return _cross(b.x - a.x, b.y - a.y, c.x - a.x, c.y - a.y) >= 0.0;
}

double _lerp(double t, double a, double b) => a + t * (b - a);

bool _anyPointInTriangle(
  List<LoveMathPoint> polygon,
  Set<int> indices,
  LoveMathPoint a,
  LoveMathPoint b,
  LoveMathPoint c,
) {
  for (final index in indices) {
    final point = polygon[index];
    if (point != a &&
        point != b &&
        point != c &&
        _pointInTriangle(point, a, b, c)) {
      return true;
    }
  }

  return false;
}

bool _onSameSide(
  LoveMathPoint a,
  LoveMathPoint b,
  LoveMathPoint c,
  LoveMathPoint d,
) {
  final px = d.x - c.x;
  final py = d.y - c.y;
  final left = px * (a.y - c.y) - py * (a.x - c.x);
  final right = px * (b.y - c.y) - py * (b.x - c.x);
  return left * right >= 0.0;
}

double _perlinNoise3(double x, double y, double z) {
  var ix0 = _fastFloor(x);
  var iy0 = _fastFloor(y);
  var iz0 = _fastFloor(z);
  final fx0 = x - ix0;
  final fy0 = y - iy0;
  final fz0 = z - iz0;
  final fx1 = fx0 - 1.0;
  final fy1 = fy0 - 1.0;
  final fz1 = fz0 - 1.0;
  final ix1 = (ix0 + 1) & 0xff;
  final iy1 = (iy0 + 1) & 0xff;
  final iz1 = (iz0 + 1) & 0xff;
  ix0 &= 0xff;
  iy0 &= 0xff;
  iz0 &= 0xff;

  final r = _fade(fz0);
  final t = _fade(fy0);
  final s = _fade(fx0);

  var nxy0 = _grad3(
    _loveNoisePerm[ix0 + _loveNoisePerm[iy0 + _loveNoisePerm[iz0]]],
    fx0,
    fy0,
    fz0,
  );
  var nxy1 = _grad3(
    _loveNoisePerm[ix0 + _loveNoisePerm[iy0 + _loveNoisePerm[iz1]]],
    fx0,
    fy0,
    fz1,
  );
  var nx0 = _lerp(r, nxy0, nxy1);

  nxy0 = _grad3(
    _loveNoisePerm[ix0 + _loveNoisePerm[iy1 + _loveNoisePerm[iz0]]],
    fx0,
    fy1,
    fz0,
  );
  nxy1 = _grad3(
    _loveNoisePerm[ix0 + _loveNoisePerm[iy1 + _loveNoisePerm[iz1]]],
    fx0,
    fy1,
    fz1,
  );
  var nx1 = _lerp(r, nxy0, nxy1);
  final n0 = _lerp(t, nx0, nx1);

  nxy0 = _grad3(
    _loveNoisePerm[ix1 + _loveNoisePerm[iy0 + _loveNoisePerm[iz0]]],
    fx1,
    fy0,
    fz0,
  );
  nxy1 = _grad3(
    _loveNoisePerm[ix1 + _loveNoisePerm[iy0 + _loveNoisePerm[iz1]]],
    fx1,
    fy0,
    fz1,
  );
  nx0 = _lerp(r, nxy0, nxy1);

  nxy0 = _grad3(
    _loveNoisePerm[ix1 + _loveNoisePerm[iy1 + _loveNoisePerm[iz0]]],
    fx1,
    fy1,
    fz0,
  );
  nxy1 = _grad3(
    _loveNoisePerm[ix1 + _loveNoisePerm[iy1 + _loveNoisePerm[iz1]]],
    fx1,
    fy1,
    fz1,
  );
  nx1 = _lerp(r, nxy0, nxy1);
  final n1 = _lerp(t, nx0, nx1);

  return 0.936 * _lerp(s, n0, n1);
}

double _perlinNoise4(double x, double y, double z, double w) {
  var ix0 = _fastFloor(x);
  var iy0 = _fastFloor(y);
  var iz0 = _fastFloor(z);
  var iw0 = _fastFloor(w);
  final fx0 = x - ix0;
  final fy0 = y - iy0;
  final fz0 = z - iz0;
  final fw0 = w - iw0;
  final fx1 = fx0 - 1.0;
  final fy1 = fy0 - 1.0;
  final fz1 = fz0 - 1.0;
  final fw1 = fw0 - 1.0;
  final ix1 = (ix0 + 1) & 0xff;
  final iy1 = (iy0 + 1) & 0xff;
  final iz1 = (iz0 + 1) & 0xff;
  final iw1 = (iw0 + 1) & 0xff;
  ix0 &= 0xff;
  iy0 &= 0xff;
  iz0 &= 0xff;
  iw0 &= 0xff;

  final q = _fade(fw0);
  final r = _fade(fz0);
  final t = _fade(fy0);
  final s = _fade(fx0);

  var nxyz0 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz0 + _loveNoisePerm[iw0]]]],
    fx0,
    fy0,
    fz0,
    fw0,
  );
  var nxyz1 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz0 + _loveNoisePerm[iw1]]]],
    fx0,
    fy0,
    fz0,
    fw1,
  );
  var nxy0 = _lerp(q, nxyz0, nxyz1);

  nxyz0 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz1 + _loveNoisePerm[iw0]]]],
    fx0,
    fy0,
    fz1,
    fw0,
  );
  nxyz1 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz1 + _loveNoisePerm[iw1]]]],
    fx0,
    fy0,
    fz1,
    fw1,
  );
  var nxy1 = _lerp(q, nxyz0, nxyz1);
  var nx0 = _lerp(r, nxy0, nxy1);

  nxyz0 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz0 + _loveNoisePerm[iw0]]]],
    fx0,
    fy1,
    fz0,
    fw0,
  );
  nxyz1 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz0 + _loveNoisePerm[iw1]]]],
    fx0,
    fy1,
    fz0,
    fw1,
  );
  nxy0 = _lerp(q, nxyz0, nxyz1);

  nxyz0 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz1 + _loveNoisePerm[iw0]]]],
    fx0,
    fy1,
    fz1,
    fw0,
  );
  nxyz1 = _grad4(
    _loveNoisePerm[ix0 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz1 + _loveNoisePerm[iw1]]]],
    fx0,
    fy1,
    fz1,
    fw1,
  );
  nxy1 = _lerp(q, nxyz0, nxyz1);
  var nx1 = _lerp(r, nxy0, nxy1);
  final n0 = _lerp(t, nx0, nx1);

  nxyz0 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz0 + _loveNoisePerm[iw0]]]],
    fx1,
    fy0,
    fz0,
    fw0,
  );
  nxyz1 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz0 + _loveNoisePerm[iw1]]]],
    fx1,
    fy0,
    fz0,
    fw1,
  );
  nxy0 = _lerp(q, nxyz0, nxyz1);

  nxyz0 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz1 + _loveNoisePerm[iw0]]]],
    fx1,
    fy0,
    fz1,
    fw0,
  );
  nxyz1 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy0 + _loveNoisePerm[iz1 + _loveNoisePerm[iw1]]]],
    fx1,
    fy0,
    fz1,
    fw1,
  );
  nxy1 = _lerp(q, nxyz0, nxyz1);
  nx0 = _lerp(r, nxy0, nxy1);

  nxyz0 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz0 + _loveNoisePerm[iw0]]]],
    fx1,
    fy1,
    fz0,
    fw0,
  );
  nxyz1 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz0 + _loveNoisePerm[iw1]]]],
    fx1,
    fy1,
    fz0,
    fw1,
  );
  nxy0 = _lerp(q, nxyz0, nxyz1);

  nxyz0 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz1 + _loveNoisePerm[iw0]]]],
    fx1,
    fy1,
    fz1,
    fw0,
  );
  nxyz1 = _grad4(
    _loveNoisePerm[ix1 +
        _loveNoisePerm[iy1 + _loveNoisePerm[iz1 + _loveNoisePerm[iw1]]]],
    fx1,
    fy1,
    fz1,
    fw1,
  );
  nxy1 = _lerp(q, nxyz0, nxyz1);
  nx1 = _lerp(r, nxy0, nxy1);
  final n1 = _lerp(t, nx0, nx1);

  return 0.87 * _lerp(s, n0, n1);
}

bool _pointInTriangle(
  LoveMathPoint p,
  LoveMathPoint a,
  LoveMathPoint b,
  LoveMathPoint c,
) {
  return _onSameSide(p, a, b, c) &&
      _onSameSide(p, b, a, c) &&
      _onSameSide(p, c, a, b);
}

double _simplexNoise1(double x) {
  final i0 = _fastFloor(x);
  final i1 = i0 + 1;
  final x0 = x - i0;
  final x1 = x0 - 1.0;

  var t0 = 1.0 - x0 * x0;
  t0 *= t0;
  final n0 = t0 * t0 * _grad1(_loveNoisePerm[i0 & 0xff], x0);

  var t1 = 1.0 - x1 * x1;
  t1 *= t1;
  final n1 = t1 * t1 * _grad1(_loveNoisePerm[i1 & 0xff], x1);

  return 0.395 * (n0 + n1);
}

double _simplexNoise2(double x, double y) {
  const f2 = 0.366025403;
  const g2 = 0.211324865;

  final s = (x + y) * f2;
  final xs = x + s;
  final ys = y + s;
  final i = _fastFloor(xs);
  final j = _fastFloor(ys);

  final t = (i + j) * g2;
  final x0 = x - (i - t);
  final y0 = y - (j - t);

  final (i1, j1) = x0 > y0 ? (1, 0) : (0, 1);

  final x1 = x0 - i1 + g2;
  final y1 = y0 - j1 + g2;
  final x2 = x0 - 1.0 + 2.0 * g2;
  final y2 = y0 - 1.0 + 2.0 * g2;

  final ii = i & 0xff;
  final jj = j & 0xff;

  final t0 = 0.5 - x0 * x0 - y0 * y0;
  final n0 = t0 < 0.0
      ? 0.0
      : (() {
          final t00 = t0 * t0;
          return t00 *
              t00 *
              _grad2(_loveNoisePerm[ii + _loveNoisePerm[jj]], x0, y0);
        })();

  final t1 = 0.5 - x1 * x1 - y1 * y1;
  final n1 = t1 < 0.0
      ? 0.0
      : (() {
          final t11 = t1 * t1;
          return t11 *
              t11 *
              _grad2(_loveNoisePerm[ii + i1 + _loveNoisePerm[jj + j1]], x1, y1);
        })();

  final t2 = 0.5 - x2 * x2 - y2 * y2;
  final n2 = t2 < 0.0
      ? 0.0
      : (() {
          final t22 = t2 * t2;
          return t22 *
              t22 *
              _grad2(_loveNoisePerm[ii + 1 + _loveNoisePerm[jj + 1]], x2, y2);
        })();

  return 45.23 * (n0 + n1 + n2);
}

void _subdivideBezier(List<LoveMathPoint> points, int depth) {
  if (depth <= 0) {
    return;
  }

  final left = <LoveMathPoint>[];
  final right = <LoveMathPoint>[];

  for (var step = 1; step < points.length; step++) {
    left.add(points.first);
    right.add(points[points.length - step]);
    for (var i = 0; i < points.length - step; i++) {
      points[i] = _midpoint(points[i], points[i + 1]);
    }
  }

  left.add(points.first);
  right.add(points.first);

  _subdivideBezier(left, depth - 1);
  _subdivideBezier(right, depth - 1);

  points
    ..clear()
    ..addAll(left)
    ..addAll(right.reversed.skip(1));
}

const List<int> _loveNoisePermBase = <int>[
  151,
  160,
  137,
  91,
  90,
  15,
  131,
  13,
  201,
  95,
  96,
  53,
  194,
  233,
  7,
  225,
  140,
  36,
  103,
  30,
  69,
  142,
  8,
  99,
  37,
  240,
  21,
  10,
  23,
  190,
  6,
  148,
  247,
  120,
  234,
  75,
  0,
  26,
  197,
  62,
  94,
  252,
  219,
  203,
  117,
  35,
  11,
  32,
  57,
  177,
  33,
  88,
  237,
  149,
  56,
  87,
  174,
  20,
  125,
  136,
  171,
  168,
  68,
  175,
  74,
  165,
  71,
  134,
  139,
  48,
  27,
  166,
  77,
  146,
  158,
  231,
  83,
  111,
  229,
  122,
  60,
  211,
  133,
  230,
  220,
  105,
  92,
  41,
  55,
  46,
  245,
  40,
  244,
  102,
  143,
  54,
  65,
  25,
  63,
  161,
  1,
  216,
  80,
  73,
  209,
  76,
  132,
  187,
  208,
  89,
  18,
  169,
  200,
  196,
  135,
  130,
  116,
  188,
  159,
  86,
  164,
  100,
  109,
  198,
  173,
  186,
  3,
  64,
  52,
  217,
  226,
  250,
  124,
  123,
  5,
  202,
  38,
  147,
  118,
  126,
  255,
  82,
  85,
  212,
  207,
  206,
  59,
  227,
  47,
  16,
  58,
  17,
  182,
  189,
  28,
  42,
  223,
  183,
  170,
  213,
  119,
  248,
  152,
  2,
  44,
  154,
  163,
  70,
  221,
  153,
  101,
  155,
  167,
  43,
  172,
  9,
  129,
  22,
  39,
  253,
  19,
  98,
  108,
  110,
  79,
  113,
  224,
  232,
  178,
  185,
  112,
  104,
  218,
  246,
  97,
  228,
  251,
  34,
  242,
  193,
  238,
  210,
  144,
  12,
  191,
  179,
  162,
  241,
  81,
  51,
  145,
  235,
  249,
  14,
  239,
  107,
  49,
  192,
  214,
  31,
  181,
  199,
  106,
  157,
  184,
  84,
  204,
  176,
  115,
  121,
  50,
  45,
  127,
  4,
  150,
  254,
  138,
  236,
  205,
  93,
  222,
  114,
  67,
  29,
  24,
  72,
  243,
  141,
  128,
  195,
  78,
  66,
  215,
  61,
  156,
  180,
];

const List<int> _loveNoisePerm = <int>[
  ..._loveNoisePermBase,
  ..._loveNoisePermBase,
];
