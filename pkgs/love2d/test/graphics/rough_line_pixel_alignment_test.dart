import 'package:love2d/love2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  const integerLine = <({double x, double y})>[(x: 0, y: 10), (x: 20, y: 10)];
  const halfPixelLine = <({double x, double y})>[
    (x: 0.5, y: 10.5),
    (x: 20.5, y: 10.5),
  ];

  test('odd rough integral coordinates select both device axes', () {
    expect(
      loveRoughLinePixelSnapAxes(
        LoveGraphicsLineStyle.rough,
        1,
        integerLine,
        vm.Matrix4.identity(),
      ),
      loveRoughLinePixelSnapX | loveRoughLinePixelSnapY,
    );
  });

  test('authored and transformed half pixels remain centered', () {
    expect(
      loveRoughLinePixelSnapAxes(
        LoveGraphicsLineStyle.rough,
        1,
        halfPixelLine,
        vm.Matrix4.identity(),
      ),
      0,
    );
    expect(
      loveRoughLinePixelSnapAxes(
        LoveGraphicsLineStyle.rough,
        1,
        integerLine,
        vm.Matrix4.translationValues(0.5, 0.5, 0),
      ),
      0,
    );
  });

  test('even, fractional, and smooth strokes are not snapped', () {
    for (final configuration in <({LoveGraphicsLineStyle style, double width})>[
      (style: LoveGraphicsLineStyle.rough, width: 2),
      (style: LoveGraphicsLineStyle.rough, width: 1.5),
      (style: LoveGraphicsLineStyle.smooth, width: 1),
    ]) {
      expect(
        loveRoughLinePixelSnapAxes(
          configuration.style,
          configuration.width,
          integerLine,
          vm.Matrix4.identity(),
        ),
        0,
      );
    }
  });
}
