import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart' show LuaError;
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics layered images', () {
    test(
      'newArrayImage metadata and drawLayer render the selected slice',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
          ),
        );

        await runtime.execute('''
testbed = {}
captured = {}

local function solidImage(r, g, b, a)
  local data = love.image.newImageData(2, 2)
  for y = 0, 1 do
    for x = 0, 1 do
      data:setPixel(x, y, r, g, b, a)
    end
  end
  return data
end

local red = solidImage(1, 0, 0, 1)
local green = solidImage(0, 1, 0, 1)
local array = love.graphics.newArrayImage({red, green})

testbed.type = array:getTextureType()
testbed.layers = array:getLayerCount()
testbed.depth = array:getDepth()
testbed.width, testbed.height = array:getDimensions()

function love.draw()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.drawLayer(array, 2, 0, 0)
  love.graphics.captureScreenshot(function(data)
    captured.r, captured.g, captured.b, captured.a = data:getPixel(0, 0)
  end)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();
        await _dispatchPendingScreenshots(runtime);

        final metadata = runtime.unwrapGlobalTable('testbed')!;
        expect(metadata['type'], 'array');
        expect(metadata['layers'], 2);
        expect(metadata['depth'], 1);
        expect(metadata['width'], 2);
        expect(metadata['height'], 2);

        expect(runtime.context.graphics.commands, hasLength(1));
        final draw =
            runtime.context.graphics.commands.single as LoveImageCommand;
        expect(draw.layer, 1);
        expect(draw.image.textureType, 'array');
        expect(draw.image.sliceImages, hasLength(2));

        final captured = runtime.unwrapGlobalTable('captured')!;
        expect(captured['r'] as double, closeTo(0.0, 0.001));
        expect(captured['g'] as double, closeTo(1.0, 0.001));
        expect(captured['b'] as double, closeTo(0.0, 0.001));
        expect(captured['a'] as double, closeTo(1.0, 0.001));
      },
    );

    test('drawLayer accepts an optional Quad before draw parameters', () async {
      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 3, height: 3),
        ),
      );

      await runtime.execute('''
captured = {}

local function colorImage()
  local data = love.image.newImageData(2, 2)
  data:setPixel(0, 0, 1, 0, 0, 1)
  data:setPixel(1, 0, 1, 1, 0, 1)
  data:setPixel(0, 1, 0, 0, 1, 1)
  data:setPixel(1, 1, 0, 1, 1, 1)
  return data
end

local blue = love.image.newImageData(2, 2)
for y = 0, 1 do
  for x = 0, 1 do
    blue:setPixel(x, y, 0, 0, 0, 1)
  end
end
blue:setPixel(1, 0, 1, 1, 0, 1)

local array = love.graphics.newArrayImage({colorImage(), blue})
quad = love.graphics.newQuad(1, 0, 1, 1, 2, 2)

function love.draw()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.drawLayer(array, 2, quad, 0, 0)
  love.graphics.captureScreenshot(function(data)
    captured.r, captured.g, captured.b, captured.a = data:getPixel(0, 0)
  end)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();
      await _dispatchPendingScreenshots(runtime);

      expect(runtime.context.graphics.commands, hasLength(1));
      final draw = runtime.context.graphics.commands.single as LoveImageCommand;
      expect(draw.layer, 1);
      expect(draw.quad, isNotNull);
      expect(draw.quad!.x, 1);
      expect(draw.quad!.width, 1);

      final captured = runtime.unwrapGlobalTable('captured')!;
      expect(captured['r'] as double, closeTo(1.0, 0.001));
      expect(captured['g'] as double, closeTo(1.0, 0.001));
      expect(captured['b'] as double, closeTo(0.0, 0.001));
      expect(captured['a'] as double, closeTo(1.0, 0.001));
    });

    test(
      'volume and cube images expose metadata but drawing stays explicit',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local function solidImage(r, g, b)
  local data = love.image.newImageData(2, 2)
  for y = 0, 1 do
    for x = 0, 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
  return data
end

local volume = love.graphics.newVolumeImage({
  solidImage(1, 0, 0),
  solidImage(0, 1, 0),
  solidImage(0, 0, 1),
})
local cube = love.graphics.newCubeImage({
  solidImage(1, 0, 0),
  solidImage(0, 1, 0),
  solidImage(0, 0, 1),
  solidImage(1, 1, 0),
  solidImage(1, 0, 1),
  solidImage(0, 1, 1),
})

testbed.volume_type = volume:getTextureType()
testbed.volume_layers = volume:getLayerCount()
testbed.volume_depth = volume:getDepth()
testbed.cube_type = cube:getTextureType()
testbed.cube_layers = cube:getLayerCount()
testbed.cube_depth = cube:getDepth()
''');

        final metadata = runtime.unwrapGlobalTable('testbed')!;
        expect(metadata['volume_type'], 'volume');
        expect(metadata['volume_layers'], 1);
        expect(metadata['volume_depth'], 3);
        expect(metadata['cube_type'], 'cube');
        expect(metadata['cube_layers'], 6);
        expect(metadata['cube_depth'], 1);

        await expectLater(
          runtime.execute('''
local image = love.graphics.newVolumeImage({
  love.image.newImageData(2, 2),
  love.image.newImageData(2, 2),
})
love.graphics.drawLayer(image, 1, 0, 0)
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('volume textures'),
            ),
          ),
        );

        await expectLater(
          runtime.execute('''
local faces = {}
for i = 1, 6 do
  faces[i] = love.image.newImageData(2, 2)
end
local image = love.graphics.newCubeImage(faces)
love.graphics.draw(image, 0, 0)
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('cube textures'),
            ),
          ),
        );
      },
    );

    test(
      'manual mipmap table layouts construct layered textures and array slices can be replaced',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
          ),
        );

        await runtime.execute('''
testbed = {}
captured = {}

local function solidImage(size, r, g, b, a)
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      data:setPixel(x, y, r, g, b, a)
    end
  end
  return data
end

array = love.graphics.newArrayImage({
  {
    solidImage(4, 1, 0, 0, 1),
    solidImage(2, 0.75, 0, 0, 1),
    solidImage(1, 0.5, 0, 0, 1),
  },
  {
    solidImage(4, 0, 1, 0, 1),
    solidImage(2, 0, 0.75, 0, 1),
    solidImage(1, 0, 0.5, 0, 1),
  },
})

volume = love.graphics.newVolumeImage({
  {
    solidImage(4, 1, 0, 0, 1),
    solidImage(4, 0, 1, 0, 1),
  },
  {
    solidImage(2, 0.75, 0, 0, 1),
    solidImage(2, 0, 0.75, 0, 1),
  },
  {
    solidImage(1, 0.5, 0, 0, 1),
    solidImage(1, 0, 0.5, 0, 1),
  },
})

local faces = {}
for i = 1, 6 do
  faces[i] = {
    solidImage(4, i / 6, 0, 0, 1),
    solidImage(2, i / 6, 0.25, 0, 1),
  }
end
cube = love.graphics.newCubeImage(faces)

testbed.array_mips = array:getMipmapCount()
testbed.array_mip2 = string.format("%dx%d", array:getPixelDimensions(2))
testbed.array_mip3 = string.format("%dx%d", array:getPixelDimensions(3))
testbed.volume_mips = volume:getMipmapCount()
testbed.volume_mip2 = string.format("%dx%d", volume:getPixelDimensions(2))
testbed.cube_mips = cube:getMipmapCount()
testbed.cube_mip2 = string.format("%dx%d", cube:getPixelDimensions(2))

local patch_base = love.image.newImageData(1, 1)
patch_base:setPixel(0, 0, 1, 1, 0, 1)
array:replacePixels(patch_base, 2, 1, 0, 0, false)

local patch_mip = love.image.newImageData(1, 1)
patch_mip:setPixel(0, 0, 0, 0, 1, 1)
array:replacePixels(patch_mip, 2, 2, 0, 0, false)

function love.draw()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.drawLayer(array, 2, 0, 0)
  love.graphics.captureScreenshot(function(data)
    captured.r, captured.g, captured.b, captured.a = data:getPixel(0, 0)
  end)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();
        await _dispatchPendingScreenshots(runtime);

        final metadata = runtime.unwrapGlobalTable('testbed')!;
        expect(metadata['array_mips'], 3);
        expect(metadata['array_mip2'], '2x2');
        expect(metadata['array_mip3'], '1x1');
        expect(metadata['volume_mips'], 3);
        expect(metadata['volume_mip2'], '2x2');
        expect(metadata['cube_mips'], 2);
        expect(metadata['cube_mip2'], '2x2');

        final wrappedArray = runtime.unwrapGlobal('array');
        expect(wrappedArray, isA<Map>());
        final arrayImage = (wrappedArray! as Map)['__love2d_image__'];
        expect(arrayImage, isA<LoveImage>());
        final arrayTexture = arrayImage! as LoveImage;
        expect(arrayTexture.mipmapCount, 3);
        expect(arrayTexture.sliceImages, hasLength(2));
        expect(
          arrayTexture.sliceImages![1].imageDataAtMipmap(1)!.getPixel(0, 0),
          const LoveColor(1.0, 1.0, 0.0, 1.0),
        );
        expect(
          arrayTexture.sliceImages![1].imageDataAtMipmap(2)!.getPixel(0, 0),
          const LoveColor(0.0, 0.0, 1.0, 1.0),
        );

        final captured = runtime.unwrapGlobalTable('captured')!;
        expect(captured['r'] as double, closeTo(1.0, 0.001));
        expect(captured['g'] as double, closeTo(1.0, 0.001));
        expect(captured['b'] as double, closeTo(0.0, 0.001));
        expect(captured['a'] as double, closeTo(1.0, 0.001));
      },
    );

    test(
      'unsupported layered-image layouts fail with explicit errors',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await expectLater(
          runtime.execute('''
local image = love.image.newImageData(4, 4)
local bad = love.image.newImageData(3, 3)
love.graphics.newArrayImage({{image, bad}})
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('manual mipmap dimensions'),
            ),
          ),
        );

        await expectLater(
          runtime.execute('''
local image = love.image.newImageData(5, 5)
love.graphics.newCubeImage(image)
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('unknown cubemap image dimensions'),
            ),
          ),
        );
      },
    );
  });
}

Future<void> _dispatchPendingScreenshots(LoveScriptRuntime runtime) {
  final snapshot = runtime.context.graphics.snapshotScreenSurface();
  return runtime.context.graphics.dispatchPendingScreenshots(
    snapshot: snapshot,
    pixelWidth:
        (runtime.context.windowMetrics.width *
                runtime.context.windowMetrics.dpiScale)
            .round(),
    pixelHeight:
        (runtime.context.windowMetrics.height *
                runtime.context.windowMetrics.dpiScale)
            .round(),
  );
}
