import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font rasterizer constructor parity', () {
    test(
      'graphics.newFont ignores extra arguments when given a Rasterizer',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 0, 2.0],
        );
        final baselineFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer, 99, 'ignored', 8.0],
        );

        expect(
          await luaCallMethod(font, 'getDPIScale'),
          await luaCallMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['ABC']),
          await luaCallMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
      },
    );

    test(
      'graphics.setNewFont ignores extra arguments when given a Rasterizer',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 0, 2.0],
        );
        final baselineFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          <Object?>[rasterizer, 99, 'ignored', 8.0],
        );
        final current = await luaCall(runtime, const [
          'love',
          'graphics',
          'getFont',
        ]);

        expect(
          await luaCallMethod(font, 'getDPIScale'),
          await luaCallMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['ABC']),
          await luaCallMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
        expect(
          await luaCallMethod(current, 'getDPIScale'),
          await luaCallMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(current, 'getWidth', const <Object?>['ABC']),
          await luaCallMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
      },
    );

    test(
      'graphics.newImageFont ignores extra arguments when given a Rasterizer',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final rasterizer = await luaCall(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 0, 2.0],
        );
        final baselineFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[rasterizer],
        );

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[rasterizer, 'ignored', 99],
        );

        expect(
          await luaCallMethod(font, 'getDPIScale'),
          await luaCallMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(font, 'getWidth', const <Object?>['ABC']),
          await luaCallMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
      },
    );
  });
}
