import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_text_handler.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  test('accepts covered atlas text including formatted alignment', () {
    expect(supportsGpuAtlasTextCommand(_textCommand()), isTrue);
    expect(supportsGpuAtlasTextCommand(_textCommand(limit: 80)), isTrue);
    expect(
      supportsGpuAtlasTextCommand(_textCommand(limit: 80, align: 'center')),
      isTrue,
    );
    expect(
      supportsGpuAtlasTextCommand(_textCommand(limit: 80, align: 'right')),
      isTrue,
    );
  });

  test('keeps unsupported text semantics on the Canvas fallback', () {
    expect(
      supportsGpuAtlasTextCommand(_textCommand(limit: 80, align: 'justify')),
      isFalse,
      reason: 'justified text needs per-space expansion',
    );
    expect(
      supportsGpuAtlasTextCommand(_textCommand(text: 'A中')),
      isFalse,
      reason: 'missing codepoints must use font fallback behavior',
    );
    expect(
      supportsGpuAtlasTextCommand(
        _textCommand(
          font: _atlasFont().copyWith(
            fallbacks: <LoveFont>[LoveFont(size: 12)],
          ),
        ),
      ),
      isFalse,
      reason: 'configured font fallbacks preserve their existing path',
    );
  });

  test('formatted atlas alignment follows native integral placement', () {
    expect(
      loveGpuAtlasLineOffset(align: 'center', wrapLimit: 200, lineWidth: 165),
      17,
      reason: 'native LOVE floors an odd spare width instead of using 17.5',
    );
    expect(
      loveGpuAtlasLineOffset(align: 'right', wrapLimit: 200, lineWidth: 165),
      35,
    );
  });

  test('batches only adjacent atlas text with a shared texture', () {
    final font = _atlasFont();
    final left = _textCommand(font: font);
    final right = _textCommand(font: font, limit: 80, align: 'right');
    expect(canBatchGpuAtlasTextCommands(left, right), isTrue);
    expect(
      canBatchGpuAtlasTextCommands(left, _textCommand(font: _atlasFont())),
      isFalse,
      reason: 'different atlas textures require separate bindings',
    );
  });
}

LoveTextCommand _textCommand({
  String text = 'A',
  double? limit,
  String align = 'left',
  LoveFont? font,
}) {
  return LoveTextCommand(
    color: LoveColor.white,
    lineWidth: 1,
    lineStyle: LoveGraphicsLineStyle.smooth,
    lineJoin: LoveGraphicsLineJoin.miter,
    blendMode: LoveGraphicsBlendMode.alpha,
    blendAlphaMode: LoveGraphicsBlendAlphaMode.alphaMultiply,
    colorMask: LoveGraphicsColorMask.all,
    wireframe: false,
    scissor: null,
    transform: vm.Matrix4.identity(),
    textTransform: vm.Matrix4.identity(),
    font: font ?? _atlasFont(),
    spans: <LoveTextSpan>[LoveTextSpan(text: text)],
    x: 0,
    y: 0,
    limit: limit,
    align: align,
  );
}

LoveFont _atlasFont() {
  final imageData = LoveImageData(width: 4, height: 4);
  return LoveFont(
    size: 12,
    glyphAtlas: LoveFontGlyphAtlas(
      image: LoveImage(
        source: 'test-font-atlas',
        width: 4,
        height: 4,
        imageData: imageData,
      ),
      glyphs: const <int, LoveFontAtlasGlyph>{
        0x41: LoveFontAtlasGlyph(
          codepoint: 0x41,
          x: 0,
          y: 0,
          width: 4,
          height: 4,
          advance: 5,
          bearingX: 0,
          bearingY: 4,
        ),
      },
    ),
  );
}
