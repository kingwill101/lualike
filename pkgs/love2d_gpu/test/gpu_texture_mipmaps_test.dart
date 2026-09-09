import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_texture_cache.dart';

void main() {
  group('gpuMipLevelsForLoveImage', () {
    test('keeps the base level when uploads are disabled or unsupported', () {
      final image = _mippedImage();

      expect(
        gpuMipLevelsForLoveImage(
          image,
          uploadsEnabled: false,
          manuallyMippedTexturesSupported: true,
          maxMipLevels: 3,
        ),
        hasLength(1),
      );
      expect(
        gpuMipLevelsForLoveImage(
          image,
          uploadsEnabled: true,
          manuallyMippedTexturesSupported: false,
          maxMipLevels: 3,
        ),
        hasLength(1),
      );
    });

    test('uses only the GPU-supported valid mip prefix', () {
      final image = _mippedImage();

      final levels = gpuMipLevelsForLoveImage(
        image,
        uploadsEnabled: true,
        manuallyMippedTexturesSupported: true,
        maxMipLevels: 2,
      );

      expect(levels, hasLength(2));
      expect((levels[0].width, levels[0].height), (4, 4));
      expect((levels[1].width, levels[1].height), (2, 2));
    });

    test('truncates malformed mip dimensions before upload', () {
      final base = LoveImageData(width: 4, height: 4);
      final image = LoveImage(
        source: 'malformed-mips',
        width: 4,
        height: 4,
        mipmapCount: 3,
        mipmapFilter: LoveGraphicsFilterMode.linear,
        imageDataMipmaps: <LoveImageData>[
          base,
          LoveImageData(width: 3, height: 2),
          LoveImageData(width: 1, height: 1),
        ],
      );

      expect(
        gpuMipLevelsForLoveImage(
          image,
          uploadsEnabled: true,
          manuallyMippedTexturesSupported: true,
          maxMipLevels: 3,
        ),
        hasLength(1),
      );
    });
  });
}

LoveImage _mippedImage() {
  final levels = LoveImageData(width: 4, height: 4).generateMipmaps();
  return LoveImage(
    source: 'mipped-image',
    width: 4,
    height: 4,
    mipmapCount: levels.length,
    mipmapFilter: LoveGraphicsFilterMode.linear,
    imageDataMipmaps: levels,
  );
}
