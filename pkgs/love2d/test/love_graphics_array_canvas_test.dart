import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart' show LuaError;
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics array canvases', () {
    test(
      'setCanvas selects per-layer render targets and Canvas:newImageData reads slices',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 2, height: 1),
          ),
        );

        await runtime.execute('''
testbed = {}

local canvas = love.graphics.newCanvas(1, 1, {
  type = "array",
  layers = 2,
  readable = true,
})

function love.draw()
  love.graphics.setCanvas(canvas, 1)
  local active1 = love.graphics.getCanvas()
  testbed.active1_type = type(active1)
  testbed.active1_layer = active1[1].layer
  testbed.active1_mipmap = active1[1].mipmap
  love.graphics.clear(0, 0, 1, 1)

  love.graphics.setCanvas({{canvas, layer = 2}})
  local active2 = love.graphics.getCanvas()
  testbed.active2_type = type(active2)
  testbed.active2_layer = active2[1].layer
  testbed.active2_mipmap = active2[1].mipmap
  love.graphics.clear(0, 1, 0, 1)

  love.graphics.setCanvas()

  local slice1 = canvas:newImageData(1)
  local slice2 = canvas:newImageData(2)
  testbed.slice1_r, testbed.slice1_g, testbed.slice1_b, testbed.slice1_a =
    slice1:getPixel(0, 0)
  testbed.slice2_r, testbed.slice2_g, testbed.slice2_b, testbed.slice2_a =
    slice2:getPixel(0, 0)
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
        expect(snapshot['slice1_r'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice1_g'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice1_b'] as double, closeTo(1.0, 0.001));
        expect(snapshot['slice1_a'] as double, closeTo(1.0, 0.001));
        expect(snapshot['slice2_r'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice2_g'] as double, closeTo(1.0, 0.001));
        expect(snapshot['slice2_b'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice2_a'] as double, closeTo(1.0, 0.001));
      },
    );

    test(
      'renderTo restores the previous array-canvas layer and drawLayer renders snapshot slices',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 2, height: 1),
          ),
        );

        await runtime.execute('''
testbed = {}
captured = {}

local canvas = love.graphics.newCanvas(1, 1, {
  type = "array",
  layers = 2,
  readable = true,
})

function love.draw()
  love.graphics.setCanvas(canvas, 1)
  love.graphics.clear(1, 0, 0, 1)

  canvas:renderTo(2, function()
    local active = love.graphics.getCanvas()
    testbed.canvas_active_inside = active ~= nil
    testbed.canvas_active_inside_layer = active[1].layer
    testbed.canvas_active_inside_mipmap = active[1].mipmap
    love.graphics.clear(0, 1, 0, 1)
  end)

  local activeAfter = love.graphics.getCanvas()
  testbed.canvas_active_after_render_to = activeAfter ~= nil
  testbed.canvas_active_after_render_to_layer = activeAfter[1].layer
  testbed.canvas_active_after_render_to_mipmap = activeAfter[1].mipmap
  love.graphics.clear(0, 0, 1, 1)
  love.graphics.setCanvas()

  local slice1 = canvas:newImageData(1)
  local slice2 = canvas:newImageData(2)
  testbed.slice1_r, testbed.slice1_g, testbed.slice1_b, testbed.slice1_a =
    slice1:getPixel(0, 0)
  testbed.slice2_r, testbed.slice2_g, testbed.slice2_b, testbed.slice2_a =
    slice2:getPixel(0, 0)

  love.graphics.clear(0, 0, 0, 1)
  love.graphics.drawLayer(canvas, 1, 0, 0)
  love.graphics.drawLayer(canvas, 2, 1, 0)
  love.graphics.captureScreenshot(function(data)
    captured.left_r, captured.left_g, captured.left_b, captured.left_a =
      data:getPixel(0, 0)
    captured.right_r, captured.right_g, captured.right_b, captured.right_a =
      data:getPixel(1, 0)
  end)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();
        await _dispatchPendingScreenshots(runtime);

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['canvas_active_inside'], isTrue);
        expect(snapshot['canvas_active_inside_layer'], 2);
        expect(snapshot['canvas_active_inside_mipmap'], 1);
        expect(snapshot['canvas_active_after_render_to'], isTrue);
        expect(snapshot['canvas_active_after_render_to_layer'], 1);
        expect(snapshot['canvas_active_after_render_to_mipmap'], 1);
        expect(snapshot['slice1_r'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice1_g'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice1_b'] as double, closeTo(1.0, 0.001));
        expect(snapshot['slice1_a'] as double, closeTo(1.0, 0.001));
        expect(snapshot['slice2_r'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice2_g'] as double, closeTo(1.0, 0.001));
        expect(snapshot['slice2_b'] as double, closeTo(0.0, 0.001));
        expect(snapshot['slice2_a'] as double, closeTo(1.0, 0.001));

        expect(runtime.context.graphics.commands, hasLength(2));
        final first = runtime.context.graphics.commands[0] as LoveImageCommand;
        final second = runtime.context.graphics.commands[1] as LoveImageCommand;
        expect(first.image, isA<LoveCanvasSnapshot>());
        expect(second.image, isA<LoveCanvasSnapshot>());
        expect(first.layer, 0);
        expect(second.layer, 1);

        final firstSnapshot = first.image as LoveCanvasSnapshot;
        expect(firstSnapshot.textureType, 'array');
        expect(firstSnapshot.sliceImages, hasLength(2));
        expect(firstSnapshot.sliceImages![0], isA<LoveCanvasSnapshot>());
        expect(firstSnapshot.sliceImages![1], isA<LoveCanvasSnapshot>());

        final captured = runtime.unwrapGlobalTable('captured')!;
        expect(captured['left_r'] as double, closeTo(0.0, 0.001));
        expect(captured['left_g'] as double, closeTo(0.0, 0.001));
        expect(captured['left_b'] as double, closeTo(1.0, 0.001));
        expect(captured['left_a'] as double, closeTo(1.0, 0.001));
        expect(captured['right_r'] as double, closeTo(0.0, 0.001));
        expect(captured['right_g'] as double, closeTo(1.0, 0.001));
        expect(captured['right_b'] as double, closeTo(0.0, 0.001));
        expect(captured['right_a'] as double, closeTo(1.0, 0.001));
      },
    );

    test(
      'array canvases reject plain-table setCanvas and missing slice arguments',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await expectLater(
          runtime.execute('''
local canvas = love.graphics.newCanvas(1, 1, {
  type = "array",
  layers = 2,
  readable = true,
})
love.graphics.setCanvas({canvas})
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('table-of-tables'),
            ),
          ),
        );

        await expectLater(
          runtime.execute('''
local canvas = love.graphics.newCanvas(1, 1, {
  type = "array",
  layers = 2,
  readable = true,
})
canvas:renderTo(function() end)
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('explicit slice'),
            ),
          ),
        );

        await expectLater(
          runtime.execute('''
local canvas = love.graphics.newCanvas(1, 1, {
  type = "array",
  layers = 2,
  readable = true,
})
canvas:newImageData()
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('explicit slice'),
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
