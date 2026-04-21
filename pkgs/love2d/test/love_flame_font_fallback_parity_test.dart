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

  testWidgets(
    'LoveFlameHost keeps tab and missing-glyph metrics after setFallbacks',
    (tester) async {
      final fonts = await tester
          .runAsync<({LoveFont primary, LoveFont fallback})>(() async {
            final host = LoveFlameHost<World>(
              game: FlameGame<World>(world: World()),
            );

            final primary = await host.loadDefaultTrueTypeFont(
              size: 16.0,
              hinting: 'normal',
              dpiScale: 1.0,
              defaultFilter: LoveGraphicsDefaultFilter.standard,
            );
            final fallback = await host.loadDefaultTrueTypeFont(
              size: 16.0,
              hinting: 'normal',
              dpiScale: 1.0,
              defaultFilter: LoveGraphicsDefaultFilter.standard,
            );

            return (primary: primary!, fallback: fallback!);
          });
      expect(fonts, isNotNull);
      final primary = fonts!.primary;
      final fallback = fonts.fallback;

      expect(primary.hasGlyphValues(const <Object?>['\t']), isFalse);
      expect(primary.hasGlyphValues(const <Object?>['🙂']), isFalse);
      expect(primary.syntheticTabAdvance, isNotNull);
      expect(primary.missingGlyphAdvance, isNotNull);

      final spacesWidth = primary.measureWidth('    ');
      final tabWidthBeforeFallbacks = primary.measureWidth('\t');
      final missingWidthBeforeFallbacks = primary.measureWidth('🙂');

      expect(tabWidthBeforeFallbacks, closeTo(spacesWidth, 1e-9));
      expect(missingWidthBeforeFallbacks, greaterThan(0.0));

      primary.setFallbacks(<LoveFont>[fallback]);

      expect(primary.measureWidth('\t'), closeTo(spacesWidth, 1e-9));
      expect(
        primary.measureWidth('A\tA'),
        closeTo(primary.measureWidth('A    A'), 1e-9),
      );
      expect(
        primary.measureWidth('🙂'),
        closeTo(missingWidthBeforeFallbacks, 1e-9),
      );
    },
  );
}
