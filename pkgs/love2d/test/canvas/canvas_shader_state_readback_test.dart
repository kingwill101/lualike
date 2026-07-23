import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

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
  group('Canvas shader state readback', () {
    test(
      'Canvas:newImageData preserves desaturation shader output with replace blend mode',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}
local source = love.image.newImageData(1, 1)
source:setPixel(0, 0, 1, 0, 0, 0.5)
local image = love.graphics.newImage(source)
local canvas = love.graphics.newCanvas(1, 1, { readable = true })
local shader = love.graphics.newShader([[
$_desaturationTintShaderSource
]])

shader:send("tint", {1, 1, 1, 0.5 / 0.299})
shader:send("strength", 1)

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("replace")
  love.graphics.setShader(shader)
  love.graphics.draw(image, 0, 0)
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha")
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local r, g, b, a = snapshot:getPixel(0, 0)
  testbed.pixel = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['pixel'], '0.15/0.15/0.15/0.50');
      },
    );

    test(
      'Canvas:newImageData preserves desaturation shader output with color masks',
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
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setColorMask(true, false, false, false)
  love.graphics.setShader(shader)
  love.graphics.draw(image, 0, 0)
  love.graphics.setShader()
  love.graphics.setColorMask(true, true, true, true)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local r, g, b, a = snapshot:getPixel(0, 0)
  testbed.pixel = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['pixel'], '0.30/1.00/0.00/1.00');
      },
    );
  });
}
