import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

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
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        expect(
          ((await lualike.execute('''
return love.graphics.validateShader(false, [[
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
]])
''')) as Value)
              .unwrap(),
          isTrue,
        );
      },
    );

    test(
      'validateShader returns false plus a backend message for unsupported source',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        expect(
          ((await lualike.execute('''
return love.graphics.validateShader(false, [[
extern vec4 tint;
extern number intensity;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  vec4 base = Texel(texture, texture_coords) * color;
  return vec4(tint.rgb * intensity, tint.a) * base;
}
]])
''')) as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>[false, _unsupportedShaderMessage],
        );
      },
    );

    test(
      'validateShader uses the same unsupported path for vertex plus pixel overloads',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        expect(
          ((await lualike.execute('''
return love.graphics.validateShader(false, [[
vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition) {
  return clipSpaceFromLocal * localPosition;
}
]], [[
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return color * Texel(texture, texture_coords);
}
]])
''')) as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>[false, _unsupportedShaderMessage],
        );
      },
    );

    test(
      'validateShader returns true for registered Flutter fragment-asset shaders',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveFlameHarnessGame().host);

        expect(
          ((await lualike.execute('''
return love.graphics.validateShader(false, [[
$_registeredFragmentShaderSource
]])
''')) as Value)
              .unwrap(),
          isTrue,
        );
      },
    );

    test(
      'validateShader returns false when the Flutter host cannot load a registered fragment asset',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveFlameHarnessGame().host);

        final result = await lualike.execute('''
return love.graphics.validateShader(false, [[
$_missingRegisteredFragmentShaderSource
]])
''');

        expect(result, isA<List<Object?>>());
        final values = (result as List).map((e) => (e as Value).unwrap()).toList();
        expect(values.first, isFalse);
        expect(
          values[1],
          contains(
            'Could not load Flutter fragment shader asset "test_assets/shaders/does_not_exist.frag"',
          ),
        );
      },
    );

    test('validateShader preserves missing path-like string errors', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      await expectLater(
        lualike.execute('return love.graphics.validateShader(false, "shaders/missing.glsl")'),
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
