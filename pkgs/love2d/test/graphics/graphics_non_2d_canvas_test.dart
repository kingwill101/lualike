import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics non-2d canvases', () {
    test(
      'volume canvases select per-layer render targets and Canvas:newImageData reads layers',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 1, height: 1),
          ),
        );

        await runtime.execute('''
testbed = {}

local canvas = love.graphics.newCanvas(1, 1, {
  type = "volume",
  layers = 2,
  readable = true,
})

function love.draw()
  love.graphics.setCanvas(canvas, 1)
  local active1 = love.graphics.getCanvas()
  testbed.active1_type = type(active1)
  testbed.active1_layer = active1[1].layer
  testbed.active1_mipmap = active1[1].mipmap
  love.graphics.clear(1, 0, 0, 1)

  canvas:renderTo(2, function()
    local active2 = love.graphics.getCanvas()
    testbed.active2_type = type(active2)
    testbed.active2_layer = active2[1].layer
    testbed.active2_mipmap = active2[1].mipmap
    love.graphics.clear(0, 1, 0, 1)
  end)

  love.graphics.setCanvas()

  local layer1 = canvas:newImageData(1)
  local layer2 = canvas:newImageData(2)
  testbed.layer1_r, testbed.layer1_g, testbed.layer1_b, testbed.layer1_a =
    layer1:getPixel(0, 0)
  testbed.layer2_r, testbed.layer2_g, testbed.layer2_b, testbed.layer2_a =
    layer2:getPixel(0, 0)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['active1_type'], 'table');
        expect(snapshot['active1_layer'], 1);
        expect(snapshot['active1_mipmap'], 1);
        expect(snapshot['active2_type'], 'table');
        expect(snapshot['active2_layer'], 2);
        expect(snapshot['active2_mipmap'], 1);
        expect(snapshot['layer1_r'] as double, closeTo(1.0, 0.001));
        expect(snapshot['layer1_g'] as double, closeTo(0.0, 0.001));
        expect(snapshot['layer1_b'] as double, closeTo(0.0, 0.001));
        expect(snapshot['layer1_a'] as double, closeTo(1.0, 0.001));
        expect(snapshot['layer2_r'] as double, closeTo(0.0, 0.001));
        expect(snapshot['layer2_g'] as double, closeTo(1.0, 0.001));
        expect(snapshot['layer2_b'] as double, closeTo(0.0, 0.001));
        expect(snapshot['layer2_a'] as double, closeTo(1.0, 0.001));
      },
    );

    test(
      'cube canvases select per-face render targets and Canvas:newImageData reads faces',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 1, height: 1),
          ),
        );

        await runtime.execute('''
testbed = {}

local canvas = love.graphics.newCanvas(1, 1, {
  type = "cube",
  readable = true,
})

function love.draw()
  love.graphics.setCanvas({{canvas, face = 1}})
  local active1 = love.graphics.getCanvas()
  testbed.active1_type = type(active1)
  testbed.active1_face = active1[1].face
  testbed.active1_mipmap = active1[1].mipmap
  love.graphics.clear(0, 0, 1, 1)

  canvas:renderTo(6, function()
    local active6 = love.graphics.getCanvas()
    testbed.active6_type = type(active6)
    testbed.active6_face = active6[1].face
    testbed.active6_mipmap = active6[1].mipmap
    love.graphics.clear(1, 1, 0, 1)
  end)

  love.graphics.setCanvas()

  local face1 = canvas:newImageData(1)
  local face6 = canvas:newImageData(6)
  testbed.face1_r, testbed.face1_g, testbed.face1_b, testbed.face1_a =
    face1:getPixel(0, 0)
  testbed.face6_r, testbed.face6_g, testbed.face6_b, testbed.face6_a =
    face6:getPixel(0, 0)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['active1_type'], 'table');
        expect(snapshot['active1_face'], 1);
        expect(snapshot['active1_mipmap'], 1);
        expect(snapshot['active6_type'], 'table');
        expect(snapshot['active6_face'], 6);
        expect(snapshot['active6_mipmap'], 1);
        expect(snapshot['face1_r'] as double, closeTo(0.0, 0.001));
        expect(snapshot['face1_g'] as double, closeTo(0.0, 0.001));
        expect(snapshot['face1_b'] as double, closeTo(1.0, 0.001));
        expect(snapshot['face1_a'] as double, closeTo(1.0, 0.001));
        expect(snapshot['face6_r'] as double, closeTo(1.0, 0.001));
        expect(snapshot['face6_g'] as double, closeTo(1.0, 0.001));
        expect(snapshot['face6_b'] as double, closeTo(0.0, 0.001));
        expect(snapshot['face6_a'] as double, closeTo(1.0, 0.001));
      },
    );
  });
}
