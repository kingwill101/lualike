import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.font bindings', () {
    test(
      'newTrueTypeRasterizer exposes LOVE object semantics for metrics',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12, 'light', 2.0],
        );

        expect(await _callMethod(rasterizer, 'type'), 'Rasterizer');
        expect(
          await _callMethod(rasterizer, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(await _callMethod(rasterizer, 'getHeight'), 24);
        expect(await _callMethod(rasterizer, 'getAdvance'), 14);
        expect(await _callMethod(rasterizer, 'getAscent'), 19);
        expect(await _callMethod(rasterizer, 'getDescent'), 5);
        expect(await _callMethod(rasterizer, 'getLineHeight'), 30);
      },
    );

    test('default font constructors use LOVE default size 12', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final defaultRasterizer = await _call(runtime, const [
        'love',
        'font',
        'newTrueTypeRasterizer',
      ]);
      expect(await _callMethod(defaultRasterizer, 'getHeight'), 12);

      final defaultGraphicsFont = await _call(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);
      expect(await _callMethod(defaultGraphicsFont, 'getHeight'), 12.0);
      expect(await _callMethod(defaultGraphicsFont, 'getLineHeight'), 1.0);
    });

    test(
      'newImageRasterizer exposes image glyph metrics and missing glyphs',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
        );
        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 1, 1.0],
        );

        expect(await _callMethod(rasterizer, 'getGlyphCount'), 3);
        expect(await _callMethod(rasterizer, 'getAdvance'), 4);
        expect(await _callMethod(rasterizer, 'getHeight'), 6);
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>['AC']),
          isTrue,
        );
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>['AZ']),
          isFalse,
        );

        final glyphData = await _callMethod(rasterizer, 'getGlyphData', ['B']);
        expect(await _callMethod(glyphData, 'getFormat'), 'rgba8');
        expect(await _callMethod(glyphData, 'getDimensions'), <Object?>[1, 6]);
        expect(await _callMethod(glyphData, 'getBearing'), <Object?>[0, 0]);
        expect(await _callMethod(glyphData, 'getBoundingBox'), <Object?>[
          0,
          6,
          1,
          -6,
        ]);
        expect(await _callMethod(glyphData, 'getSize'), 24);

        final missing = await _callMethod(rasterizer, 'getGlyphData', ['Z']);
        expect(await _callMethod(missing, 'getDimensions'), <Object?>[0, 6]);
        expect(await _callMethod(missing, 'getFormat'), 'rgba8');
      },
    );

    test('image font constructors reject non-rgba8 image data', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[2, 2, 'r8'],
      );

      await expectLater(
        () => _call(
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
        () => _call(
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

        final imageRasterizer = await _call(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[
            await _call(
              runtime,
              const ['love', 'image', 'newImageData'],
              <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
            ),
            'XYZ',
            0,
            1.0,
          ],
        );
        expect(await _callMethod(imageRasterizer, 'getGlyphCount'), 3);

        final imageFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[imageRasterizer],
        );
        expect(
          await _callMethod(imageFont, 'getWidth', const <Object?>['XY']),
          3.0,
        );
        expect(await _callMethod(imageFont, 'getDPIScale'), 1.0);

        final trueTypeRasterizer = await _call(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          const <Object?>[18, 'mono', 1.0],
        );
        expect(await _callMethod(trueTypeRasterizer, 'getHeight'), 18);

        final trueTypeFont = await _call(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          <Object?>[trueTypeRasterizer],
        );
        expect(await _callMethod(trueTypeFont, 'getHeight'), 18.0);
        expect(await _callMethod(trueTypeFont, 'getDPIScale'), 1.0);
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
                bytes: _imageFontStripBytes(),
              ).encode('png'),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final imageRasterizer = await _call(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[
            LuaString.fromDartString('assets/fonts/imagefont.png'),
            LuaString.fromDartString('XYZ'),
            0,
            1.0,
          ],
        );
        expect(await _callMethod(imageRasterizer, 'getGlyphCount'), 3);

        final glyphData = await _call(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[imageRasterizer, LuaString.fromDartString('X')],
        );
        expect(await _callMethod(glyphData, 'getGlyphString'), 'X');
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

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['Vera.ttf', 16],
        );

        expect(await _callMethod(font, 'getHeight'), 19.0);
        expect(await _callMethod(font, 'getAscent'), 14.0);
        expect(await _callMethod(font, 'getDescent'), 5.0);
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['WWW']),
          33.0,
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['iii']),
          12.0,
        );
        expect(
          await _callMethod(font, 'getWrap', const <Object?>['abcd', 10.0]),
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

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[20, 'light', 2.0],
        );

        expect(await _callMethod(font, 'getHeight'), 24.0);
        expect(await _callMethod(font, 'getAscent'), 18.0);
        expect(await _callMethod(font, 'getDescent'), 6.0);
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['Lua']),
          24.0,
        );
        expect(await _callMethod(font, 'getDPIScale'), 2.0);
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

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
        );
        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
        );
        final baselineFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        expect(await _callMethod(font, 'type'), 'Font');
        expect(
          await _callMethod(font, 'getDPIScale'),
          await _callMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(font, 'getHeight'),
          await _callMethod(baselineFont, 'getHeight'),
        );
        expect(
          await _callMethod(font, 'getAscent'),
          await _callMethod(baselineFont, 'getAscent'),
        );
        expect(
          await _callMethod(font, 'getDescent'),
          await _callMethod(baselineFont, 'getDescent'),
        );
        final wideWidth =
            await _callMethod(font, 'getWidth', const <Object?>['W']) as num;
        final narrowWidth =
            await _callMethod(font, 'getWidth', const <Object?>['i']) as num;
        expect(wideWidth, greaterThan(narrowWidth));
        final aWidth =
            await _callMethod(font, 'getWidth', const <Object?>['A']) as num;
        final vWidth =
            await _callMethod(font, 'getWidth', const <Object?>['V']) as num;
        final avWidth =
            await _callMethod(font, 'getWidth', const <Object?>['AV']) as num;
        final avKerning =
            await _callMethod(font, 'getKerning', const <Object?>['A', 'V'])
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

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf'],
        );

        expect(await _callMethod(font, 'getHeight'), 14.0);
        expect(await _callMethod(font, 'getAscent'), 11.0);
        expect(await _callMethod(font, 'getDescent'), 3.0);
        expect(await _callMethod(font, 'getLineHeight'), 1.0);
        final wideWidth =
            await _callMethod(font, 'getWidth', const <Object?>['W']) as num;
        final narrowWidth =
            await _callMethod(font, 'getWidth', const <Object?>['i']) as num;
        expect(wideWidth, greaterThan(narrowWidth));
        final aWidth =
            await _callMethod(font, 'getWidth', const <Object?>['A']) as num;
        final vWidth =
            await _callMethod(font, 'getWidth', const <Object?>['V']) as num;
        final avWidth =
            await _callMethod(font, 'getWidth', const <Object?>['AV']) as num;
        final avKerning =
            await _callMethod(font, 'getKerning', const <Object?>['A', 'V'])
                as num;
        expect(avKerning, lessThan(0));
        expect(avWidth, lessThan(aWidth + vWidth));
      },
    );

    test('graphics.newFont rejects unresolved filename sources', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      await expectLater(
        () => _call(
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

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[24],
        );

        expect(await _callMethod(font, 'getHeight'), 24.0);
        expect(await _callMethod(font, 'getLineHeight'), 1.0);

        await _callMethod(font, 'setLineHeight', const <Object?>[1.25]);

        expect(await _callMethod(font, 'getHeight'), 24.0);
        expect(await _callMethod(font, 'getLineHeight'), 1.25);

        final text = await _call(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'hello'],
        );
        expect(await _callMethod(text, 'getHeight'), 30.0);
      },
    );

    test('font hasGlyphs requires at least one glyph argument', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[14],
      );

      expect(
        await _callMethod(font, 'hasGlyphs', const <Object?>['LuaLike']),
        isTrue,
      );
      expect(
        await _callMethod(font, 'hasGlyphs', const <Object?>['']),
        isFalse,
      );
      await expectLater(
        () => _callMethod(font, 'hasGlyphs'),
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

      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
      );
      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1],
      );

      expect(await _callMethod(font, 'getWidth', const <Object?>['ABC']), 9.0);
      expect(await _callMethod(font, 'getWidth', const <Object?>['BA']), 5.0);
    });

    test('image font fallbacks contribute missing glyph widths', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
      );
      final primary = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1],
      );
      final fallback = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'XYZ', 1],
      );

      await _callMethod(primary, 'setFallbacks', <Object?>[fallback]);

      final primaryA =
          await _callMethod(primary, 'getWidth', const <Object?>['A']) as num;
      final fallbackX =
          await _callMethod(fallback, 'getWidth', const <Object?>['X']) as num;

      expect(
        await _callMethod(primary, 'getWidth', const <Object?>['AX']),
        closeTo(primaryA + fallbackX, 1e-9),
      );
      expect(
        await _callMethod(primary, 'hasGlyphs', const <Object?>['AX']),
        isTrue,
      );
    });
  });
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

BuiltinFunction _rawMethod(Object? receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = await _resolveRawCallResult(result);
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Future<Object?> _resolveRawCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(wrapped.raw as List<Object?>, growable: false);
  }
  return resolved;
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

Uint8List _imageFontStripBytes() {
  final bytes = Uint8List(9 * 6 * 4);

  void fillColumns(int start, int end, List<int> rgba) {
    for (var row = 0; row < 6; row++) {
      for (var column = start; column < end; column++) {
        final offset = ((row * 9) + column) * 4;
        bytes[offset] = rgba[0];
        bytes[offset + 1] = rgba[1];
        bytes[offset + 2] = rgba[2];
        bytes[offset + 3] = rgba[3];
      }
    }
  }

  fillColumns(1, 3, const <int>[255, 255, 255, 255]);
  fillColumns(4, 5, const <int>[255, 96, 96, 255]);
  fillColumns(6, 9, const <int>[96, 255, 96, 255]);
  return bytes;
}
