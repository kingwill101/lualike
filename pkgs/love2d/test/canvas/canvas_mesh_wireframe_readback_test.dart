import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test(
    'Canvas:newImageData preserves mesh wireframe output as edges only',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local mesh = love.graphics.newMesh({
  {0, 0},
  {10, 0},
  {10, 10},
  {0, 10},
}, "fan", "static")
local canvas = love.graphics.newCanvas(10, 10, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setWireframe(true)
  love.graphics.draw(mesh)
  love.graphics.setWireframe(false)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local cr, cg, cb, ca = snapshot:getPixel(2, 5)
  local er, eg, eb, ea = snapshot:getPixel(5, 0)
  testbed.center = string.format("%.2f/%.2f/%.2f/%.2f", cr, cg, cb, ca)
  testbed.edge = string.format("%.2f/%.2f/%.2f/%.2f", er, eg, eb, ea)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['center'], '0.00/0.00/0.00/0.00');
      expect(snapshot['edge'], '1.00/1.00/1.00/1.00');
    },
  );
}
