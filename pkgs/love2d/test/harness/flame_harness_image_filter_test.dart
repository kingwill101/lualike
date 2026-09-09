import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart'
    show loveFilterQualityForImage;

void main() {
  group('LOVE image filter quality', () {
    test('keeps linear images without mipmaps bilinear', () {
      final image = LoveImage(source: 'linear', width: 16, height: 16);

      expect(loveFilterQualityForImage(image), ui.FilterQuality.low);
    });

    test('uses mipmapped sampling for linear mip chains', () {
      final image = LoveImage(
        source: 'linear-mipmaps',
        width: 16,
        height: 16,
        mipmapCount: 5,
        mipmapFilter: LoveGraphicsFilterMode.linear,
      );

      expect(loveFilterQualityForImage(image), ui.FilterQuality.medium);
    });

    test('does not enable mipmapped sampling when filtering is disabled', () {
      final image = LoveImage(
        source: 'disabled-mipmaps',
        width: 16,
        height: 16,
        mipmapCount: 5,
      );

      expect(loveFilterQualityForImage(image), ui.FilterQuality.low);
    });

    test('preserves nearest image sampling', () {
      final image = LoveImage(
        source: 'nearest-mipmaps',
        width: 16,
        height: 16,
        mipmapCount: 5,
        filter: const LoveGraphicsDefaultFilter(
          min: LoveGraphicsFilterMode.nearest,
          mag: LoveGraphicsFilterMode.nearest,
        ),
        mipmapFilter: LoveGraphicsFilterMode.linear,
      );

      expect(loveFilterQualityForImage(image), ui.FilterQuality.none);
    });
  });
}
