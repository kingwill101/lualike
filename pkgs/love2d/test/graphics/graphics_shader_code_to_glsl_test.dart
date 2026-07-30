import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE graphics shader code to GLSL parity', () {
    test('_shaderCodeToGLSL translates pixel-only LOVE shader code', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final shaderCodeToGlsl =
          await lualike.execute('return love.graphics._shaderCodeToGLSL') as Value;
      final values = (await shaderCodeToGlsl.call(<Object?>[
        false,
        'vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {\n'
            '  return color * Texel(tex, tc);\n'
            '}',
      ])) as Value;

      final results = values.unwrap() as List<Object?>;
      expect(results[0], isNull);

      final pixelCode = results[1] as String;
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
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final shaderCodeToGlsl =
            await lualike.execute('return love.graphics._shaderCodeToGLSL') as Value;
        final values = (await shaderCodeToGlsl.call(<Object?>[
          true,
          'vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {\n'
              '  return color * Texel(tex, tc);\n'
              '}',
          'vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition) {\n'
              '  return clipSpaceFromLocal * localPosition;\n'
              '}',
        ])) as Value;

        final results = values.unwrap() as List<Object?>;
        final vertexCode = results[0] as String;
        final pixelCode = results[1] as String;

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
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final shaderCodeToGlsl =
            await lualike.execute('return love.graphics._shaderCodeToGLSL') as Value;
        final values = (await shaderCodeToGlsl.call(<Object?>[
          false,
          'void effect() {\n'
              '  love_Canvases[0] = vec4(1.0);\n'
              '  love_Canvases[1] = vec4(0.0);\n'
              '}',
        ])) as Value;

        final pixelCode = (values.unwrap() as List<Object?>)[1] as String;
        expect(pixelCode, contains('#define LOVE_MULTI_CANVAS 1'));
        expect(
          pixelCode,
          contains('layout(location = 0) out vec4 love_Canvases'),
        );
        expect(pixelCode, contains('void effect();'));
      },
    );

    test('_shaderCodeToGLSL rejects mismatched shader language pragmas', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
      final shaderCodeToGlsl =
          await lualike.execute('return love.graphics._shaderCodeToGLSL') as Value;

      await expectLater(
        shaderCodeToGlsl.call(<Object?>[
          false,
          '#pragma language glsl1\n'
              'vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition) {\n'
              '  return clipSpaceFromLocal * localPosition;\n'
              '}',
          '#pragma language glsl3\n'
              'vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {\n'
              '  return color;\n'
              '}',
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

    test('_shaderCodeToGLSL rejects invalid shader language pragmas', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
      final shaderCodeToGlsl =
          await lualike.execute('return love.graphics._shaderCodeToGLSL') as Value;

      await expectLater(
        shaderCodeToGlsl.call(<Object?>[
          false,
          '#pragma language banana\n'
              'vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {\n'
              '  return color;\n'
              '}',
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
