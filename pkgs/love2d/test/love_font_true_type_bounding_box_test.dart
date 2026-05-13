import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font true type bounding box parity', () {
    test('source-backed glyph data uses LOVE bounding-box semantics', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final fileData = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[veraBytes, 'Vera.ttf'],
      );
      final rasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[fileData, 16],
      );

      final wideGlyph = await luaCallMethod(
        rasterizer,
        'getGlyphData',
        const <Object?>['W'],
      );
      final narrowGlyph = await luaCallMethod(
        rasterizer,
        'getGlyphData',
        const <Object?>['i'],
      );
      final spaceGlyph = await luaCallMethod(
        rasterizer,
        'getGlyphData',
        const <Object?>[' '],
      );

      await _expectBoundingBoxMatchesMetrics(wideGlyph);
      await _expectBoundingBoxMatchesMetrics(narrowGlyph);
      await _expectBoundingBoxMatchesMetrics(spaceGlyph);

      expect(await luaCallMethod(spaceGlyph, 'getBoundingBox'), <Object?>[
        0,
        0,
        0,
        0,
      ]);
    });
  });
}

Future<void> _expectBoundingBoxMatchesMetrics(Object? glyphData) async {
  final dimensions =
      await luaCallMethod(glyphData, 'getDimensions') as List<Object?>;
  final bearing = await luaCallMethod(glyphData, 'getBearing') as List<Object?>;
  final box = await luaCallMethod(glyphData, 'getBoundingBox') as List<Object?>;

  final width = dimensions[0] as num;
  final height = dimensions[1] as num;
  final bearingX = bearing[0] as num;
  final bearingY = bearing[1] as num;

  expect(box, <Object?>[
    bearingX,
    height - bearingY,
    width,
    bearingY - (height - bearingY),
  ]);
}
