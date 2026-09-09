import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_stroke_tessellator.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  const closedSquare = <({double x, double y})>[
    (x: 0, y: 0),
    (x: 10, y: 0),
    (x: 10, y: 10),
    (x: 0, y: 10),
    (x: 0, y: 0),
  ];

  test('miter joins share endpoints between every closed segment', () {
    final tessellator = GpuStrokeTessellator();
    final vertices = tessellator.tessellate(
      closedSquare,
      2,
      lineJoin: LoveGraphicsLineJoin.miter,
      closed: true,
    );

    expect(tessellator.floatLength, 4 * 6 * 8);
    for (var segment = 0; segment < 4; segment++) {
      final base = segment * 6 * 8;
      final nextBase = ((segment + 1) % 4) * 6 * 8;
      expect(vertices[base + 2 * 8], vertices[nextBase]);
      expect(vertices[base + 2 * 8 + 1], vertices[nextBase + 1]);
      expect(vertices[base + 4 * 8], vertices[nextBase + 8]);
      expect(vertices[base + 4 * 8 + 1], vertices[nextBase + 9]);
    }
  });

  test('bevel fills outer wedges while none leaves segments independent', () {
    final tessellator = GpuStrokeTessellator();
    tessellator.tessellate(
      closedSquare,
      2,
      lineJoin: LoveGraphicsLineJoin.bevel,
      closed: true,
    );
    expect(tessellator.floatLength, (4 * 6 + 4 * 3) * 8);

    tessellator.tessellate(
      closedSquare,
      2,
      lineJoin: LoveGraphicsLineJoin.none,
      closed: true,
    );
    expect(tessellator.floatLength, 4 * 6 * 8);
  });

  test('coordinate buffers preserve record-list geometry exactly', () {
    final recordTessellator = GpuStrokeTessellator();
    final recordVertices = recordTessellator.tessellate(
      closedSquare,
      2,
      lineJoin: LoveGraphicsLineJoin.miter,
      closed: true,
    );
    final recordLength = recordTessellator.floatLength;
    final expected = List<double>.of(recordVertices.take(recordLength));

    final coordinateTessellator = GpuStrokeTessellator();
    final coordinateVertices = coordinateTessellator.tessellateCoordinates(
      Float64List.fromList(closedSquare.map((point) => point.x).toList()),
      Float64List.fromList(closedSquare.map((point) => point.y).toList()),
      closedSquare.length,
      2,
      lineJoin: LoveGraphicsLineJoin.miter,
      closed: true,
    );

    expect(coordinateTessellator.floatLength, recordLength);
    expect(coordinateVertices.take(recordLength), orderedEquals(expected));
  });

  test('ellipse tessellation mirrors LOVE 11.5 point counts', () {
    expect(gpuEllipseSegmentCount(68, 68), 36);
    expect(gpuEllipseSegmentCount(4, 4), 8);
    expect(gpuEllipseSegmentCount(68, 68, pixelScale: 4), 73);
  });

  test('arc tessellation scales LOVE point counts by sweep fraction', () {
    expect(gpuArcSegmentCount(68, math.pi * 2), 36);
    expect(gpuArcSegmentCount(68, math.pi), 18);
    expect(gpuArcSegmentCount(68, 0), 0);
  });

  test('rounded rectangles divide LOVE point counts between corners', () {
    expect(gpuRoundedRectanglePointsPerCorner(20, 14, 104, 70), 6);
    expect(
      gpuRoundedRectanglePointsPerCorner(20, 14, 104, 70, pointCount: 8),
      4,
    );
    expect(
      gpuRoundedRectanglePointsPerCorner(20, 14, 104, 70, pointCount: 20),
      7,
    );
  });

  test('shared rough-line snap preserves authored half pixels', () {
    const integerLine = <({double x, double y})>[(x: 0, y: 10), (x: 20, y: 10)];
    const halfPixelLine = <({double x, double y})>[
      (x: 0.5, y: 10.5),
      (x: 20.5, y: 10.5),
    ];
    final identity = vm.Matrix4.identity();

    expect(
      loveRoughLinePixelSnapAxes(
        LoveGraphicsLineStyle.rough,
        1,
        integerLine,
        identity,
      ),
      loveRoughLinePixelSnapX | loveRoughLinePixelSnapY,
    );
    expect(
      loveRoughLinePixelSnapAxes(
        LoveGraphicsLineStyle.rough,
        1,
        halfPixelLine,
        identity,
      ),
      0,
    );
    expect(
      loveRoughLinePixelSnapAxes(
        LoveGraphicsLineStyle.rough,
        2,
        integerLine,
        identity,
      ),
      0,
    );
    expect(
      loveRoughLinePixelSnapAxes(
        LoveGraphicsLineStyle.smooth,
        1,
        integerLine,
        identity,
      ),
      0,
    );
  });

  test('rough rasterizer coalesces native shallow pixel runs', () {
    final rasterizer = GpuRoughLineRasterizer();
    final vertices = rasterizer.rasterizeSegment(
      x0: 0,
      y0: 0,
      x1: 8,
      y1: 2,
      lineWidth: 1,
    );

    expect(rasterizer.floatLength, 2 * 6 * 8);
    expect(_quadBounds(vertices, 0), (left: 0, top: 0, right: 4, bottom: 1));
    expect(_quadBounds(vertices, 1), (left: 4, top: 1, right: 8, bottom: 2));
  });

  test('smooth segment reproduces LOVE core and one-pixel overdraw', () {
    final tessellator = GpuSmoothLineTessellator();
    final vertices = tessellator.tessellateSegment(
      x0: 4,
      y0: 10,
      x1: 24,
      y1: 10,
      lineWidth: 1,
    );

    expect(tessellator.floatLength, 30 * 8);
    _expectBoundsClose(_bounds(vertices, tessellator.floatLength), (
      left: 3,
      top: 8.8,
      right: 25,
      bottom: 11.2,
    ));
    _expectBoundsClose(_quadBounds(vertices, 0), (
      left: 4,
      top: 9.8,
      right: 24,
      bottom: 10.2,
    ));

    for (var vertex = 0; vertex < 6; vertex++) {
      expect(vertices[vertex * 8 + 7], 1);
    }
    expect(vertices[6 * 8 + 7], 1);
    expect(vertices[7 * 8 + 7], 0);
    expect(vertices[8 * 8 + 7], 1);
  });

  test('smooth segment scales its overdraw by the supplied pixel size', () {
    final tessellator = GpuSmoothLineTessellator();
    final vertices = tessellator.tessellateSegment(
      x0: 0,
      y0: 0,
      x1: 0,
      y1: 10,
      lineWidth: 2,
      pixelSize: 0.5,
    );

    _expectBoundsClose(_bounds(vertices, tessellator.floatLength), (
      left: -1.35,
      top: -0.5,
      right: 1.35,
      bottom: 10.5,
    ));
  });

  test('smooth segment reuses storage and rejects degenerate geometry', () {
    final tessellator = GpuSmoothLineTessellator();
    final first = tessellator.tessellateSegment(
      x0: 0,
      y0: 0,
      x1: 10,
      y1: 0,
      lineWidth: 1,
    );
    final second = tessellator.tessellateSegment(
      x0: 0,
      y0: 0,
      x1: 10,
      y1: 10,
      lineWidth: 1,
    );

    expect(second, same(first));
    tessellator.tessellateSegment(x0: 1, y0: 1, x1: 1, y1: 1, lineWidth: 1);
    expect(tessellator.floatLength, 0);
  });

  test('rough rasterizer expands odd widths around the selected pixel', () {
    final rasterizer = GpuRoughLineRasterizer();
    final vertices = rasterizer.rasterizeSegment(
      x0: 0,
      y0: 0,
      x1: 8,
      y1: 2,
      lineWidth: 3,
    );

    expect(_quadBounds(vertices, 0), (left: 0, top: -1, right: 4, bottom: 2));
    expect(_quadBounds(vertices, 1), (left: 4, top: 0, right: 8, bottom: 3));
  });

  test('rough rasterizer resolves exact boundaries toward upper left', () {
    final horizontal = GpuRoughLineRasterizer();
    final horizontalVertices = horizontal.rasterizeSegment(
      x0: 4,
      y0: 8,
      x1: 12,
      y1: 8,
      lineWidth: 1,
    );
    final vertical = GpuRoughLineRasterizer();
    final verticalVertices = vertical.rasterizeSegment(
      x0: 4,
      y0: 8,
      x1: 4,
      y1: 16,
      lineWidth: 1,
    );

    expect(_quadBounds(horizontalVertices, 0), (
      left: 4,
      top: 7,
      right: 12,
      bottom: 8,
    ));
    expect(_quadBounds(verticalVertices, 0), (
      left: 3,
      top: 8,
      right: 4,
      bottom: 16,
    ));
  });

  test('rough rasterizer is direction invariant for steep segments', () {
    final forward = GpuRoughLineRasterizer();
    final forwardVertices = forward.rasterizeSegment(
      x0: 2,
      y0: 0,
      x1: 0,
      y1: 8,
      lineWidth: 1,
    );
    final expected = List<double>.of(forwardVertices.take(forward.floatLength));
    final reverse = GpuRoughLineRasterizer();
    final reverseVertices = reverse.rasterizeSegment(
      x0: 0,
      y0: 8,
      x1: 2,
      y1: 0,
      lineWidth: 1,
    );

    expect(reverse.floatLength, forward.floatLength);
    expect(reverseVertices.take(reverse.floatLength), orderedEquals(expected));
  });

  test('rough rasterizer matches pixel-center reference across slopes', () {
    for (var majorLength = 1; majorLength <= 20; majorLength++) {
      for (
        var minorDelta = -majorLength;
        minorDelta <= majorLength;
        minorDelta++
      ) {
        final shallow = GpuRoughLineRasterizer();
        final shallowVertices = shallow.rasterizeSegment(
          x0: 0,
          y0: 0,
          x1: majorLength,
          y1: minorDelta,
          lineWidth: 1,
        );
        expect(
          _occupiedPixels(shallowVertices, shallow.floatLength),
          _referencePixels(majorLength, minorDelta, steep: false),
          reason: 'shallow major=$majorLength minor=$minorDelta',
        );

        final steep = GpuRoughLineRasterizer();
        final steepVertices = steep.rasterizeSegment(
          x0: 0,
          y0: 0,
          x1: minorDelta,
          y1: majorLength,
          lineWidth: 1,
        );
        expect(
          _occupiedPixels(steepVertices, steep.floatLength),
          _referencePixels(majorLength, minorDelta, steep: true),
          reason: 'steep major=$majorLength minor=$minorDelta',
        );
      }
    }
  });

  test('rough-line shader geometry is one ordered conservative quad', () {
    final geometry = GpuRoughLineShaderGeometry()
      ..prepare(
        x0: 8,
        y0: 2,
        x1: 0,
        y1: 0,
        lineWidth: 3,
        color: const LoveColor(0.1, 0.2, 0.3, 0.4),
        viewportWidth: 8,
        viewportHeight: 4,
      );

    expect(geometry.vertices.length, 6 * 8);
    expect(_quadBounds(geometry.vertices, 0), (
      left: 0,
      top: -2,
      right: 8,
      bottom: 4,
    ));
    expect(
      geometry.lineInfo.take(8),
      orderedEquals(<double>[0, 0, 8, 2, 1.5, 1, 0, 0]),
    );
    expect(geometry.lineInfo[8], closeTo(0.1, 1e-6));
    expect(geometry.lineInfo[9], closeTo(0.2, 1e-6));
    expect(geometry.lineInfo[10], closeTo(0.3, 1e-6));
    expect(geometry.lineInfo[11], closeTo(0.4, 1e-6));
    expect(geometry.vertices[2], -1);
    expect(geometry.vertices[3], 2);
    expect(geometry.vertices[8 + 2], 1);
    expect(geometry.vertices[8 + 3], 2);
  });
}

