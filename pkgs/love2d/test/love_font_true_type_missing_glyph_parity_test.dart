import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/love_runtime.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('love.font true type missing glyph parity', () {
    test('source-backed fonts keep primary missing-glyph advance '
        'when coverage rejects a codepoint', () async {
      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final rasterizer = LoveRasterizer.trueType(
        size: 12.0,
        source: 'Vera.ttf',
        sourceBytes: veraBytes,
        hinting: 'normal',
        dpiScale: 2.0,
      );
      final font = rasterizer.toLoveFont(
        defaultFilter: LoveGraphicsDefaultFilter.standard,
      );

      const missingCodepoint = 0x1f642;
      final missingGlyph = String.fromCharCode(missingCodepoint);
      final glyphData = rasterizer.glyphDataForValue(missingGlyph);

      expect(rasterizer.hasGlyph(missingCodepoint), isFalse);
      expect(font.hasGlyphValues(<Object?>[missingGlyph]), isFalse);
      expect(glyphData.advance, greaterThan(0));
      expect(
        font.measureWidth(missingGlyph),
        closeTo(glyphData.advance / 2.0, 1e-9),
      );
    });

    test('default true type metadata fonts keep missing-glyph '
        'advance and synthetic tab spacing', () async {
      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final metadata = parseLoveTrueTypeFontMetadata(veraBytes);
      final context = LoveRuntimeContext(
        host: LoveHeadlessHost(
          defaultTrueTypeFontDataLoader: () async =>
              Uint8List.fromList(veraBytes),
        ),
      );

      final font = await context.createDefaultTrueTypeOrFallbackFont(
        size: 12.0,
        hinting: 'normal',
        dpiScale: 2.0,
        defaultFilter: LoveGraphicsDefaultFilter.standard,
      );

      const missingCodepoint = 0x1f642;
      final missingGlyph = String.fromCharCode(missingCodepoint);
      final expectedMissingAdvance = metadata?.logicalMaxAdvance(
        12.0,
        dpiScale: 2.0,
      );

      expect(expectedMissingAdvance, isNotNull);
      expect(font.hasGlyphValues(<Object?>[missingGlyph]), isFalse);
      expect(
        font.measureWidth(missingGlyph),
        closeTo(expectedMissingAdvance!, 1e-9),
      );

      expect(font.hasGlyphValues(const <Object?>['\t']), isFalse);
      expect(font.measureWidth('\t'), closeTo(font.measureWidth('    '), 1e-9));
      expect(
        font.measureWidth('A\tA'),
        closeTo(font.measureWidth('A    A'), 1e-9),
      );
    });

    test('default true type metadata fonts match rasterizer-backed '
        'true type conversion', () async {
      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final context = LoveRuntimeContext(
        host: LoveHeadlessHost(
          defaultTrueTypeFontDataLoader: () async =>
              Uint8List.fromList(veraBytes),
        ),
      );

      final defaultFont = await context.createDefaultTrueTypeOrFallbackFont(
        size: 12.0,
        hinting: 'normal',
        dpiScale: 2.0,
        defaultFilter: LoveGraphicsDefaultFilter.standard,
      );
      final rasterizerFont = LoveRasterizer.trueType(
        size: 12.0,
        hinting: 'normal',
        dpiScale: 2.0,
        sourceBytes: veraBytes,
      ).toLoveFont(defaultFilter: LoveGraphicsDefaultFilter.standard);

      expect(defaultFont.height, closeTo(rasterizerFont.height, 1e-9));
      expect(defaultFont.ascent, closeTo(rasterizerFont.ascent, 1e-9));
      expect(defaultFont.descent, closeTo(rasterizerFont.descent, 1e-9));
      expect(
        defaultFont.syntheticTabAdvance,
        closeTo(rasterizerFont.syntheticTabAdvance!, 1e-9),
      );
      expect(
        defaultFont.missingGlyphAdvance,
        closeTo(rasterizerFont.missingGlyphAdvance!, 1e-9),
      );
      expect(
        defaultFont.measureWidth('WAV\t🙂'),
        closeTo(rasterizerFont.measureWidth('WAV\t🙂'), 1e-9),
      );
    });
  });
}
