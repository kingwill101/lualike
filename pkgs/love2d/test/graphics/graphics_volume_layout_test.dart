import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart' show LuaError;
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics packed volume images', () {
    test('accepted packed layouts extract volume layers', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
local function fillLayer(data, ox, oy, size, r, g, b)
  for y = oy, oy + size - 1 do
    for x = ox, ox + size - 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
end

local function makeHorizontalStrip()
  local size = 2
  local data = love.image.newImageData(size * 3, size)
  fillLayer(data, 0, 0, size, 1, 0, 0)
  fillLayer(data, size, 0, size, 0, 1, 0)
  fillLayer(data, size * 2, 0, size, 0, 0, 1)
  return data
end

local function makeVerticalStrip()
  local size = 2
  local data = love.image.newImageData(size, size * 3)
  fillLayer(data, 0, 0, size, 1, 0, 0)
  fillLayer(data, 0, size, size, 0, 1, 0)
  fillLayer(data, 0, size * 2, size, 0, 0, 1)
  return data
end

volume_horizontal = love.graphics.newVolumeImage(makeHorizontalStrip(), {
  mipmaps = true,
})
volume_vertical = love.graphics.newVolumeImage(makeVerticalStrip(), {
  mipmaps = true,
})
''');

      _expectPackedVolume(_unwrapImage(runtime, 'volume_horizontal'));
      _expectPackedVolume(_unwrapImage(runtime, 'volume_vertical'));
    });

    test('invalid packed volume dimensions fail explicitly', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await expectLater(
        runtime.execute('''
local image = love.image.newImageData(3, 2)
love.graphics.newVolumeImage(image)
'''),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('cannot extract volume layers'),
          ),
        ),
      );
    });
  });
}

LoveImage _unwrapImage(LoveScriptRuntime runtime, String globalName) {
  final wrapped = runtime.unwrapGlobal(globalName);
  expect(wrapped, isA<Map<dynamic, dynamic>>());
  final image = (wrapped! as Map<dynamic, dynamic>)['__love2d_image__'];
  expect(image, isA<LoveImage>());
  return image! as LoveImage;
}

void _expectPackedVolume(LoveImage volume) {
  expect(volume.textureType, 'volume');
  expect(volume.layerCount, 1);
  expect(volume.depth, 3);
  expect(volume.mipmapCount, 2);
  expect(volume.sliceImages, hasLength(3));

  const expectedColors = <LoveColor>[
    LoveColor(1.0, 0.0, 0.0, 1.0),
    LoveColor(0.0, 1.0, 0.0, 1.0),
    LoveColor(0.0, 0.0, 1.0, 1.0),
  ];

  for (var layer = 0; layer < expectedColors.length; layer++) {
    final layerImage = volume.sliceImages![layer];
    expect(layerImage.mipmapCount, 2);
    expect(layerImage.pixelWidth, 2);
    expect(layerImage.pixelHeight, 2);
    expect(
      layerImage.imageDataAtMipmap(1)!.getPixel(0, 0),
      expectedColors[layer],
    );
    expect(
      layerImage.imageDataAtMipmap(2)!.getPixel(0, 0),
      expectedColors[layer],
    );
  }
}
