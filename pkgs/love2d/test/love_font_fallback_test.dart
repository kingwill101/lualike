import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveFont callback fallbacks', () {
    test(
      'callback-backed true type fonts use fallback-aware width and wrap',
      () {
        const primaryAdvance = 6.0;
        final primary = LoveFont(
          size: 16.0,
          fontType: LoveFont.trueTypeFontType,
          dataType: LoveFont.trueTypeFontType,
          measureWidthCallback: (text) => switch (text) {
            'X' => primaryAdvance,
            'A' => 40.0,
            'B' => 41.0,
            'AB' => 81.0,
            _ => text.runes.length * 20.0,
          },
          wrapTextCallback: (text, wrapLimit) =>
              (width: 99.0, lines: <String>['callback']),
          supportsCodepointCallback: (codepoint) =>
              codepoint == 'X'.codeUnitAt(0),
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
              codepoint == 'A'.codeUnitAt(0) || codepoint == 'B'.codeUnitAt(0),
        );

        primary.setFallbacks(<LoveFont>[fallback]);

        expect(primary.measureWidth('AB'), 8.0);
        expect(primary.measureWidth('XA'), primaryAdvance + 5.0);
        expect(primary.measureWidth('XAB'), primaryAdvance + 8.0);
        expect(primary.getKerning('A', 'B'), -1.0);
        expect(primary.getKerning('X', 'A'), 0.0);
        expect(primary.hasGlyphValues(const <Object?>['XAB']), isTrue);
        expect(primary.hasGlyphValues(const <Object?>['XZ']), isFalse);

        final wrapped = primary.wrapText('XAB', 10.0);
        expect(wrapped.width, 8.0);
        expect(wrapped.lines, <String>['X', 'AB']);
      },
    );
  });
}
