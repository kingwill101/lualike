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
  group('Canvas shader scissor readback', () {
    test(
      'Canvas:newImageData preserves desaturation shader output under scissor clipping',
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
$_desaturationTintShaderSource
]])

shader:send("tint", {1, 1, 1, 1 / 0.299})
shader:send("strength", 1)

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setScissor(3, 3, 4, 4)
  love.graphics.setShader(shader)
  love.graphics.draw(image, 0, 0)
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local or_, og, ob, oa = snapshot:getPixel(0, 0)
  local ir, ig, ib, ia = snapshot:getPixel(5, 5)
  testbed.outside = string.format("%.2f/%.2f/%.2f/%.2f", or_, og, ob, oa)
  testbed.inside = string.format("%.2f/%.2f/%.2f/%.2f", ir, ig, ib, ia)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['outside'], '0.00/1.00/0.00/1.00');
        expect(snapshot['inside'], '0.30/0.30/0.30/1.00');
      },
    );

    test(
      'Canvas:newImageData preserves radial gradient image shader output under scissor clipping',
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
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setScissor(3, 3, 4, 4)
  love.graphics.setShader(shader)
  love.graphics.draw(image, 0, 0)
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local or_, og, ob, oa = snapshot:getPixel(0, 5)
  local ir, ig, ib, ia = snapshot:getPixel(5, 5)
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

    test(
      'Canvas:newImageData preserves radial gradient points shader output under scissor clipping',
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
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setPointSize(8)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.setScissor(4, 4, 2, 2)
  love.graphics.setShader(shader)
  love.graphics.points(5, 5)
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local or_, og, ob, oa = snapshot:getPixel(1, 5)
  local ir, ig, ib, ia = snapshot:getPixel(5, 5)
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
  });
}
