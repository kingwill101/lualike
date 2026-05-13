import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

const String _flutterFragmentAssetShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag
extern vec4 uColor;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return color;
}
''';

void main() {
  group('Canvas software readback shader limits', () {
    test(
      'Canvas:newImageData rejects Flutter fragment-asset shaders with an explicit LuaError',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
canvas = love.graphics.newCanvas(2, 2, { readable = true })
shader = love.graphics.newShader([[
$_flutterFragmentAssetShaderSource
]])

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 2, 2)
  love.graphics.setShader()
  love.graphics.setCanvas()
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final canvas = runtime.unwrapGlobal('canvas');
        expect(
          () => luaCallMethodList(canvas, 'newImageData'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Canvas:newImageData does not yet support software readback of Flutter fragment-asset shaders',
              ),
            ),
          ),
        );
      },
    );

    test(
      'Canvas:newImageData rejects nested canvas snapshots that depend on Flutter fragment-asset shaders',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
source = love.graphics.newCanvas(2, 2, { readable = true })
target = love.graphics.newCanvas(2, 2, { readable = true })
shader = love.graphics.newShader([[
$_flutterFragmentAssetShaderSource
]])

function love.draw()
  love.graphics.setCanvas(source)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 2, 2)
  love.graphics.setShader()
  love.graphics.setCanvas()

  love.graphics.setCanvas(target)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.draw(source, 0, 0)
  love.graphics.setCanvas()
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final target = runtime.unwrapGlobal('target');
        expect(
          () => luaCallMethodList(target, 'newImageData'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Canvas:newImageData does not yet support software readback of Flutter fragment-asset shaders',
              ),
            ),
          ),
        );
      },
    );
  });
}
