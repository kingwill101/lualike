import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/love_runtime.dart';

void main() {
  group('love.font fallback scope parity', () {
    test(
      'direct fallbacks do not recurse transitively through nested fonts',
      () {
        final nestedFallback = LoveFont(
          size: 16.0,
          fontType: LoveFont.imageFontType,
          dataType: LoveFont.imageFontType,
          glyphs: 'C',
          glyphAdvances: const <int, double>{0x43: 3.0},
        );
        final directFallback = LoveFont(
          size: 16.0,
          fontType: LoveFont.imageFontType,
          dataType: LoveFont.imageFontType,
          glyphs: 'B',
          glyphAdvances: const <int, double>{0x42: 2.0},
        )..setFallbacks(<LoveFont>[nestedFallback]);
        final primary = LoveFont(
          size: 16.0,
          fontType: LoveFont.imageFontType,
          dataType: LoveFont.imageFontType,
          glyphs: 'A',
          glyphAdvances: const <int, double>{0x41: 1.0},
        )..setFallbacks(<LoveFont>[directFallback]);

        expect(primary.hasGlyphValues(const <Object?>['AB']), isTrue);
        expect(primary.hasGlyphValues(const <Object?>['AC']), isFalse);
        expect(primary.measureWidth('AB'), 3.0);
        expect(primary.measureWidth('AC'), 1.0);
      },
    );

    test('self fallbacks do not recurse infinitely for missing glyphs', () {
      final font = LoveFont(
        size: 16.0,
        fontType: LoveFont.imageFontType,
        dataType: LoveFont.imageFontType,
        glyphs: 'A',
        glyphAdvances: const <int, double>{0x41: 1.0},
      )..setFallbacks(<LoveFont>[]);

      font.setFallbacks(<LoveFont>[font]);

      expect(font.hasGlyphValues(const <Object?>['A']), isTrue);
      expect(font.hasGlyphValues(const <Object?>['Z']), isFalse);
      expect(font.measureWidth('A'), 1.0);
      expect(font.measureWidth('Z'), 0.0);
      expect(font.getKerning('A', 'Z'), 0.0);
    });
  });
}
