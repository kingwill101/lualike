import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics texture metadata mipmaps', () {
    test(
      'texture getters honor mipmap arguments for logical size and depth',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local function solid(width, height, r, g, b)
  local data = love.image.newImageData(width, height)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
  return data
end

image = love.graphics.newImage(solid(8, 4, 1, 0, 0), {
  mipmaps = true,
  dpiscale = 2,
})

volume = love.graphics.newVolumeImage({
  {
    solid(8, 8, 1, 0, 0),
    solid(8, 8, 0, 1, 0),
    solid(8, 8, 0, 0, 1),
    solid(8, 8, 1, 1, 0),
  },
  {
    solid(4, 4, 0.75, 0, 0),
    solid(4, 4, 0, 0.75, 0),
    solid(4, 4, 0, 0, 0.75),
    solid(4, 4, 0.75, 0.75, 0),
  },
  {
    solid(2, 2, 0.5, 0, 0),
    solid(2, 2, 0, 0.5, 0),
    solid(2, 2, 0, 0, 0.5),
    solid(2, 2, 0.5, 0.5, 0),
  },
})

local faces = {}
for i = 1, 6 do
  faces[i] = {
    solid(8, 8, i / 6, 0, 0),
    solid(4, 4, i / 6, 0.25, 0),
    solid(2, 2, i / 6, 0.5, 0),
  }
end
cube = love.graphics.newCubeImage(faces)

testbed.image_dims = string.format("%dx%d", image:getDimensions())
testbed.image_dims2 = string.format("%dx%d", image:getDimensions(2))
testbed.image_width3 = image:getWidth(3)
testbed.image_height3 = image:getHeight(3)

testbed.volume_dims = string.format("%dx%d", volume:getDimensions())
testbed.volume_dims2 = string.format("%dx%d", volume:getDimensions(2))
testbed.volume_dims3 = string.format("%dx%d", volume:getDimensions(3))
testbed.volume_depth = volume:getDepth()
testbed.volume_depth2 = volume:getDepth(2)
testbed.volume_depth3 = volume:getDepth(3)

testbed.cube_dims = string.format("%dx%d", cube:getDimensions())
testbed.cube_dims2 = string.format("%dx%d", cube:getDimensions(2))
testbed.cube_dims3 = string.format("%dx%d", cube:getDimensions(3))
testbed.cube_depth2 = cube:getDepth(2)
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['image_dims'], '4x2');
        expect(snapshot['image_dims2'], '2x1');
        expect(snapshot['image_width3'], 1);
        expect(snapshot['image_height3'], 1);

        expect(snapshot['volume_dims'], '8x8');
        expect(snapshot['volume_dims2'], '4x4');
        expect(snapshot['volume_dims3'], '2x2');
        expect(snapshot['volume_depth'], 4);
        expect(snapshot['volume_depth2'], 2);
        expect(snapshot['volume_depth3'], 1);

        expect(snapshot['cube_dims'], '8x8');
        expect(snapshot['cube_dims2'], '4x4');
        expect(snapshot['cube_dims3'], '2x2');
        expect(snapshot['cube_depth2'], 1);
      },
    );
  });
}
