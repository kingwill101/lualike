import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('centered mip sampling matches area averaging for even dimensions', () {
    final source = _horizontalRamp(<int>[0, 40, 80, 120], height: 2);

    final area = source.generateMipmaps(centeredLinear: false)[1];
    final centered = source.generateMipmaps(centeredLinear: true)[1];

    expect(centered.width, 2);
    expect(centered.height, 1);
    expect(centered.toRgbaBytes(), area.toRgbaBytes());
    expect(_redBytes(centered), <int>[20, 100]);
  });

  test('centered mip sampling spans the complete odd-sized source', () {
    final source = _horizontalRamp(<int>[0, 40, 80, 120, 160], height: 3);

    final area = source.generateMipmaps(centeredLinear: false)[1];
    final centered = source.generateMipmaps(centeredLinear: true)[1];

    expect(centered.width, 2);
    expect(centered.height, 1);
    expect(_redBytes(area), <int>[20, 120]);
    expect(_redBytes(centered), <int>[30, 130]);
  });

  test('centered mip generation reaches one pixel without changing format', () {
    final source = _horizontalRamp(<int>[0, 64, 128, 192, 255], height: 3);

    final levels = source.generateMipmaps(centeredLinear: true);

    expect(levels.map((level) => '${level.width}x${level.height}'), <String>[
      '5x3',
      '2x1',
      '1x1',
    ]);
    expect(levels.every((level) => level.format == 'rgba8'), isTrue);
  });
}

LoveImageData _horizontalRamp(List<int> values, {required int height}) {
  final bytes = Uint8List(values.length * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < values.length; x++) {
      final offset = ((y * values.length) + x) * 4;
      bytes[offset] = values[x];
      bytes[offset + 3] = 255;
    }
  }
  return LoveImageData.fromRgbaBytes(
    width: values.length,
    height: height,
    bytes: bytes,
  );
}

List<int> _redBytes(LoveImageData image) {
  final bytes = image.toRgbaBytes();
  return <int>[
    for (var offset = 0; offset < bytes.length; offset += 4) bytes[offset],
  ];
}
