import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test(
    'Canvas:newImageData preserves mesh points with the current point size',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local mesh = love.graphics.newMesh({
  {5, 5, 0, 0, 1, 0, 0, 1},
}, "points", "static")
local canvas = love.graphics.newCanvas(10, 10, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setPointSize(4)
  love.graphics.draw(mesh)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local cr, cg, cb, ca = snapshot:getPixel(5, 5)
  local sr, sg, sb, sa = snapshot:getPixel(3, 5)
  local orr, org, orb, ora = snapshot:getPixel(0, 0)
  testbed.center = string.format("%.2f/%.2f/%.2f/%.2f", cr, cg, cb, ca)
  testbed.spread = string.format("%.2f/%.2f/%.2f/%.2f", sr, sg, sb, sa)
  testbed.outside = string.format("%.2f/%.2f/%.2f/%.2f", orr, org, orb, ora)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['center'], '1.00/0.00/0.00/1.00');
      expect(snapshot['spread'], '1.00/0.00/0.00/1.00');
      expect(snapshot['outside'], '0.00/0.00/0.00/0.00');
    },
  );
}
