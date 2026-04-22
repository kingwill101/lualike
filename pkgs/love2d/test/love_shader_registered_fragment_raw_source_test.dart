import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

const String _rawRegisteredFragmentShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform float iTime;
uniform vec2 iResolution;
uniform sampler2D iChannel0;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / iResolution;
  fragColor = vec4(iTime / 10.0, uv.x, uv.y, 1.0);
}
''';

void main() {
  test(
    'newShader accepts raw Flutter fragment source with registered asset metadata',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
local shader = love.graphics.newShader([[
$_rawRegisteredFragmentShaderSource
]])
shader:send("iTime", 2.5)

function love.draw()
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 1, 1)
  love.graphics.setShader()
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final commands = runtime.context.graphics.commands
          .whereType<LoveRectangleCommand>()
          .toList(growable: false);
      expect(commands, hasLength(1));

      final shader = commands.single.shader;
      expect(shader, isNotNull);
      expect(
        shader!.flutterFragmentAssetKey,
        'packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag',
      );
      expect(shader.uniformDeclaration('iTime')?.typeName, 'float');
      expect(shader.uniformDeclaration('iResolution')?.typeName, 'vec2');
      expect(shader.uniformDeclaration('iChannel0')?.typeName, 'sampler2d');
      expect(shader.uniform('iTime'), 2.5);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
