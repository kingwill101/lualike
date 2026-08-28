import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('toRgbaBytes returns exact bytes without exposing mutable storage', () {
    final image = LoveImageData.fromRgbaBytes(
      width: 2,
      height: 1,
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
    );

    final first = image.toRgbaBytes();
    expect(first, <int>[1, 2, 3, 4, 5, 6, 7, 8]);

    first[0] = 255;
    expect(image.toRgbaBytes(), <int>[1, 2, 3, 4, 5, 6, 7, 8]);
  });
}
