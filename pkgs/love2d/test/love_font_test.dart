import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font bindings', () {
    test(
      'newTrueTypeRasterizer exposes LOVE object semantics for metrics',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12, 'light', 2.0],
        );

        expect(await luaCallMethodList(rasterizer, 'type'), 'Rasterizer');
        expect(
          await luaCallMethodList(rasterizer, 'typeOf', const <Object?>[
            'Object',
          ]),
          isTrue,
        );
        expect(await luaCallMethodList(rasterizer, 'getHeight'), 24);
        expect(await luaCallMethodList(rasterizer, 'getAdvance'), 14);
        expect(await luaCallMethodList(rasterizer, 'getAscent'), 19);
        expect(await luaCallMethodList(rasterizer, 'getDescent'), 5);
        expect(await luaCallMethodList(rasterizer, 'getLineHeight'), 30);
      },
    );

    test('default font constructors use LOVE default size 12', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final defaultRasterizer = await luaCallList(runtime, const [
        'love',
        'font',
        'newTrueTypeRasterizer',
      ]);
      expect(await luaCallMethodList(defaultRasterizer, 'getHeight'), 12);

      final defaultGraphicsFont = await luaCallList(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);
      expect(await luaCallMethodList(defaultGraphicsFont, 'getHeight'), 12.0);
      expect(
        await luaCallMethodList(defaultGraphicsFont, 'getLineHeight'),
        1.0,
      );
    });

    test(
      'newImageRasterizer exposes image glyph metrics and missing glyphs',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 1, 1.0],
        );

        expect(await luaCallMethodList(rasterizer, 'getGlyphCount'), 3);
        expect(await luaCallMethodList(rasterizer, 'getAdvance'), 4);
        expect(await luaCallMethodList(rasterizer, 'getHeight'), 6);
        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>[
            'AC',
          ]),
          isTrue,
        );
        expect(
          await luaCallMethodList(rasterizer, 'hasGlyphs', const <Object?>[
            'AZ',
          ]),
          isFalse,
        );

        final glyphData = await luaCallMethodList(rasterizer, 'getGlyphData', [
          'B',
        ]);
        expect(await luaCallMethodList(glyphData, 'getFormat'), 'rgba8');
        expect(await luaCallMethodList(glyphData, 'getDimensions'), <Object?>[
          1,
          6,
        ]);
        expect(await luaCallMethodList(glyphData, 'getBearing'), <Object?>[
          0,
          0,
        ]);
        expect(await luaCallMethodList(glyphData, 'getBoundingBox'), <Object?>[
          0,
          6,
          1,
          -6,
        ]);
        expect(await luaCallMethodList(glyphData, 'getSize'), 24);

        final missing = await luaCallMethodList(rasterizer, 'getGlyphData', [
          'Z',
        ]);
        expect(await luaCallMethodList(missing, 'getDimensions'), <Object?>[
          0,
          6,
        ]);
        expect(await luaCallMethodList(missing, 'getFormat'), 'rgba8');
      },
    );

    test('image font constructors reject non-rgba8 image data', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await luaCallList(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[2, 2, 'r8'],
      );

      await expectLater(
        () => luaCallList(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'A', 0, 1.0],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('32-bit RGBA images are supported in Image Fonts'),
          ),
        ),
      );

      await expectLater(
        () => luaCallList(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageData, 'A', 0],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('32-bit RGBA images are supported in Image Fonts'),
          ),
        ),
      );
    });

    test(
      'newRasterizer uses true type overloads and graphics accepts rasterizers',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageRasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[
            await luaCallList(
              runtime,
              const ['love', 'image', 'newImageData'],
              <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
            ),
            'XYZ',
            0,
            1.0,
          ],
        );
        expect(await luaCallMethodList(imageRasterizer, 'getGlyphCount'), 3);

        final imageFont = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[imageRasterizer],
        );
        expect(
          await luaCallMethodList(imageFont, 'getWidth', const <Object?>['XY']),
          3.0,
        );
        expect(await luaCallMethodList(imageFont, 'getDPIScale'), 1.0);

        final trueTypeRasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          const <Object?>[18, 'mono', 1.0],
        );
        expect(await luaCallMethodList(trueTypeRasterizer, 'getHeight'), 18);

        final trueTypeFont = await luaCallList(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          <Object?>[trueTypeRasterizer],
        );
        expect(await luaCallMethodList(trueTypeFont, 'getHeight'), 18.0);
        expect(await luaCallMethodList(trueTypeFont, 'getDPIScale'), 1.0);
      },
    );

    test(
      'font bindings accept LuaString inputs for glyphs and filenames',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/imagefont.png': LoveImageData.fromRgbaBytes(
                width: 9,
                height: 6,
                bytes: imageFontStripBytes(),
              ).encode('png'),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final imageRasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[
            LuaString.fromDartString('assets/fonts/imagefont.png'),
            LuaString.fromDartString('XYZ'),
            0,
            1.0,
          ],
        );
        expect(await luaCallMethodList(imageRasterizer, 'getGlyphCount'), 3);

        final glyphData = await luaCallList(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[imageRasterizer, LuaString.fromDartString('X')],
        );
        expect(await luaCallMethodList(glyphData, 'getGlyphString'), 'X');
      },
    );

    test(
      'graphics.newFont uses host-backed true type fonts when available',
      () async {
        final host = LoveHeadlessHost(
          trueTypeFontLoader:
              (
                source, {
                required Uint8List bytes,
                required double size,
                required String hinting,
                required double dpiScale,
                required LoveGraphicsDefaultFilter defaultFilter,
              }) async {
                expect(source, 'Vera.ttf');
                expect(bytes, isNotEmpty);
                expect(size, 16.0);
                expect(hinting, 'normal');
                expect(dpiScale, 1.0);
                return LoveFont(
                  size: size,
                  family: 'HostBackedVera',
                  source: source,
                  fontType: LoveFont.trueTypeFontType,
                  hinting: hinting,
                  dpiScale: dpiScale,
                  heightOverride: 19.0,
                  ascentOverride: 14.0,
                  descentOverride: 5.0,
                  filter: defaultFilter,
                  measureWidthCallback: (text) => switch (text) {
                    'WWW' => 33.0,
                    'iii' => 12.0,
                    _ => text.runes.length * 7.0,
                  },
                  wrapTextCallback: (text, wrapLimit) {
                    if (wrapLimit >= 40.0) {
                      return (width: 21.0, lines: <String>[text]);
                    }
                    return (width: 14.0, lines: <String>['ab', 'cd']);
                  },
                );
              },
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final sourceDir = await love2dResourceDirectory();
        expect(
          LoveFilesystemState.of(runtime).setSource(sourceDir.path),
          isTrue,
        );

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['Vera.ttf', 16],
        );

        expect(await luaCallMethodList(font, 'getHeight'), 19.0);
        expect(await luaCallMethodList(font, 'getAscent'), 14.0);
        expect(await luaCallMethodList(font, 'getDescent'), 5.0);
        expect(
          await luaCallMethodList(font, 'getWidth', const <Object?>['WWW']),
          33.0,
        );
        expect(
          await luaCallMethodList(font, 'getWidth', const <Object?>['iii']),
          12.0,
        );
        expect(
          await luaCallMethodList(font, 'getWrap', const <Object?>[
            'abcd',
            10.0,
          ]),
          <Object?>[
            14.0,
            <Object?, Object?>{1: 'ab', 2: 'cd'},
          ],
        );
      },
    );

    test(
      'graphics.newFont uses host-backed default true type fonts when available',
      () async {
        final host = LoveHeadlessHost(
          defaultTrueTypeFontLoader:
              ({
                required double size,
                required String hinting,
                required double dpiScale,
                required LoveGraphicsDefaultFilter defaultFilter,
              }) async {
                expect(size, 20.0);
                expect(hinting, 'light');
                expect(dpiScale, 2.0);
                return LoveFont(
                  size: size,
                  family: 'HostBackedDefaultVera',
                  fontType: LoveFont.trueTypeFontType,
                  hinting: hinting,
                  dpiScale: dpiScale,
                  heightOverride: 24.0,
                  ascentOverride: 18.0,
                  descentOverride: 6.0,
                  filter: defaultFilter,
                  measureWidthCallback: (text) => text.runes.length * 8.0,
                );
              },
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[20, 'light', 2.0],
        );

        expect(await luaCallMethodList(font, 'getHeight'), 24.0);
        expect(await luaCallMethodList(font, 'getAscent'), 18.0);
        expect(await luaCallMethodList(font, 'getDescent'), 6.0);
        expect(
          await luaCallMethodList(font, 'getWidth', const <Object?>['Lua']),
          24.0,
        );
        expect(await luaCallMethodList(font, 'getDPIScale'), 2.0);
      },
    );

    test(
      'graphics.newFont loads mounted filename sources through LOVE filesystem',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Body.ttf': veraBytes,
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
        );
        final rasterizer = await luaCallList(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
        );
        final baselineFont = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        expect(await luaCallMethodList(font, 'type'), 'Font');
        expect(
          await luaCallMethodList(font, 'getDPIScale'),
          await luaCallMethodList(baselineFont, 'getDPIScale'),
        );
        expect(
          await luaCallMethodList(font, 'getHeight'),
          await luaCallMethodList(baselineFont, 'getHeight'),
        );
        expect(
          await luaCallMethodList(font, 'getAscent'),
          await luaCallMethodList(baselineFont, 'getAscent'),
        );
        expect(
          await luaCallMethodList(font, 'getDescent'),
          await luaCallMethodList(baselineFont, 'getDescent'),
        );
        final wideWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['W'])
                as num;
        final narrowWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['i'])
                as num;
        expect(wideWidth, greaterThan(narrowWidth));
        final aWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['A'])
                as num;
        final vWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['V'])
                as num;
        final avWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['AV'])
                as num;
        final avKerning =
            await luaCallMethodList(font, 'getKerning', const <Object?>[
                  'A',
                  'V',
                ])
                as num;
        expect(avKerning, lessThan(0));
        expect(avWidth, lessThan(aWidth + vWidth));
      },
    );

    test(
      'graphics.newFont without size uses LOVE default size 12 for mounted files',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Body.ttf': veraBytes,
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf'],
        );

        expect(await luaCallMethodList(font, 'getHeight'), 14.0);
        expect(await luaCallMethodList(font, 'getAscent'), 11.0);
        expect(await luaCallMethodList(font, 'getDescent'), 3.0);
        expect(await luaCallMethodList(font, 'getLineHeight'), 1.0);
        final wideWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['W'])
                as num;
        final narrowWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['i'])
                as num;
        expect(wideWidth, greaterThan(narrowWidth));
        final aWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['A'])
                as num;
        final vWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['V'])
                as num;
        final avWidth =
            await luaCallMethodList(font, 'getWidth', const <Object?>['AV'])
                as num;
        final avKerning =
            await luaCallMethodList(font, 'getKerning', const <Object?>[
                  'A',
                  'V',
                ])
                as num;
        expect(avKerning, lessThan(0));
        expect(avWidth, lessThan(aWidth + vWidth));
      },
    );

    test('graphics.newFont rejects unresolved filename sources', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      await expectLater(
        () => luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Missing.ttf', 16],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'Could not open file assets/fonts/Missing.ttf. Does not exist.',
            ),
          ),
        ),
      );
    });

    test(
      'font line height does not change Font:getHeight and scales Text height',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[24],
        );

        expect(await luaCallMethodList(font, 'getHeight'), 24.0);
        expect(await luaCallMethodList(font, 'getLineHeight'), 1.0);

        await luaCallMethodList(font, 'setLineHeight', const <Object?>[1.25]);

        expect(await luaCallMethodList(font, 'getHeight'), 24.0);
        expect(await luaCallMethodList(font, 'getLineHeight'), 1.25);

        final text = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'hello'],
        );
        expect(await luaCallMethodList(text, 'getHeight'), 30.0);
      },
    );

    test('font hasGlyphs requires at least one glyph argument', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[14],
      );

      expect(
        await luaCallMethodList(font, 'hasGlyphs', const <Object?>['LuaLike']),
        isTrue,
      );
      expect(
        await luaCallMethodList(font, 'hasGlyphs', const <Object?>['']),
        isFalse,
      );
      await expectLater(
        () => luaCallMethodList(font, 'hasGlyphs'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Font:hasGlyphs expected a number at argument 2'),
          ),
        ),
      );
    });

    test('graphics.newImageFont uses spacer-delimited glyph widths', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await luaCallList(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
      );
      final font = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1],
      );

      expect(
        await luaCallMethodList(font, 'getWidth', const <Object?>['ABC']),
        9.0,
      );
      expect(
        await luaCallMethodList(font, 'getWidth', const <Object?>['BA']),
        5.0,
      );
    });

    test('image font fallbacks contribute missing glyph widths', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await luaCallList(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
      );
      final primary = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1],
      );
      final fallback = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'XYZ', 1],
      );

      await luaCallMethodList(primary, 'setFallbacks', <Object?>[fallback]);

      final primaryA =
          await luaCallMethodList(primary, 'getWidth', const <Object?>['A'])
              as num;
      final fallbackX =
          await luaCallMethodList(fallback, 'getWidth', const <Object?>['X'])
              as num;

      expect(
        await luaCallMethodList(primary, 'getWidth', const <Object?>['AX']),
        closeTo(primaryA + fallbackX, 1e-9),
      );
      expect(
        await luaCallMethodList(primary, 'hasGlyphs', const <Object?>['AX']),
        isTrue,
      );
    });
  });
}
