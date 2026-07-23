import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics quad layer parity', () {
    test(
      'Quad layer accessors and viewport refresh mirror LOVE wrappers',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local quad = love.graphics.newQuad(1, 2, 3, 4, 8, 9)
testbed.initial_layer = quad:getLayer()

quad:setLayer(3)
testbed.layer = quad:getLayer()

quad:setViewport(4, 5, 6, 7, 10, 11)
testbed.x, testbed.y, testbed.w, testbed.h = quad:getViewport()
testbed.tw, testbed.th = quad:getTextureDimensions()
''');

        final metadata = runtime.unwrapGlobalTable('testbed')!;
        expect(metadata['initial_layer'], 1);
        expect(metadata['layer'], 3);
        expect(metadata['x'], 4);
        expect(metadata['y'], 5);
        expect(metadata['w'], 6);
        expect(metadata['h'], 7);
        expect(metadata['tw'], 10);
        expect(metadata['th'], 11);
      },
    );

    test('love.graphics.draw uses the Quad layer for array textures', () async {
      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 2, height: 2),
        ),
      );

      await runtime.execute('''
captured = {}

local function solidImage(r, g, b)
  local data = love.image.newImageData(2, 2)
  for y = 0, 1 do
    for x = 0, 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
  return data
end

local array = love.graphics.newArrayImage({
  solidImage(1, 0, 0),
  solidImage(0, 1, 0),
})
local quad = love.graphics.newQuad(0, 0, 2, 2, 2, 2)
quad:setLayer(2)

function love.draw()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(array, quad, 0, 0)
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
      expect(draw.quad!.layer, 1);

      final captured = runtime.unwrapGlobalTable('captured')!;
      expect(captured['r'] as double, closeTo(0.0, 0.001));
      expect(captured['g'] as double, closeTo(1.0, 0.001));
      expect(captured['b'] as double, closeTo(0.0, 0.001));
      expect(captured['a'] as double, closeTo(1.0, 0.001));
    });

    test(
      'SpriteBatch add and set use the Quad layer for array textures',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 2, height: 2),
          ),
        );

        await runtime.execute('''
captured = {}

local function solidImage(r, g, b)
  local data = love.image.newImageData(2, 2)
  for y = 0, 1 do
    for x = 0, 1 do
      data:setPixel(x, y, r, g, b, 1)
    end
  end
  return data
end

local array = love.graphics.newArrayImage({
  solidImage(1, 0, 0),
  solidImage(0, 1, 0),
})
local quad = love.graphics.newQuad(0, 0, 2, 2, 2, 2)
quad:setLayer(2)

local batch = love.graphics.newSpriteBatch(array, 4)
local index = batch:add(quad, 0, 0)
quad:setLayer(1)
batch:set(index, quad, 0, 0)
quad:setLayer(2)
batch:set(index, quad, 0, 0)

function love.draw()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(batch, 0, 0)
  love.graphics.captureScreenshot(function(data)
    captured.r, captured.g, captured.b, captured.a = data:getPixel(0, 0)
  end)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();
        await _dispatchPendingScreenshots(runtime);

        expect(runtime.context.graphics.commands, hasLength(1));
        final draw =
            runtime.context.graphics.commands.single as LoveSpriteBatchCommand;
        expect(draw.spriteBatch.sprites, hasLength(1));
        expect(draw.spriteBatch.sprites.single.layer, 1);
        expect(draw.spriteBatch.sprites.single.quad, isNotNull);
        expect(draw.spriteBatch.sprites.single.quad!.layer, 1);

        final captured = runtime.unwrapGlobalTable('captured')!;
        expect(captured['r'] as double, closeTo(0.0, 0.001));
        expect(captured['g'] as double, closeTo(1.0, 0.001));
        expect(captured['b'] as double, closeTo(0.0, 0.001));
        expect(captured['a'] as double, closeTo(1.0, 0.001));
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
