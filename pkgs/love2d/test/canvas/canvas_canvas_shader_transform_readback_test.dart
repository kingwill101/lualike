import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

const String _radialGradientShaderSource = '''
extern number innerRadius;
extern number outerRadius;
extern vec2 center;
extern vec4 colorInner;
extern vec4 colorOuter;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  number dist = distance(screen_coords, center);
  number t = smoothstep(innerRadius, outerRadius, dist);
  return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
}
''';

void main() {
  test(
    'Canvas:newImageData preserves transformed canvas snapshot radial shader output',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local source = love.graphics.newCanvas(4, 4, { readable = true })
local target = love.graphics.newCanvas(8, 4, { readable = true })
local shader = love.graphics.newShader([[
$_radialGradientShaderSource
]])

shader:send("innerRadius", 0)
shader:send("outerRadius", 1.5)
shader:send("center", {5.5, 1.5})
shader:send("colorInner", {1, 1, 1, 1})
shader:send("colorOuter", {0, 0, 0, 1})

function love.draw()
  love.graphics.setCanvas(source)
  love.graphics.clear(1, 0, 0, 1)
  love.graphics.setCanvas()

  love.graphics.setCanvas(target)
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.draw(source, 4, 0)
  love.graphics.setShader()
  love.graphics.setCanvas()

  local snapshot = target:newImageData()
  local or_, og, ob, oa = snapshot:getPixel(1, 1)
  local ir, ig, ib, ia = snapshot:getPixel(5, 1)
  testbed.outside = string.format("%.2f/%.2f/%.2f/%.2f", or_, og, ob, oa)
  testbed.inside = string.format("%.2f/%.2f/%.2f/%.2f", ir, ig, ib, ia)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['outside'], '0.00/1.00/0.00/1.00');
      expect(snapshot['inside'], '1.00/0.00/0.00/1.00');
    },
  );
}
