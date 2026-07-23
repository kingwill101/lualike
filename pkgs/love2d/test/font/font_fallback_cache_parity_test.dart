import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/love_runtime.dart';

void main() {
  group('love.font fallback cache parity', () {
    test('cached missing glyph widths survive later fallback installation', () {
      final primary = LoveFont(
        size: 16.0,
        fontType: LoveFont.imageFontType,
        dataType: LoveFont.imageFontType,
        glyphAdvances: const <int, double>{0x41: 4.0},
      );
      final fallback = LoveFont(
        size: 16.0,
        fontType: LoveFont.imageFontType,
        dataType: LoveFont.imageFontType,
        glyphAdvances: const <int, double>{0x58: 3.0, 0x59: 2.0},
      );

      expect(primary.measureWidth('X'), 0.0);

      primary.setFallbacks(<LoveFont>[fallback]);

      expect(primary.measureWidth('X'), 0.0);
      expect(primary.measureWidth('Y'), 2.0);
      expect(primary.measureWidth('AY'), 6.0);
    });

    test('cached kerning pairs survive later fallback installation', () {
      final primary = LoveFont(
        size: 16.0,
        fontType: LoveFont.trueTypeFontType,
        dataType: LoveFont.trueTypeFontType,
        measureWidthCallback: (text) => switch (text) {
          'X' => 6.0,
          _ => text.runes.length * 6.0,
        },
        supportsCodepointCallback: (codepoint) => codepoint == 0x58,
      );
      final fallback = LoveFont(
        size: 16.0,
        fontType: LoveFont.trueTypeFontType,
        dataType: LoveFont.trueTypeFontType,
        measureWidthCallback: (text) => switch (text) {
          'A' => 5.0,
          'B' => 4.0,
          'AB' => 8.0,
          _ => text.runes.length * 5.0,
        },
        supportsCodepointCallback: (codepoint) =>
            codepoint == 0x41 || codepoint == 0x42,
      );

      expect(primary.getKerning('A', 'B'), 0.0);

      primary.setFallbacks(<LoveFont>[fallback]);

      expect(primary.getKerning('A', 'B'), 0.0);
      expect(primary.measureWidth('AB'), 9.0);
    });
  });
}
