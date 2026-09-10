import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('Canvas:newImageData preserves textured mesh output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local texture = love.image.newImageData(2, 2)
texture:setPixel(0, 0, 1, 0, 0, 1)
texture:setPixel(1, 0, 0, 1, 0, 1)
texture:setPixel(0, 1, 0, 0, 1, 1)
texture:setPixel(1, 1, 1, 1, 1, 1)

local image = love.graphics.newImage(texture)
local mesh = love.graphics.newMesh({
  {0, 0, 0, 0, 1, 1, 1, 1},
  {10, 0, 1, 0, 1, 1, 1, 1},
  {10, 10, 1, 1, 1, 1, 1, 1},
  {0, 10, 0, 1, 1, 1, 1, 1},
}, "fan", "static")
mesh:setTexture(image)

local canvas = love.graphics.newCanvas(10, 10, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(mesh)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local tlr, tlg, tlb, tla = snapshot:getPixel(2, 2)
  local trr, trg, trb, tra = snapshot:getPixel(7, 2)
  local blr, blg, blb, bla = snapshot:getPixel(2, 7)
  local brr, brg, brb, bra = snapshot:getPixel(7, 7)
  testbed.tl = string.format("%.2f/%.2f/%.2f/%.2f", tlr, tlg, tlb, tla)
  testbed.tr = string.format("%.2f/%.2f/%.2f/%.2f", trr, trg, trb, tra)
  testbed.bl = string.format("%.2f/%.2f/%.2f/%.2f", blr, blg, blb, bla)
  testbed.br = string.format("%.2f/%.2f/%.2f/%.2f", brr, brg, brb, bra)
end
''');

    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['tl'], '1.00/0.00/0.00/1.00');
    expect(snapshot['tr'], '0.00/1.00/0.00/1.00');
    expect(snapshot['bl'], '0.00/0.00/1.00/1.00');
    expect(snapshot['br'], '1.00/1.00/1.00/1.00');
  });
}
