import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font constructor dpi parity', () {
    test('image font constructors accept zero dpiscale', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await luaCall(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
      );
      final rasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newImageRasterizer'],
        <Object?>[imageData, 'ABC', 1, 0.0],
      );
      final rasterizerFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[rasterizer],
      );
      final directFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1, 0.0],
      );

      expect(await luaCallMethod(directFont, 'getDPIScale'), 0.0);
      expect(await luaCallMethod(rasterizerFont, 'getDPIScale'), 0.0);
      expect(
        await luaCallMethod(directFont, 'getHeight'),
        await luaCallMethod(rasterizerFont, 'getHeight'),
      );
      expect(
        await luaCallMethod(directFont, 'getWidth', const <Object?>['ABC']),
        await luaCallMethod(rasterizerFont, 'getWidth', const <Object?>['ABC']),
      );
    });

    test('bmfont constructors accept negative dpiscale', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final definition = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
      );
      final imageData = await luaCall(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 6],
      );
      final rasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newBMFontRasterizer'],
        <Object?>[definition, imageData, -2.0],
      );
      final rasterizerFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[rasterizer],
      );
      final directFont = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[definition, imageData, -2.0],
      );

      expect(await luaCallMethod(directFont, 'getDPIScale'), -2.0);
      expect(await luaCallMethod(rasterizerFont, 'getDPIScale'), -2.0);
      expect(
        await luaCallMethod(directFont, 'getHeight'),
        await luaCallMethod(rasterizerFont, 'getHeight'),
      );
      expect(
        await luaCallMethod(directFont, 'getWidth', const <Object?>['AB']),
        await luaCallMethod(rasterizerFont, 'getWidth', const <Object?>['AB']),
      );
    });
  });
}
