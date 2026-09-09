import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_sprite_geometry.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  final image = LoveImage(source: 'atlas.png', width: 128, height: 64);
  final commandTransform = vm.Matrix4.translationValues(11, -7, 0)
    ..rotateZ(0.13);
  final drawTransform = vm.Matrix4.translationValues(3, 5, 0)
    ..scaleByDouble(1.25, 0.75, 1, 1);
  const commandColor = LoveColor(0.8, 0.7, 0.6, 0.5);

  test('direct sprite expansion matches legacy matrix geometry', () {
    final sprites = <LoveSpriteBatchSprite>[
      LoveSpriteBatchSprite(
        transform: vm.Matrix4.translationValues(20, 30, 0)
          ..rotateZ(-0.41)
          ..scaleByDouble(0.5, 1.4, 1, 1),
        color: const LoveColor(0.25, 0.5, 0.75, 0.9),
      ),
      LoveSpriteBatchSprite(
        transform: vm.Matrix4.translationValues(-4, 17, 0)..rotateZ(0.72),
        quad: LoveQuad(
          x: 16,
          y: 8,
          width: 24,
          height: 20,
          textureWidth: 128,
          textureHeight: 64,
        ),
      ),
    ];
    final builder = GpuSpriteGeometryBuilder();
    final direct = builder.buildSprites(
      sprites: sprites,
      image: image,
      commandTransform: commandTransform,
      drawTransform: drawTransform,
      commandColor: commandColor,
    );
    final legacy = buildLegacySpriteVertices(
      sprites: sprites,
      image: image,
      commandTransform: commandTransform,
      drawTransform: drawTransform,
      commandColor: commandColor,
    );

    expect(builder.floatLength, legacy.length);
    for (var i = 0; i < legacy.length; i++) {
      expect(direct[i], closeTo(legacy[i], 1e-5), reason: 'float $i');
    }
  });

  test('direct particle expansion matches legacy matrix geometry', () {
    final particles = <LoveParticleDrawEntry>[
      LoveParticleDrawEntry(
        transform: vm.Matrix4.translationValues(7, 9, 0)
          ..rotateZ(0.33)
          ..scaleByDouble(0.8, 1.1, 1, 1),
        color: const LoveColor(0.2, 0.4, 0.6, 0.8),
      ),
      LoveParticleDrawEntry(
        transform: vm.Matrix4.translationValues(40, -8, 0)..rotateZ(-0.27),
        color: const LoveColor(1, 0.5, 0.25, 0.75),
        quad: LoveQuad(
          x: 32,
          y: 0,
          width: 16,
          height: 32,
          textureWidth: 128,
          textureHeight: 64,
        ),
      ),
    ];
    final builder = GpuSpriteGeometryBuilder();
    final direct = builder.buildParticles(
      particles: particles,
      image: image,
      commandTransform: commandTransform,
      drawTransform: drawTransform,
      commandColor: commandColor,
    );
    final legacy = buildLegacyParticleVertices(
      particles: particles,
      image: image,
      commandTransform: commandTransform,
      drawTransform: drawTransform,
      commandColor: commandColor,
    );

    expect(builder.floatLength, legacy.length);
    for (var i = 0; i < legacy.length; i++) {
      expect(direct[i], closeTo(legacy[i], 1e-5), reason: 'float $i');
    }
  });

  test('direct expansion reuses its typed buffer after reaching capacity', () {
    final builder = GpuSpriteGeometryBuilder();
    final sprites = <LoveSpriteBatchSprite>[
      LoveSpriteBatchSprite(transform: vm.Matrix4.identity()),
    ];
    final first = builder.buildSprites(
      sprites: sprites,
      image: image,
      commandTransform: vm.Matrix4.identity(),
      drawTransform: vm.Matrix4.identity(),
      commandColor: LoveColor.white,
    );
    final second = builder.buildSprites(
      sprites: sprites,
      image: image,
      commandTransform: vm.Matrix4.identity(),
      drawTransform: vm.Matrix4.identity(),
      commandColor: LoveColor.white,
    );

    expect(second, same(first));
    expect(builder.floatLength, 48);
  });
}
