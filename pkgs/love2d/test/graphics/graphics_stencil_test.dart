import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics.stencil', () {
    test(
      'writes stencil values without color by default and masks later canvas draws',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", 0, 0, 2, 4)
  end, "replace", 1, false)
  love.graphics.setCanvas()

  local before = canvas:newImageData()
  local br, bg, bb, ba = before:getPixel(0, 1)
  testbed.before = string.format("%.1f/%.1f/%.1f/%.1f", br, bg, bb, ba)

  love.graphics.setCanvas(canvas)
  love.graphics.setStencilTest("greater", 0)
  love.graphics.setColor(1, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setStencilTest()
  love.graphics.setCanvas()

  local after = canvas:newImageData()
  local lr, lg, lb, la = after:getPixel(0, 1)
  local rr, rg, rb, ra = after:getPixel(3, 1)
  testbed.left = string.format("%.1f/%.1f/%.1f/%.1f", lr, lg, lb, la)
  testbed.right = string.format("%.1f/%.1f/%.1f/%.1f", rr, rg, rb, ra)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['before'], '0.0/0.0/0.0/0.0');
        expect(snapshot['left'], '1.0/0.0/0.0/1.0');
        expect(snapshot['right'], '0.0/0.0/0.0/0.0');
      },
    );

    test('supports keepvalues with increment stencil actions', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", 0.1, 0.1, 1.8, 3.8)
  end, "replace", 1, false)
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", 1.1, 0.1, 0.8, 3.8)
  end, "increment", 0, true)
  love.graphics.setStencilTest("equal", 2)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setStencilTest()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local ar, ag, ab, aa = snapshot:getPixel(0, 1)
  local br, bg, bb, ba = snapshot:getPixel(1, 1)
  local cr, cg, cb, ca = snapshot:getPixel(2, 1)
  testbed.a = string.format("%.1f/%.1f/%.1f/%.1f", ar, ag, ab, aa)
  testbed.b = string.format("%.1f/%.1f/%.1f/%.1f", br, bg, bb, ba)
  testbed.c = string.format("%.1f/%.1f/%.1f/%.1f", cr, cg, cb, ca)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['a'], '0.0/0.0/0.0/0.0');
      expect(snapshot['b'], '0.0/1.0/0.0/1.0');
      expect(snapshot['c'], '0.0/0.0/0.0/0.0');
    });
  });
}