Set<(int, int)> _occupiedPixels(Float32List vertices, int floatLength) {
  final pixels = <(int, int)>{};
  for (var offset = 0; offset < floatLength; offset += 6 * 8) {
    final bounds = _quadBounds(vertices, offset ~/ (6 * 8));
    for (var y = bounds.top.round(); y < bounds.bottom.round(); y++) {
      for (var x = bounds.left.round(); x < bounds.right.round(); x++) {
        pixels.add((x, y));
      }
    }
  }
  return pixels;
}

Set<(int, int)> _referencePixels(
  int majorLength,
  int minorDelta, {
  required bool steep,
}) {
  return <(int, int)>{
    for (var offset = 0; offset < majorLength; offset++)
      if (steep)
        ((minorDelta * (offset + 0.5) / majorLength).ceil() - 1, offset)
      else
        (offset, (minorDelta * (offset + 0.5) / majorLength).ceil() - 1),
  };
}

({double left, double top, double right, double bottom}) _quadBounds(
  Float32List vertices,
  int quadIndex,
) {
  final offset = quadIndex * 6 * 8;
  final xs = <double>[
    for (var vertex = 0; vertex < 6; vertex++) vertices[offset + vertex * 8],
  ];
  final ys = <double>[
    for (var vertex = 0; vertex < 6; vertex++)
      vertices[offset + vertex * 8 + 1],
  ];
  return (
    left: xs.reduce(math.min),
    top: ys.reduce(math.min),
    right: xs.reduce(math.max),
    bottom: ys.reduce(math.max),
  );
}

({double left, double top, double right, double bottom}) _bounds(
  Float32List vertices,
  int floatLength,
) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (var offset = 0; offset < floatLength; offset += 8) {
    left = math.min(left, vertices[offset]);
    top = math.min(top, vertices[offset + 1]);
    right = math.max(right, vertices[offset]);
    bottom = math.max(bottom, vertices[offset + 1]);
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

void _expectBoundsClose(
  ({double left, double top, double right, double bottom}) actual,
  ({double left, double top, double right, double bottom}) expected,
) {
  expect(actual.left, closeTo(expected.left, 1e-6));
  expect(actual.top, closeTo(expected.top, 1e-6));
  expect(actual.right, closeTo(expected.right, 1e-6));
  expect(actual.bottom, closeTo(expected.bottom, 1e-6));
}
