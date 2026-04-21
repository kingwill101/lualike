import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureLove2dDefaultFontAssetAvailable();
  });

  tearDownAll(clearLove2dTestAssetMocks);

  testWidgets('LoveFlameHost loads and measures true type fonts via Flutter', (
    tester,
  ) async {
    final font = await tester.runAsync(() async {
      final host = LoveFlameHost<World>(game: FlameGame<World>(world: World()));
      final bytes = await (await love2dVeraFontFile()).readAsBytes();
      return host.loadTrueTypeFont(
        'Vera.ttf',
        bytes: bytes,
        size: 18.0,
        hinting: 'normal',
        dpiScale: 1.0,
        defaultFilter: LoveGraphicsDefaultFilter.standard,
      );
    });

    expect(font, isNotNull);
    expect(font!.family, isNotEmpty);
    expect(font.height, greaterThan(0.0));
    expect(font.ascent, greaterThan(0.0));
    expect(font.measureWidth('WWW'), greaterThan(font.measureWidth('iii')));
    expect(font.hasGlyphValues(const <Object?>['LuaLike']), isTrue);
    expect(font.hasGlyphValues(const <Object?>['中']), isFalse);
    expect(font.hasGlyphValues(const <Object?>[0x1f642]), isFalse);

    final wrapped = font.wrapText('alpha beta gamma', 60.0);
    expect(wrapped.lines.length, greaterThan(1));
    expect(wrapped.width, lessThanOrEqualTo(60.0));
  });

  testWidgets(
    'LoveFlameHost wrapText follows LOVE trailing-space and carriage-return rules',
    (tester) async {
      final font = await tester.runAsync(() async {
        final host = LoveFlameHost<World>(game: FlameGame<World>(world: World()));
        return host.loadDefaultTrueTypeFont(
          size: 16.0,
          hinting: 'normal',
          dpiScale: 1.0,
          defaultFilter: LoveGraphicsDefaultFilter.standard,
        );
      });

      expect(font, isNotNull);

      final widthA = font!.measureWidth('A');
      final widthB = font.measureWidth('B');
      final widthABWithSpace = font.measureWidth('A B');
      final wrapLimit = (widthA + widthABWithSpace) / 2.0;

      final wrapped = font.wrapText('A B', wrapLimit);
      expect(wrapped.lines, <String>['A ', 'B']);
      expect(wrapped.width, closeTo(math.max(widthA, widthB), 1e-9));

      final carriageReturn = font.wrapText('A\rB', 1000.0);
      expect(carriageReturn.lines, <String>['AB']);
      expect(
        carriageReturn.width,
        closeTo(font.measureWidth('AB'), 1e-9),
      );
    },
  );

  testWidgets('LoveFlameHost loads the bundled default font via Flutter', (
    tester,
  ) async {
    final font = await tester.runAsync(() async {
      final host = LoveFlameHost<World>(game: FlameGame<World>(world: World()));
      return host.loadDefaultTrueTypeFont(
        size: 16.0,
        hinting: 'normal',
        dpiScale: 1.0,
        defaultFilter: LoveGraphicsDefaultFilter.standard,
      );
    });

    expect(font, isNotNull);
    expect(font!.family, isNotEmpty);
    expect(font.source, isNull);
    expect(font.height, greaterThan(0.0));
    expect(font.measureWidth('WWW'), greaterThan(font.measureWidth('iii')));
    expect(font.hasGlyphValues(const <Object?>['LuaLike']), isTrue);
    expect(font.hasGlyphValues(const <Object?>['中']), isFalse);
  });

  testWidgets(
    'LoveFlameHost loads the default font from an injected asset bundle',
    (tester) async {
      final font = await tester.runAsync(() async {
        final bytes = await (await love2dVeraFontFile()).readAsBytes();
        final host = LoveFlameHost<World>(
          game: FlameGame<World>(world: World()),
          assetBundle: _MapAssetBundle(<String, List<int>>{
            love2dDefaultTrueTypeFontAssetPath: bytes,
          }),
        );
        return host.loadDefaultTrueTypeFont(
          size: 16.0,
          hinting: 'normal',
          dpiScale: 1.0,
          defaultFilter: LoveGraphicsDefaultFilter.standard,
        );
      });

      expect(font, isNotNull);
      expect(font!.family, isNotEmpty);
      expect(font.source, isNull);
      expect(font.height, greaterThan(0.0));
      expect(font.hasGlyphValues(const <Object?>['LuaLike']), isTrue);
      expect(font.hasGlyphValues(const <Object?>['中']), isFalse);
    },
  );
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, List<int>> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw StateError('Missing asset: $key');
    }

    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
