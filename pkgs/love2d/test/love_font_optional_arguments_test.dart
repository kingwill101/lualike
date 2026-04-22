import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font optional arguments', () {
    test('true type constructors accept nil hinting before dpiscale', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final rasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[12, null, 2.0],
      );
      expect(await luaCallMethod(rasterizer, 'getHeight'), 24);

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[12, null, 2.0],
      );
      expect(await luaCallMethod(font, 'getDPIScale'), 2.0);

      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final fileData = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[veraBytes, 'Vera.ttf'],
      );
      final sourceRasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[fileData, 12, null, 2.0],
      );
      expect(await luaCallMethod(sourceRasterizer, 'getGlyphCount'), 268);
      expect(
        await luaCallMethod(sourceRasterizer, 'getHeight'),
        greaterThan(24),
      );

      final nilSizeRasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[fileData, null, 'mono', 2.0],
      );
      final defaultSizeRasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[fileData, 12, 'mono', 2.0],
      );
      expect(
        await luaCallMethod(nilSizeRasterizer, 'getHeight'),
        await luaCallMethod(defaultSizeRasterizer, 'getHeight'),
      );
      expect(
        await luaCallMethod(nilSizeRasterizer, 'getGlyphCount'),
        await luaCallMethod(defaultSizeRasterizer, 'getGlyphCount'),
      );
    });

    test(
      'image font constructors accept nil extraspacing before later arguments',
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
          <Object?>[imageData, 'ABC', null, 2.0],
        );
        expect(await luaCallMethod(rasterizer, 'getAdvance'), 3);

        final rasterizerFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(await luaCallMethod(rasterizerFont, 'getDPIScale'), 2.0);
        expect(
          await luaCallMethod(rasterizerFont, 'getWidth', const <Object?>[
            'ABC',
          ]),
          3.0,
        );

        final imageFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageData, 'ABC', null],
        );
        expect(
          await luaCallMethod(imageFont, 'getWidth', const <Object?>['ABC']),
          6.0,
        );
      },
    );

    test('bmfont constructors accept nil dpiscale', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final definition = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
      );
      final imageData = await luaCall(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 6],
      );

      final rasterizer = await luaCall(
        runtime,
        const ['love', 'font', 'newBMFontRasterizer'],
        <Object?>[definition, imageData, null],
      );
      expect(await luaCallMethod(rasterizer, 'getGlyphCount'), 2);

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[definition, imageData, null],
      );
      expect(await luaCallMethod(font, 'getDPIScale'), 1.0);
      expect(await luaCallMethod(font, 'getHeight'), 6.0);
    });

    test(
      'graphics.newFont treats nil source size like the single-argument auto path',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final sourceDir = await love2dResourceDirectory();
        expect(
          LoveFilesystemState.of(runtime).setSource(sourceDir.path),
          isTrue,
        );

        final autoFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['Vera.ttf'],
        );
        final nilSizeFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>['Vera.ttf', null, 2.0],
        );

        expect(
          await luaCallMethod(nilSizeFont, 'getHeight'),
          await luaCallMethod(autoFont, 'getHeight'),
        );
        expect(
          await luaCallMethod(nilSizeFont, 'getDPIScale'),
          await luaCallMethod(autoFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(nilSizeFont, 'getWidth', const <Object?>['AV']),
          await luaCallMethod(autoFont, 'getWidth', const <Object?>['AV']),
        );
      },
    );

    test(
      'graphics.setNewFont treats nil source size like the single-argument auto path',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final sourceDir = await love2dResourceDirectory();
        expect(
          LoveFilesystemState.of(runtime).setSource(sourceDir.path),
          isTrue,
        );

        final autoFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['Vera.ttf'],
        );
        final nilSizeFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          <Object?>['Vera.ttf', null, 'mono', 2.0],
        );
        final currentFont = await luaCall(runtime, const [
          'love',
          'graphics',
          'getFont',
        ]);

        expect(
          await luaCallMethod(nilSizeFont, 'getHeight'),
          await luaCallMethod(autoFont, 'getHeight'),
        );
        expect(
          await luaCallMethod(nilSizeFont, 'getDPIScale'),
          await luaCallMethod(autoFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(nilSizeFont, 'getWidth', const <Object?>['AV']),
          await luaCallMethod(autoFont, 'getWidth', const <Object?>['AV']),
        );
        expect(
          await luaCallMethod(currentFont, 'getHeight'),
          await luaCallMethod(autoFont, 'getHeight'),
        );
        expect(
          await luaCallMethod(currentFont, 'getDPIScale'),
          await luaCallMethod(autoFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethod(currentFont, 'getWidth', const <Object?>['AV']),
          await luaCallMethod(autoFont, 'getWidth', const <Object?>['AV']),
        );
      },
    );
  });
}

const String _bmFontDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=2
char id=65 x=0 y=0 width=3 height=6 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15
char id=66 x=3 y=0 width=2 height=6 xoffset=0 yoffset=0 xadvance=3 page=0 chnl=15
kernings count=1
kerning first=65 second=66 amount=-1
''';
