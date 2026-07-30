import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('love.graphics.setColor accepts table colors', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(2, 2, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  local color = { 1, 0.5, 0.25, 1.0 }
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", 0, 0, 2, 2)
  love.graphics.setCanvas()

  local r, g, b, a = canvas:newImageData():getPixel(1, 1)
  testbed.pixel = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
end
''');

    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['pixel'], '1.00/0.50/0.25/1.00');
  });
}
