import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

const String _unsupportedShaderMessage =
    'love.graphics.validateShader cannot validate arbitrary runtime shader '
    'source on the Flutter backend yet; only the compatibility-emulated '
    'radial gradient and desaturation tint shader subsets plus registered '
    'Flutter fragment-asset shaders are currently supported';

const String _registeredFragmentShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag
extern vec4 uColor;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return uColor;
}
''';

void main() {
  group('LOVE graphics shader validation parity', () {
    test(
      'validateShader returns true for the supported radial gradient subset',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final result = await _call(
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

        final result = await _call(
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

        final result = await _call(
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
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final result = await _call(
          runtime,
          const ['love', 'graphics', 'validateShader'],
          <Object?>[false, _registeredFragmentShaderSource],
        );

        expect(result, isTrue);
      },
    );

    test('validateShader preserves missing path-like string errors', () {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        () => _rawFunction(runtime, const [
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

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
