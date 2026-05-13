import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE graphics shader code to GLSL parity', () {
    test('_shaderCodeToGLSL translates pixel-only LOVE shader code', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final result = await luaCall(
        runtime,
        const ['love', 'graphics', '_shaderCodeToGLSL'],
        <Object?>[
          false,
          '''
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  return color * Texel(tex, tc);
}
''',
        ],
      );

      expect(result, isA<List<Object?>>());
      final values = result as List<Object?>;
      expect(values[0], isNull);

      final pixelCode = values[1] as String;
      expect(pixelCode, contains('#version 330 core'));
      expect(pixelCode, contains('#define PIXEL PIXEL'));
      expect(pixelCode, contains('#define LOVE_GLSL1_ON_GLSL3 1'));
      expect(pixelCode, contains('uniform sampler2D MainTex;'));
      expect(
        pixelCode,
        contains('vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc)'),
      );
      expect(pixelCode, contains('#line 0'));
    });

    test(
      '_shaderCodeToGLSL classifies vertex and pixel stages regardless of argument order',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final result = await luaCall(
          runtime,
          const ['love', 'graphics', '_shaderCodeToGLSL'],
          <Object?>[
            true,
            '''
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  return color * Texel(tex, tc);
}
''',
            '''
vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition) {
  return clipSpaceFromLocal * localPosition;
}
''',
          ],
        );

        expect(result, isA<List<Object?>>());
        final values = result as List<Object?>;
        final vertexCode = values[0] as String;
        final pixelCode = values[1] as String;

        expect(vertexCode, contains('#version 300 es'));
        expect(vertexCode, contains('#define VERTEX VERTEX'));
        expect(vertexCode, contains('attribute vec4 VertexPosition;'));
        expect(vertexCode, contains('vec4 position(mat4 clipSpaceFromLocal'));

        expect(pixelCode, contains('#version 300 es'));
        expect(pixelCode, contains('#define PIXEL PIXEL'));
        expect(pixelCode, contains('uniform sampler2D MainTex;'));
        expect(pixelCode, contains('vec4 effect(vec4 color, Image tex'));
      },
    );

    test(
      '_shaderCodeToGLSL emits custom multi-canvas pixel scaffolding',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final result = await luaCall(
          runtime,
          const ['love', 'graphics', '_shaderCodeToGLSL'],
          <Object?>[
            false,
            '''
void effect() {
  love_Canvases[0] = vec4(1.0);
  love_Canvases[1] = vec4(0.0);
}
''',
          ],
        );

        final pixelCode = (result as List<Object?>)[1] as String;
        expect(pixelCode, contains('#define LOVE_MULTI_CANVAS 1'));
        expect(
          pixelCode,
          contains('layout(location = 0) out vec4 love_Canvases'),
        );
        expect(pixelCode, contains('void effect();'));
      },
    );

    test('_shaderCodeToGLSL rejects mismatched shader language pragmas', () {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        () =>
            luaRawFunction(runtime, const [
              'love',
              'graphics',
              '_shaderCodeToGLSL',
            ]).call(<Object?>[
              false,
              '''
#pragma language glsl1
vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition) {
  return clipSpaceFromLocal * localPosition;
}
''',
              '''
#pragma language glsl3
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  return color;
}
''',
            ]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('vertex and pixel shader languages must match'),
          ),
        ),
      );
    });

    test('_shaderCodeToGLSL rejects invalid shader language pragmas', () {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        () =>
            luaRawFunction(runtime, const [
              'love',
              'graphics',
              '_shaderCodeToGLSL',
            ]).call(<Object?>[
              false,
              '''
#pragma language banana
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  return color;
}
''',
            ]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Invalid shader language: banana'),
          ),
        ),
      );
    });
  });
}
