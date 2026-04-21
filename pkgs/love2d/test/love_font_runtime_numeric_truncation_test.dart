import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/love_runtime.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('love.font runtime numeric truncation parity', () {
    test('LoveRasterizer and LoveFont truncate numeric codepoints', () async {
      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final sourceRasterizer = LoveRasterizer.trueType(
        size: 12.0,
        hinting: 'normal',
        dpiScale: 1.0,
        source: 'Vera.ttf',
        sourceBytes: veraBytes,
      );
      final sourceFont = sourceRasterizer.toLoveFont(
        defaultFilter: LoveGraphicsDefaultFilter.standard,
      );
      final defaultRasterizer = LoveRasterizer.trueType(
        size: 12.0,
        hinting: 'normal',
        dpiScale: 1.0,
      );
      final defaultFont = defaultRasterizer.toLoveFont(
        defaultFilter: LoveGraphicsDefaultFilter.standard,
      );

      final glyphData = sourceRasterizer.glyphDataForValue(65.9);
      final exactKerning = sourceFont.getKerning(65, 86);
      final fractionalKerning = sourceFont.getKerning(65.9, 86.9);

      expect(glyphData.glyph, 65);
      expect(exactKerning, isNonZero);
      expect(fractionalKerning, exactKerning);
      expect(defaultRasterizer.hasGlyphValues(<Object?>[0xd7ff + 0.9]), isTrue);
      expect(defaultFont.hasGlyphValues(<Object?>[0xd7ff + 0.9]), isTrue);
    });
  });
}
