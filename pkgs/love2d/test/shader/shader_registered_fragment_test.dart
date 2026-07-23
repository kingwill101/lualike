import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

const String _registeredTextureShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: packages/love2d/test_assets/shaders/runtime_effect_uniform_texture.frag
extern Image uTexture;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return Texel(uTexture, vec2(0.5, 0.5));
}
''';

void main() {
  group('Registered fragment shaders', () {
    test('LoveShader extracts the registered Flutter asset key', () {
      final shader = LoveShader.fromSource(_registeredTextureShaderSource);
      expect(
        shader.flutterFragmentAssetKey,
        'packages/love2d/test_assets/shaders/runtime_effect_uniform_texture.frag',
      );
    });

    test(
      'newShader accepts registered fragment metadata and sampler uploads',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
function love.draw()
  local imageData = love.image.newImageData(1, 1)
  imageData:setPixel(0, 0, 1, 0, 0, 1)
  local image = love.graphics.newImage(imageData)
  local canvas = love.graphics.newCanvas(1, 1)

  local imageShader = love.graphics.newShader([[
$_registeredTextureShaderSource
  ]])
  imageShader:send("uTexture", image)
  love.graphics.setShader(imageShader)
  love.graphics.rectangle("fill", 0, 0, 1, 1)

  local canvasShader = love.graphics.newShader([[
$_registeredTextureShaderSource
  ]])
  canvasShader:send("uTexture", canvas)
  love.graphics.setShader(canvasShader)
  love.graphics.rectangle("fill", 1, 0, 1, 1)

  love.graphics.setShader()
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final commands = runtime.context.graphics.commands
            .whereType<LoveRectangleCommand>()
            .toList(growable: false);
        expect(commands, hasLength(2));

        final imageUniform = commands.first.shader!.uniform('uTexture');
        expect(
          commands.first.shader!.flutterFragmentAssetKey,
          'packages/love2d/test_assets/shaders/runtime_effect_uniform_texture.frag',
        );
        expect(imageUniform, isA<LoveImage>());
        expect(imageUniform, isNot(isA<LoveCanvas>()));

        final canvasUniform = commands.last.shader!.uniform('uTexture');
        expect(canvasUniform, isA<LoveCanvas>());
      },
    );

    test(
      'registered fragment sampler uploads still type-check non-texture payloads',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await expectLater(
          runtime.execute('''
local shader = love.graphics.newShader([[
$_registeredTextureShaderSource
]])
shader:send("uTexture", 1)
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send expected an Image or Canvas for sampler uniform values',
              ),
            ),
          ),
        );
      },
    );
  });
}
