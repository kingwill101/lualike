import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test(
    'Canvas:newImageData keeps strip triangles when canvas winding flip matches back-face culling',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local mesh = love.graphics.newMesh({
  {0, 0, 0, 0, 1, 0, 0, 1},
  {0, 10, 0, 0, 1, 0, 0, 1},
  {10, 0, 0, 0, 1, 0, 0, 1},
  {10, 10, 0, 0, 1, 0, 0, 1},
}, "strip", "static")
local canvas = love.graphics.newCanvas(10, 10, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setFrontFaceWinding("cw")
  love.graphics.setMeshCullMode("back")
  love.graphics.draw(mesh)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local ulr, ulg, ulb, ula = snapshot:getPixel(2, 2)
  local lrr, lrg, lrb, lra = snapshot:getPixel(7, 7)
  testbed.upper_left = string.format("%.2f/%.2f/%.2f/%.2f", ulr, ulg, ulb, ula)
  testbed.lower_right = string.format("%.2f/%.2f/%.2f/%.2f", lrr, lrg, lrb, lra)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['upper_left'], '1.00/0.00/0.00/1.00');
      expect(snapshot['lower_right'], '1.00/0.00/0.00/1.00');
    },
  );

  test(
    'Canvas:newImageData culls strip triangles when canvas winding flip disagrees with back-face culling',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local mesh = love.graphics.newMesh({
  {0, 0, 0, 0, 1, 0, 0, 1},
  {0, 10, 0, 0, 1, 0, 0, 1},
  {10, 0, 0, 0, 1, 0, 0, 1},
  {10, 10, 0, 0, 1, 0, 0, 1},
}, "strip", "static")
local canvas = love.graphics.newCanvas(10, 10, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setFrontFaceWinding("ccw")
  love.graphics.setMeshCullMode("back")
  love.graphics.draw(mesh)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local ulr, ulg, ulb, ula = snapshot:getPixel(2, 2)
  local lrr, lrg, lrb, lra = snapshot:getPixel(7, 7)
  testbed.upper_left = string.format("%.2f/%.2f/%.2f/%.2f", ulr, ulg, ulb, ula)
  testbed.lower_right = string.format("%.2f/%.2f/%.2f/%.2f", lrr, lrg, lrb, lra)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['upper_left'], '0.00/0.00/0.00/0.00');
      expect(snapshot['lower_right'], '0.00/0.00/0.00/0.00');
    },
  );
}
