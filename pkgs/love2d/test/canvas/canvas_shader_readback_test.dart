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

const String _desaturationTintShaderSource = '''
extern vec4 tint;
extern number strength;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
  color = Texel(texture, tc);
  number luma = dot(vec3(0.299f, 0.587f, 0.114f), color.rgb);
  return mix(color, tint * luma, strength);
}
''';

void main() {
  group('Canvas shader readback', () {
    test(
      'Canvas:newImageData preserves radial gradient shader output for filled shapes',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(8, 8, { readable = true })
local shader = love.graphics.newShader([[
$_radialGradientShaderSource
]])

shader:send("innerRadius", 0)
shader:send("outerRadius", 4)
shader:send("center", {4.5, 4.5})
shader:send("colorInner", {1, 0, 0, 1})
shader:send("colorOuter", {0, 0, 1, 1})

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 8, 8)
  love.graphics.setShader()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local cr, cg, cb, ca = snapshot:getPixel(4, 4)
  local er, eg, eb, ea = snapshot:getPixel(0, 4)
  testbed.center = string.format("%.2f/%.2f/%.2f/%.2f", cr, cg, cb, ca)
  testbed.edge = string.format("%.2f/%.2f/%.2f/%.2f", er, eg, eb, ea)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['center'], '1.00/0.00/0.00/1.00');
        expect(snapshot['edge'], '0.00/0.00/1.00/1.00');
      },
    );

    test(
      'Canvas:newImageData preserves radial gradient shader output for image draws',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}
local source = love.image.newImageData(10, 10)
for y = 0, 9 do
  for x = 0, 9 do
    source:setPixel(x, y, 1, 0, 0, 1)
  end
end
local image = love.graphics.newImage(source)
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
  love.graphics.draw(image, 0, 0)
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

    test(
      'Canvas:newImageData preserves radial gradient shader output for points',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(10, 10, { readable = true })
local shader = love.graphics.newShader([[
$_radialGradientShaderSource
]])

shader:send("innerRadius", 0)
shader:send("outerRadius", 4)
shader:send("center", {5.5, 5.5})
shader:send("colorInner", {1, 0, 0, 1})
shader:send("colorOuter", {0, 0, 1, 1})

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setPointSize(8)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.points(5, 5)
  love.graphics.setShader()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local cr, cg, cb, ca = snapshot:getPixel(5, 5)
  local er, eg, eb, ea = snapshot:getPixel(1, 5)
  testbed.center = string.format("%.2f/%.2f/%.2f/%.2f", cr, cg, cb, ca)
  testbed.edge = string.format("%.2f/%.2f/%.2f/%.2f", er, eg, eb, ea)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['center'], '1.00/0.00/0.00/1.00');
        expect(snapshot['edge'], '0.00/0.00/1.00/1.00');
      },
    );

    test(
      'Canvas:newImageData preserves desaturation tint shader output for image draws',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}
local source = love.image.newImageData(1, 1)
source:setPixel(0, 0, 1, 0, 0, 1)
local image = love.graphics.newImage(source)
local canvas = love.graphics.newCanvas(1, 1, { readable = true })
local shader = love.graphics.newShader([[
$_desaturationTintShaderSource
]])

shader:send("tint", {1, 1, 1, 1 / 0.299})
shader:send("strength", 1)

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setShader(shader)
  love.graphics.draw(image, 0, 0)
  love.graphics.setShader()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local r, g, b, a = snapshot:getPixel(0, 0)
  testbed.pixel = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['pixel'], '0.30/0.30/0.30/1.00');
      },
    );
  });
}
