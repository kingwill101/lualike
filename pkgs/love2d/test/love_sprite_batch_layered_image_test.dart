import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('SpriteBatch layered textures', () {
    test('addLayer and setLayer render selected array slices', () async {
      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 2),
        ),
      );

      await runtime.execute('''
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

batch = love.graphics.newSpriteBatch(array, 2)
batch:addLayer(1, 0, 0)
batch:addLayer(1, 2, 0)
batch:setLayer(2, 2, 2, 0)

function love.draw()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(batch)
  love.graphics.captureScreenshot(function(data)
    captured.left_r, captured.left_g, captured.left_b, captured.left_a =
      data:getPixel(0, 0)
    captured.right_r, captured.right_g, captured.right_b, captured.right_a =
      data:getPixel(2, 0)
  end)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();
      await _dispatchPendingScreenshots(runtime);

      expect(runtime.context.graphics.commands, hasLength(1));
      final command =
          runtime.context.graphics.commands.single as LoveSpriteBatchCommand;
      expect(command.spriteBatch.texture.textureType, 'array');
      final entries = command.spriteBatch.spritesToDraw();
      expect(entries, hasLength(2));
      expect(entries[0].layer, 0);
      expect(entries[1].layer, 1);

      final captured = runtime.unwrapGlobalTable('captured')!;
      expect(captured['left_r'] as double, closeTo(1.0, 0.001));
      expect(captured['left_g'] as double, closeTo(0.0, 0.001));
      expect(captured['left_b'] as double, closeTo(0.0, 0.001));
      expect(captured['left_a'] as double, closeTo(1.0, 0.001));
      expect(captured['right_r'] as double, closeTo(0.0, 0.001));
      expect(captured['right_g'] as double, closeTo(1.0, 0.001));
      expect(captured['right_b'] as double, closeTo(0.0, 0.001));
      expect(captured['right_a'] as double, closeTo(1.0, 0.001));
    });
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
