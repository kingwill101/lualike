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
    'Canvas:newImageData preserves radial gradient shader output for textured meshes',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local source = love.image.newImageData(1, 1)
source:setPixel(0, 0, 1, 0, 0, 1)
local image = love.graphics.newImage(source)
local mesh = love.graphics.newMesh({
  {0, 0, 0, 0},
  {10, 0, 1, 0},
  {10, 10, 1, 1},
  {0, 10, 0, 1},
}, "fan", "static")
mesh:setTexture(image)
local canvas = love.graphics.newCanvas(10, 10, { readable = true })
local shader = love.graphics.newShader([[
$_radialGradientShaderSource
]])

shader:send("innerRadius", 0)
shader:send("outerRadius", 4.5)
shader:send("center", {5.5, 5.5})
shader:send("colorInner", {1, 1, 1, 1})
shader:send("colorOuter", {0, 0, 0, 1})

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setShader(shader)
  love.graphics.draw(mesh, 0, 0)
  love.graphics.setShader()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local cr, cg, cb, ca = snapshot:getPixel(5, 5)
  local er, eg, eb, ea = snapshot:getPixel(0, 5)
  testbed.center = string.format("%.2f/%.2f/%.2f/%.2f", cr, cg, cb, ca)
  testbed.edge = string.format("%.2f/%.2f/%.2f/%.2f", er, eg, eb, ea)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['center'], '1.00/0.00/0.00/1.00');
      expect(snapshot['edge'], '0.00/0.00/0.00/1.00');
    },
  );
}
