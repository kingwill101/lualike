import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test(
    'Canvas:newImageData preserves premultiplied multiply blend mode output',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setBlendMode("multiply", "premultiplied")
  love.graphics.setColor(0.5, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
      expect(snapshot['center'], '0.50/0.00/0.00/0.50');
    },
  );

  test('Canvas:newImageData preserves screen blend mode output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.4, 0.3, 0.2, 1)
  love.graphics.setBlendMode("screen")
  love.graphics.setColor(0.8, 0.1, 0.05, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
    expect(snapshot['center'], '0.48/0.32/0.21/1.00');
  });

  test('Canvas:newImageData preserves replace blend mode output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
    expect(snapshot['center'], '0.50/0.00/0.00/0.50');
  });

  test('Canvas:newImageData preserves none blend mode output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("none")
  love.graphics.setColor(1, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
    expect(snapshot['center'], '1.00/0.00/0.00/0.50');
  });

  test('Canvas:newImageData preserves add blend mode output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
    expect(snapshot['center'], '0.50/0.00/0.00/0.00');
  });

  test('Canvas:newImageData preserves subtract blend mode output', () async {
    final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

    await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setBlendMode("subtract")
  love.graphics.setColor(1, 0, 0, 0.25)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
    expect(snapshot['center'], '0.75/1.00/1.00/1.00');
  });

  test(
    'Canvas:newImageData preserves premultiplied lighten blend mode output',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.3, 0.4, 0.2, 0.6)
  love.graphics.setBlendMode("lighten", "premultiplied")
  love.graphics.setColor(0.5, 0.1, 0.25, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
      expect(snapshot['center'], '0.50/0.40/0.25/0.60');
    },
  );

  test(
    'Canvas:newImageData preserves premultiplied darken blend mode output',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.3, 0.4, 0.2, 0.6)
  love.graphics.setBlendMode("darken", "premultiplied")
  love.graphics.setColor(0.5, 0.1, 0.25, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
      expect(snapshot['center'], '0.30/0.10/0.20/0.50');
    },
  );

  test(
    'Canvas:newImageData preserves premultiplied alpha blend mode output',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}
local canvas = love.graphics.newCanvas(4, 4, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(0.5, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setBlendMode("alpha")
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
      expect(snapshot['center'], '0.50/0.00/0.00/1.00');
    },
  );
}
