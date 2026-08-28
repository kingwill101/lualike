import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('atlas glyph quad includes LOVE transparent border', () {
    final atlas = _atlas(width: 32, height: 24);
    final quad = loveFontAtlasGlyphQuad(
      atlas: atlas,
      glyph: atlas.glyphs[0x41]!,
      penX: 3,
      lineY: 4,
      baseline: 12,
      dpiScale: 2,
    );

    if (loveFreeTypeGlyphQuadExtrusionEnabled) {
      expect(quad, (
        left: 3.5,
        top: 10.5,
        width: 3,
        height: 3.5,
        sourceX: 9,
        sourceY: 7,
        sourceWidth: 6,
        sourceHeight: 7,
      ));
    } else {
      expect(quad, (
        left: 4,
        top: 11,
        width: 2,
        height: 2.5,
        sourceX: 10,
        sourceY: 8,
        sourceWidth: 4,
        sourceHeight: 5,
      ));
    }
  });

  test('atlas glyph quad does not sample beyond atlas edges', () {
    final atlas = _atlas(width: 14, height: 13, x: 0, y: 0);
    final quad = loveFontAtlasGlyphQuad(
      atlas: atlas,
      glyph: atlas.glyphs[0x41]!,
      penX: 0,
      lineY: 0,
      baseline: 12,
      dpiScale: 1,
    );

    expect(quad.sourceX, 0);
    expect(quad.sourceY, 0);
    expect(quad.sourceX + quad.sourceWidth, lessThanOrEqualTo(14));
    expect(quad.sourceY + quad.sourceHeight, lessThanOrEqualTo(13));
  });
}

LoveFontGlyphAtlas _atlas({
  required int width,
  required int height,
  int x = 10,
  int y = 8,
}) {
  return LoveFontGlyphAtlas(
    image: LoveImage(
      source: 'font-atlas-test',
      width: width,
      height: height,
      imageData: LoveImageData(width: width, height: height),
    ),
    glyphs: <int, LoveFontAtlasGlyph>{
      0x41: LoveFontAtlasGlyph(
        codepoint: 0x41,
        x: x,
        y: y,
        width: 4,
        height: 5,
        advance: 5,
        bearingX: 2,
        bearingY: 10,
      ),
    },
  );
}
