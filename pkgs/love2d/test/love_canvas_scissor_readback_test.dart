import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('Canvas:newImageData preserves command scissor clipping', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setScissor(1, 1, 2, 2)
  love.graphics.setColor(1, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local or_, og, ob, oa = snapshot:getPixel(0, 0)
  local ir, ig, ib, ia = snapshot:getPixel(2, 2)
  testbed.outside = string.format("%.2f/%.2f/%.2f/%.2f", or_, og, ob, oa)
  testbed.inside = string.format("%.2f/%.2f/%.2f/%.2f", ir, ig, ib, ia)
end
''');

    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['outside'], '0.00/1.00/0.00/1.00');
    expect(snapshot['inside'], '1.00/0.00/0.00/1.00');
  });

  test('Canvas:newImageData preserves scissored clear output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 1, 0, 1)
  love.graphics.setScissor(1, 1, 2, 2)
  love.graphics.clear(1, 0, 0, 1)
  love.graphics.setScissor()
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local or_, og, ob, oa = snapshot:getPixel(0, 0)
  local ir, ig, ib, ia = snapshot:getPixel(2, 2)
  testbed.outside = string.format("%.2f/%.2f/%.2f/%.2f", or_, og, ob, oa)
  testbed.inside = string.format("%.2f/%.2f/%.2f/%.2f", ir, ig, ib, ia)
end
''');

    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['outside'], '0.00/1.00/0.00/1.00');
    expect(snapshot['inside'], '1.00/0.00/0.00/1.00');
  });
}
