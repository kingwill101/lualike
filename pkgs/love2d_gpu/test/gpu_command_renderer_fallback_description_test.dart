import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_command_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  test('describeGpuFallbackCommand includes sprite batch details', () {
    final spriteBatch = LoveSpriteBatch(
      texture: LoveImage(source: 'sprites.png', width: 8, height: 8),
    );
    spriteBatch.add(vm.Matrix4.identity());

    final command = LoveSpriteBatchCommand(
      color: LoveColor.white,
      lineWidth: 1,
      lineStyle: LoveGraphicsLineStyle.smooth,
      lineJoin: LoveGraphicsLineJoin.miter,
      blendMode: LoveGraphicsBlendMode.alpha,
      blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
      colorMask: LoveGraphicsColorMask.all,
      wireframe: false,
      scissor: null,
      shader: null,
      transform: vm.Matrix4.identity(),
      drawTransform: vm.Matrix4.identity(),
      spriteBatch: spriteBatch,
    );

    final description = describeGpuFallbackCommand(
      command,
      reason: 'sprite batch texture is not prewarmed',
    );

    expect(description, contains('LoveSpriteBatchCommand'));
    expect(description, contains('sprites=1'));
    expect(description, contains('textureType=2d'));
    expect(
      description,
      contains('reason=sprite batch texture is not prewarmed'),
    );
  });

  test('describeGpuFallbackCommand includes text details', () {
    final command = LoveTextCommand(
      color: LoveColor.white,
      lineWidth: 1,
      lineStyle: LoveGraphicsLineStyle.smooth,
      lineJoin: LoveGraphicsLineJoin.miter,
      blendMode: LoveGraphicsBlendMode.alpha,
      blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
      colorMask: LoveGraphicsColorMask.all,
      wireframe: false,
      scissor: null,
      shader: null,
      transform: vm.Matrix4.identity(),
      textTransform: vm.Matrix4.identity(),
      font: LoveFont(size: 24, family: 'monospace'),
      spans: const <LoveTextSpan>[LoveTextSpan(text: 'Score: 123')],
      x: 0,
      y: 0,
    );

    final description = describeGpuFallbackCommand(command);

    expect(description, contains('LoveTextCommand'));
    expect(description, contains('spans=1'));
    expect(description, contains('textLength=10'));
    expect(description, contains('preview="Score: 123"'));
  });
}
