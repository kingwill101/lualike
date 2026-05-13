import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('default graphics font', () {
    test('getFont lazily loads and restores the cached default font', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
      );

      final firstFont = await luaCall(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);

      expect(await luaCallMethod(firstFont, 'getHeight'), 14.0);
      expect(
        await luaCallMethod(firstFont, 'hasGlyphs', const <Object?>['LuaLike']),
        isTrue,
      );

      await luaCallMethod(firstFont, 'setLineHeight', const <Object?>[1.5]);
      await luaCall(runtime, const ['love', 'graphics', 'reset']);

      final secondFont = await luaCall(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);

      expect(await luaCallMethod(secondFont, 'getLineHeight'), 1.5);
      expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 1);
    });

    test(
      'setNewFont keeps the default graphics font counted in stats',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
        );

        expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 1);

        await luaCall(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          const <Object?>[18.0],
        );

        expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 2);
      },
    );

    test(
      'repeated numeric newFont calls use the cached default font path synchronously',
      () async {
        var loadCount = 0;
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            defaultTrueTypeFontLoader:
                ({
                  required double size,
                  required String hinting,
                  required double dpiScale,
                  required LoveGraphicsDefaultFilter defaultFilter,
                }) async {
                  loadCount++;
                  return LoveFont(
                    size: size,
                    family: 'CachedDefaultFont',
                    fontType: LoveFont.trueTypeFontType,
                    hinting: hinting,
                    dpiScale: dpiScale,
                    heightOverride: size + 4,
                    filter: defaultFilter,
                    measureWidthCallback: (text) => text.runes.length * 7.0,
                  );
                },
          ),
        );

        final rawNewFont = luaRawFunction(runtime, const [
          'love',
          'graphics',
          'newFont',
        ]);

        final firstResult = rawNewFont.call(const <Object?>[18.0]);
        expect(firstResult, isA<Future<Object?>>());
        final firstFont = await luaResolveCallResult(firstResult);

        final secondResult = rawNewFont.call(const <Object?>[18.0]);
        expect(secondResult, isNot(isA<Future>()));
        final secondFont = luaUnwrapValue(secondResult);

        expect(loadCount, 1);
        expect(
          await luaCallMethod(firstFont, 'getHeight'),
          await luaCallMethod(secondFont, 'getHeight'),
        );
      },
    );

    test(
      'print uses the current explicit font without yielding once it is loaded',
      () async {
        var loadCount = 0;
        final host = LoveHeadlessHost(
          defaultTrueTypeFontLoader:
              ({
                required double size,
                required String hinting,
                required double dpiScale,
                required LoveGraphicsDefaultFilter defaultFilter,
              }) async {
                loadCount++;
                return LoveFont(
                  size: size,
                  family: 'PrintFont',
                  fontType: LoveFont.trueTypeFontType,
                  hinting: hinting,
                  dpiScale: dpiScale,
                  heightOverride: size + 2,
                  filter: defaultFilter,
                  measureWidthCallback: (text) => text.runes.length * 6.0,
                );
              },
        );
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: host);

        await luaCall(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          const <Object?>[18.0],
        );

        host.graphics.beginFrame();
        final rawPrint = luaRawFunction(runtime, const [
          'love',
          'graphics',
          'print',
        ]);
        final printResult = rawPrint.call(const <Object?>['LuaLike', 4.0, 8.0]);

        expect(printResult, isNot(isA<Future>()));
        expect(loadCount, 1);
        expect(host.graphics.commands, hasLength(1));
      },
    );

    test('print and printf lazily use the cached default font', () async {
      final host = LoveHeadlessHost(
        defaultTrueTypeFontDataLoader: _loadVeraBytes,
      );
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: host);

      host.graphics.beginFrame();
      await luaCall(runtime, const ['love', 'graphics', 'reset']);
      await luaCall(
        runtime,
        const ['love', 'graphics', 'print'],
        const <Object?>['Wi', 4.0, 8.0],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'printf'],
        const <Object?>['Wi', 4.0, 8.0, 120.0, 'left'],
      );

      expect(host.graphics.commands, hasLength(2));

      final printCommand = host.graphics.commands[0] as LoveTextCommand;
      final printfCommand = host.graphics.commands[1] as LoveTextCommand;

      expect(printCommand.font.height, 14.0);
      expect(printfCommand.font.height, 14.0);
      expect(
        printCommand.font.measureWidth('W'),
        greaterThan(printCommand.font.measureWidth('i')),
      );
      expect(
        printfCommand.font.measureWidth('W'),
        printCommand.font.measureWidth('W'),
      );
      expect(
        printCommand.font.hasGlyphValues(const <Object?>['LuaLike']),
        isTrue,
      );
      expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 1);
    });
  });
}

Future<Uint8List> _loadVeraBytes() async {
  final bytes = await (await love2dVeraFontFile()).readAsBytes();
  return Uint8List.fromList(bytes);
}
