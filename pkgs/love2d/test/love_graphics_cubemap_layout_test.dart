import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics packed cubemaps', () {
    test(
      'accepted packed layouts extract faces in LOVE cubemap order',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
local function fillFace(data, ox, oy, size, r, g, b)
  for y = oy, oy + size - 1 do
    for x = ox, ox + size - 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
end

local function makeCrossA()
  local size = 2
  local data = love.image.newImageData(size * 3, size * 4)
  fillFace(data, size, size, size, 1, 0, 0) -- +x
  fillFace(data, size, size * 3, size, 0, 1, 0) -- -x
  fillFace(data, size, 0, size, 0, 0, 1) -- +y
  fillFace(data, size, size * 2, size, 1, 1, 0) -- -y
  fillFace(data, 0, size, size, 1, 0, 1) -- +z
  fillFace(data, size * 2, size, size, 0, 1, 1) -- -z
  return data
end

local function makeCrossB()
  local size = 2
  local data = love.image.newImageData(size * 4, size * 3)
  fillFace(data, size * 2, size, size, 1, 0, 0) -- +x
  fillFace(data, 0, size, size, 0, 1, 0) -- -x
  fillFace(data, size, 0, size, 0, 0, 1) -- +y
  fillFace(data, size, size * 2, size, 1, 1, 0) -- -y
  fillFace(data, size, size, size, 1, 0, 1) -- +z
  fillFace(data, size * 3, size, size, 0, 1, 1) -- -z
  return data
end

local function makeVerticalStrip()
  local size = 2
  local data = love.image.newImageData(size, size * 6)
  fillFace(data, 0, 0, size, 1, 0, 0) -- +x
  fillFace(data, 0, size, size, 0, 1, 0) -- -x
  fillFace(data, 0, size * 2, size, 0, 0, 1) -- +y
  fillFace(data, 0, size * 3, size, 1, 1, 0) -- -y
  fillFace(data, 0, size * 4, size, 1, 0, 1) -- +z
  fillFace(data, 0, size * 5, size, 0, 1, 1) -- -z
  return data
end

local function makeHorizontalStrip()
  local size = 2
  local data = love.image.newImageData(size * 6, size)
  fillFace(data, 0, 0, size, 1, 0, 0) -- +x
  fillFace(data, size, 0, size, 0, 1, 0) -- -x
  fillFace(data, size * 2, 0, size, 0, 0, 1) -- +y
  fillFace(data, size * 3, 0, size, 1, 1, 0) -- -y
  fillFace(data, size * 4, 0, size, 1, 0, 1) -- +z
  fillFace(data, size * 5, 0, size, 0, 1, 1) -- -z
  return data
end

cube_cross_a = love.graphics.newCubeImage(makeCrossA(), { mipmaps = true })
cube_cross_b = love.graphics.newCubeImage(makeCrossB(), { mipmaps = true })
cube_vertical = love.graphics.newCubeImage(makeVerticalStrip(), { mipmaps = true })
cube_horizontal = love.graphics.newCubeImage(makeHorizontalStrip(), { mipmaps = true })
''');

        _expectPackedCube(_unwrapImage(runtime, 'cube_cross_a'));
        _expectPackedCube(_unwrapImage(runtime, 'cube_cross_b'));
        _expectPackedCube(_unwrapImage(runtime, 'cube_vertical'));
        _expectPackedCube(_unwrapImage(runtime, 'cube_horizontal'));
      },
    );

    test('flat packed-source tables map to cubemap mipmap levels', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
local function fillFace(data, ox, oy, size, r, g, b)
  for y = oy, oy + size - 1 do
    for x = ox, ox + size - 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
end

local function makeCross(size, colors)
  local data = love.image.newImageData(size * 3, size * 4)
  fillFace(data, size, size, size, colors[1][1], colors[1][2], colors[1][3])
  fillFace(data, size, size * 3, size, colors[2][1], colors[2][2], colors[2][3])
  fillFace(data, size, 0, size, colors[3][1], colors[3][2], colors[3][3])
  fillFace(data, size, size * 2, size, colors[4][1], colors[4][2], colors[4][3])
  fillFace(data, 0, size, size, colors[5][1], colors[5][2], colors[5][3])
  fillFace(data, size * 2, size, size, colors[6][1], colors[6][2], colors[6][3])
  return data
end

cube_manual = love.graphics.newCubeImage({
  makeCross(4, {
    {1, 0, 0},
    {0, 1, 0},
    {0, 0, 1},
    {1, 1, 0},
    {1, 0, 1},
    {0, 1, 1},
  }),
  makeCross(2, {
    {0.8, 0, 0},
    {0, 0.8, 0},
    {0, 0, 0.8},
    {0.8, 0.8, 0},
    {0.8, 0, 0.8},
    {0, 0.8, 0.8},
  }),
})
''');

      final cube = _unwrapImage(runtime, 'cube_manual');
      expect(cube.textureType, 'cube');
      expect(cube.sliceImages, hasLength(6));
      expect(cube.mipmapCount, 2);

      expect(
        cube.sliceImages![0].imageDataAtMipmap(1)!.getPixel(0, 0),
        const LoveColor(1.0, 0.0, 0.0, 1.0),
      );
      expect(
        cube.sliceImages![0].imageDataAtMipmap(2)!.getPixel(0, 0),
        const LoveColor(0.8, 0.0, 0.0, 1.0),
      );
      expect(
        cube.sliceImages![5].imageDataAtMipmap(1)!.getPixel(0, 0),
        const LoveColor(0.0, 1.0, 1.0, 1.0),
      );
      expect(
        cube.sliceImages![5].imageDataAtMipmap(2)!.getPixel(0, 0),
        const LoveColor(0.0, 0.8, 0.8, 1.0),
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

void _expectPackedCube(LoveImage cube) {
  expect(cube.textureType, 'cube');
  expect(cube.layerCount, 6);
  expect(cube.depth, 1);
  expect(cube.mipmapCount, 2);
  expect(cube.sliceImages, hasLength(6));

  const expectedColors = <LoveColor>[
    LoveColor(1.0, 0.0, 0.0, 1.0),
    LoveColor(0.0, 1.0, 0.0, 1.0),
    LoveColor(0.0, 0.0, 1.0, 1.0),
    LoveColor(1.0, 1.0, 0.0, 1.0),
    LoveColor(1.0, 0.0, 1.0, 1.0),
    LoveColor(0.0, 1.0, 1.0, 1.0),
  ];

  for (var face = 0; face < expectedColors.length; face++) {
    final faceImage = cube.sliceImages![face];
    expect(faceImage.mipmapCount, 2);
    expect(faceImage.pixelWidth, 2);
    expect(faceImage.pixelHeight, 2);
    expect(
      faceImage.imageDataAtMipmap(1)!.getPixel(0, 0),
      expectedColors[face],
    );
    expect(
      faceImage.imageDataAtMipmap(2)!.getPixel(0, 0),
      expectedColors[face],
    );
  }
}
