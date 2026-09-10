import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('Canvas:newImageData preserves command color mask output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setColorMask(true, false, false, false)
  love.graphics.setColor(1, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setColorMask(true, true, true, true)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local r, g, b, a = snapshot:getPixel(2, 2)
  testbed.center = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
end
''');

    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['center'], '1.00/1.00/0.00/1.00');
  });

  test('Canvas:newImageData preserves clear color masks', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setColorMask(true, false, false, false)
  love.graphics.clear(1, 0, 0, 1)
  love.graphics.setColorMask(true, true, true, true)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local r, g, b, a = snapshot:getPixel(2, 2)
  testbed.center = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
end
''');

    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['center'], '1.00/1.00/0.00/1.00');
  });
}
