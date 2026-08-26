import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_stroke_tessellator.dart';

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

  test('arc tessellation uses a subpixel chord-error bound', () {
    final segments = gpuArcSegmentCount(68, math.pi * 2);

    expect(segments, inInclusiveRange(48, 64));
    expect(segments, lessThan(68 * math.pi * 2 * 2));
  });
}
