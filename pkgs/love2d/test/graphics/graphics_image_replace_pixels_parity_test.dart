import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart' show LuaError;
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics Image:replacePixels parity', () {
    test('2D images ignore the slice argument slot', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
image = love.graphics.newImage(love.image.newImageData(4, 4))
patch = love.image.newImageData(1, 1)
patch:setPixel(0, 0, 0, 1, 0, 1)
image:replacePixels(patch, 99, 1, 2, 1, false)
''');

      final image = _unwrapImage(runtime, 'image');
      expect(
        image.imageData!.getPixel(2, 1),
        const LoveColor(0.0, 1.0, 0.0, 1.0),
      );
    });

    test('non-2D images require an explicit slice argument', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await expectLater(
        runtime.execute('''
local image = love.graphics.newArrayImage({
  love.image.newImageData(2, 2),
  love.image.newImageData(2, 2),
})
local patch = love.image.newImageData(1, 1)
image:replacePixels(patch)
'''),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('explicit slice'),
          ),
        ),
      );
    });

    test('array, volume, and cube images replace the selected slice', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
local function solid(size, r, g, b)
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
  return data
end

array = love.graphics.newArrayImage({
  solid(2, 1, 0, 0),
  solid(2, 0, 1, 0),
})

volume = love.graphics.newVolumeImage({
  solid(2, 1, 0, 0),
  solid(2, 0, 1, 0),
  solid(2, 0, 0, 1),
})

cube = love.graphics.newCubeImage({
  solid(2, 1, 0, 0),
  solid(2, 0, 1, 0),
  solid(2, 0, 0, 1),
  solid(2, 1, 1, 0),
  solid(2, 1, 0, 1),
  solid(2, 0, 1, 1),
})

local yellow = love.image.newImageData(1, 1)
yellow:setPixel(0, 0, 1, 1, 0, 1)
array:replacePixels(yellow, 2, 1, 0, 0, false)

local white = love.image.newImageData(1, 1)
white:setPixel(0, 0, 1, 1, 1, 1)
volume:replacePixels(white, 3, 1, 0, 0, false)

local black = love.image.newImageData(1, 1)
black:setPixel(0, 0, 0, 0, 0, 1)
cube:replacePixels(black, 6, 1, 0, 0, false)
''');

      final array = _unwrapImage(runtime, 'array');
      final volume = _unwrapImage(runtime, 'volume');
      final cube = _unwrapImage(runtime, 'cube');

      expect(
        array.sliceImages![1].imageData!.getPixel(0, 0),
        const LoveColor(1.0, 1.0, 0.0, 1.0),
      );
      expect(
        volume.sliceImages![2].imageData!.getPixel(0, 0),
        const LoveColor(1.0, 1.0, 1.0, 1.0),
      );
      expect(
        cube.sliceImages![5].imageData!.getPixel(0, 0),
        const LoveColor(0.0, 0.0, 0.0, 1.0),
      );

      expect(
        array.sliceImages![0].imageData!.getPixel(0, 0),
        const LoveColor(1.0, 0.0, 0.0, 1.0),
      );
      expect(
        volume.sliceImages![1].imageData!.getPixel(0, 0),
        const LoveColor(0.0, 1.0, 0.0, 1.0),
      );
      expect(
        cube.sliceImages![0].imageData!.getPixel(0, 0),
        const LoveColor(1.0, 0.0, 0.0, 1.0),
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
