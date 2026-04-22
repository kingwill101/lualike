import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
import 'test_support/lua_api_test_helpers.dart';

const String _unsupportedShaderMessage =
    'love.graphics.validateShader cannot validate arbitrary runtime shader '
    'source on the Flutter backend yet; only the compatibility-emulated '
    'radial gradient and desaturation tint shader subsets plus registered '
    'Flutter fragment-asset shaders are currently supported';

const String _registeredFragmentShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: test_assets/shaders/runtime_effect_solid_color.frag
extern vec4 uColor;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return uColor;
}
''';

const String _missingRegisteredFragmentShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: test_assets/shaders/does_not_exist.frag
extern vec4 uColor;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return uColor;
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LOVE graphics shader validation parity', () {
    test(
      'validateShader returns true for the supported radial gradient subset',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final result = await luaCallList(
          runtime,
          const ['love', 'graphics', 'validateShader'],
          <Object?>[
            false,
            '''
extern number innerRadius;
extern number outerRadius;
extern vec2 center;
extern vec4 colorInner;
extern vec4 colorOuter;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  number dist = distance(screen_coords, center);
  number t = smoothstep(innerRadius, outerRadius, dist);
  return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
}
''',
          ],
        );

        expect(result, isTrue);
      },
    );

    test(
      'validateShader returns false plus a backend message for unsupported source',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final result = await luaCallList(
          runtime,
          const ['love', 'graphics', 'validateShader'],
          <Object?>[
            false,
            '''
extern vec4 tint;
extern number intensity;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  vec4 base = Texel(texture, texture_coords) * color;
  return vec4(tint.rgb * intensity, tint.a) * base;
}
''',
          ],
        );

        expect(result, <Object?>[false, _unsupportedShaderMessage]);
      },
    );

    test(
      'validateShader uses the same unsupported path for vertex plus pixel overloads',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final result = await luaCallList(
          runtime,
          const ['love', 'graphics', 'validateShader'],
          <Object?>[
            false,
            '''
vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition) {
  return clipSpaceFromLocal * localPosition;
}
''',
            '''
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return color * Texel(texture, texture_coords);
}
''',
          ],
        );

        expect(result, <Object?>[false, _unsupportedShaderMessage]);
      },
    );

    test(
      'validateShader returns true for registered Flutter fragment-asset shaders',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveFlameHarnessGame().host);

        final result = await luaCallList(
          runtime,
          const ['love', 'graphics', 'validateShader'],
          <Object?>[false, _registeredFragmentShaderSource],
        );

        expect(result, isTrue);
      },
    );

    test(
      'validateShader returns false when the Flutter host cannot load a registered fragment asset',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveFlameHarnessGame().host);

        final result = await luaCallList(
          runtime,
          const ['love', 'graphics', 'validateShader'],
          <Object?>[false, _missingRegisteredFragmentShaderSource],
        );

        expect(result, isA<List<Object?>>());
        expect((result as List<Object?>).first, isFalse);
        expect(
          result[1],
          contains(
            'Could not load Flutter fragment shader asset "test_assets/shaders/does_not_exist.frag"',
          ),
        );
      },
    );

    test('validateShader preserves missing path-like string errors', () {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        () => luaRawFunction(runtime, const [
          'love',
          'graphics',
          'validateShader',
        ]).call(const <Object?>[false, 'shaders/missing.glsl']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'Could not open file shaders/missing.glsl. Does not exist.',
            ),
          ),
        ),
      );
    });
  });
}
